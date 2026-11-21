import asyncio
import ipaddress
import os
import socket
from collections import deque
from typing import Any
from urllib.parse import urljoin, urlparse, urldefrag

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, field_validator


UPSTREAM = os.environ.get("CRAWL4AI_UPSTREAM", "http://crawl4ai:11235")
TOKEN = os.environ.get("CRAWL4AI_API_TOKEN", "")
MAX_CONCURRENCY = int(os.environ.get("CRAWL4AI_MAX_CONCURRENCY", "2"))
UPSTREAM_TIMEOUT_SECONDS = float(
    os.environ.get("CRAWL4AI_UPSTREAM_TIMEOUT_SECONDS", "180")
)
SITE_CRAWL_TIMEOUT_SECONDS = float(
    os.environ.get("CRAWL4AI_SITE_TIMEOUT_SECONDS", "900")
)

MAX_SITE_DEPTH = 5
MAX_SITE_PAGES_HARD = 500

if not TOKEN:
    raise RuntimeError("CRAWL4AI_API_TOKEN is required")

if MAX_CONCURRENCY < 1:
    raise RuntimeError("CRAWL4AI_MAX_CONCURRENCY must be >= 1")

crawl_semaphore = asyncio.Semaphore(MAX_CONCURRENCY)

app = FastAPI(
    title="@@BRAND@@ Crawl4AI API",
    version="0.3.2",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


def validate_url_shape(url: str) -> None:
    parsed = urlparse(url)

    if parsed.scheme not in ("http", "https"):
        raise ValueError("only http:// and https:// URLs are allowed")

    if not parsed.hostname:
        raise ValueError("URL hostname is required")


class CrawlRequest(BaseModel):
    urls: list[str] = Field(min_length=1, max_length=10)

    @field_validator("urls")
    @classmethod
    def validate_urls(cls, urls: list[str]) -> list[str]:
        for url in urls:
            validate_url_shape(url)
        return urls


class SiteCrawlRequest(BaseModel):
    url: str
    max_depth: int = Field(default=1, ge=0, le=MAX_SITE_DEPTH)
    max_pages: int | None = Field(
        default=None,
        ge=1,
        le=MAX_SITE_PAGES_HARD,
    )
    query: str | None = Field(default=None, max_length=200)

    @field_validator("url")
    @classmethod
    def validate_url(cls, url: str) -> str:
        validate_url_shape(url)
        return url

    @field_validator("query")
    @classmethod
    def normalize_query(cls, query: str | None) -> str | None:
        if query is None:
            return None

        query = query.strip()
        return query or None


def is_forbidden_ip(address: str) -> bool:
    ip = ipaddress.ip_address(address)

    return (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
    )


async def validate_public_destination(url: str) -> None:
    parsed = urlparse(url)
    hostname = parsed.hostname

    if not hostname:
        raise HTTPException(status_code=400, detail=f"invalid URL: {url}")

    if hostname.lower() == "localhost":
        raise HTTPException(
            status_code=400,
            detail=f"private/local destinations are not allowed: {url}",
        )

    try:
        infos = await asyncio.to_thread(
            socket.getaddrinfo,
            hostname,
            parsed.port or (443 if parsed.scheme == "https" else 80),
            type=socket.SOCK_STREAM,
        )
    except socket.gaierror as exc:
        raise HTTPException(
            status_code=400,
            detail=f"unable to resolve hostname: {hostname}",
        ) from exc

    addresses = {info[4][0] for info in infos}

    if not addresses:
        raise HTTPException(
            status_code=400,
            detail=f"unable to resolve hostname: {hostname}",
        )

    for address in addresses:
        try:
            if is_forbidden_ip(address):
                raise HTTPException(
                    status_code=400,
                    detail=f"private/local destinations are not allowed: {url}",
                )
        except ValueError:
            continue


async def call_upstream(urls: list[str]) -> dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    }

    async with crawl_semaphore:
        try:
            async with httpx.AsyncClient(
                timeout=UPSTREAM_TIMEOUT_SECONDS
            ) as client:
                response = await client.post(
                    f"{UPSTREAM}/crawl",
                    headers=headers,
                    json={"urls": urls},
                )
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"upstream error: {exc}",
            ) from exc

    if response.status_code >= 400:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.text[:2000],
        )

    return response.json()


def normalize_url(url: str) -> str:
    url, _ = urldefrag(url)
    parsed = urlparse(url)

    path = parsed.path or "/"

    return parsed._replace(
        scheme=parsed.scheme.lower(),
        netloc=parsed.netloc.lower(),
        path=path,
    ).geturl()


def same_site(seed_url: str, candidate_url: str) -> bool:
    seed = urlparse(seed_url)
    candidate = urlparse(candidate_url)

    return (
        candidate.scheme in ("http", "https")
        and candidate.hostname is not None
        and seed.hostname is not None
        and candidate.hostname.lower() == seed.hostname.lower()
    )


def link_score(url: str, text: str, query: str | None) -> int:
    if not query:
        return 0

    terms = [term.lower() for term in query.split() if term.strip()]
    haystack = f"{url} {text}".lower()

    return sum(1 for term in terms if term in haystack)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "@@PFX@@-crawl4ai-api",
        "api": "0.3.2",
        "max_concurrency": MAX_CONCURRENCY,
        "site_crawl": {
            "max_depth_hard": MAX_SITE_DEPTH,
            "max_pages_hard": MAX_SITE_PAGES_HARD,
            "timeout_seconds": SITE_CRAWL_TIMEOUT_SECONDS,
            "max_pages_optional": True,
        },
    }


@app.post("/crawl")
async def crawl(req: CrawlRequest) -> Any:
    for url in req.urls:
        await validate_public_destination(url)

    return await call_upstream(req.urls)


@app.post("/crawl/site")
async def crawl_site(req: SiteCrawlRequest) -> Any:
    seed_url = normalize_url(req.url)
    await validate_public_destination(seed_url)

    effective_page_limit = (
        req.max_pages
        if req.max_pages is not None
        else MAX_SITE_PAGES_HARD
    )

    queue = deque([(seed_url, 0)])
    queued = {seed_url}
    visited: set[str] = set()
    collected: list[dict[str, Any]] = []

    timed_out = False

    try:
        async with asyncio.timeout(SITE_CRAWL_TIMEOUT_SECONDS):
            while queue and len(collected) < effective_page_limit:
                current_url, depth = queue.popleft()

                if current_url in visited:
                    continue

                visited.add(current_url)

                await validate_public_destination(current_url)

                payload = await call_upstream([current_url])
                results = payload.get("results", [])

                if not results:
                    continue

                result = results[0]
                collected.append(result)

                if depth >= req.max_depth:
                    continue

                candidates: list[tuple[int, str]] = []

                links = result.get("links") or {}
                internal_links = links.get("internal") or []

                for link in internal_links:
                    href = link.get("href")
                    if not href:
                        continue

                    absolute = normalize_url(urljoin(current_url, href))

                    if not same_site(seed_url, absolute):
                        continue

                    if absolute in visited or absolute in queued:
                        continue

                    score = link_score(
                        absolute,
                        str(link.get("text") or ""),
                        req.query,
                    )

                    candidates.append((score, absolute))

                candidates.sort(key=lambda item: (-item[0], item[1]))

                for _, candidate in candidates:
                    if (
                        len(queued) + len(visited)
                        >= MAX_SITE_PAGES_HARD * 5
                    ):
                        break

                    queued.add(candidate)
                    queue.append((candidate, depth + 1))

    except TimeoutError:
        timed_out = True

    return {
        "success": True,
        "seed_url": seed_url,
        "query": req.query,
        "max_depth": req.max_depth,
        "max_pages_requested": req.max_pages,
        "server_page_ceiling": MAX_SITE_PAGES_HARD,
        "pages_crawled": len(collected),
        "timed_out": timed_out,
        "queue_remaining": len(queue),
        "results": collected,
    }
