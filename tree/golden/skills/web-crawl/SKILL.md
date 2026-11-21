---
name: web-crawl
description: 웹 페이지를 수집하고 같은 사이트 내부 링크를 따라가며 필요한 페이지를 찾아 Markdown으로 정리한다. 웹 조사, 자료 수집, 사이트 탐색, 본문 추출, RAG 입력 자료 준비 요청에 사용한다. 인터넷 전체 검색은 하지 않고, 로그인·클릭·폼 입력은 브라우저 자동화 Skill로 넘긴다.
---

# Web Crawl

Collect web pages as Markdown, keep the source with the text, and hand off
anything that needs interaction.

## Route the request first

Pick the capability by what the task actually needs:

- **A page whose address you already have** — use the @@BRAND@@ crawl service's
  page operation (`crawl4ai_crawl`; `crawl4ai_health` reports service state).
  It returns the rendered content as Markdown. No token or header is supplied
  by the user.
- **Pages you still have to find inside one site** — use the site operation
  (`crawl4ai_site`). It follows internal links on the same site, deduplicates
  what it finds, and accepts a query so that links related to the question are
  visited first. Depth defaults to one level; ask for more only when the
  material is actually nested.
- **Finding which site to read in the first place** — that is internet-wide
  search, which this service does not do. Choose the sites yourself or with a
  web search tool, then crawl them.
- **Operating a page** — logging in, clicking, filling forms, or anything that
  depends on session state: use the browser automation Skill
  (`agent-browser`). Do not attempt it with the crawler.
- **A local file** — DOCX, XLSX, PPTX, HTML, TXT: convert it instead of
  crawling.
- **A Korean official document** — PDF, HWP, HWPX, 공문서: use the Korean
  document service, not a converter and not the crawler.

State the chosen route when it is not obvious, and switch route rather than
retrying a capability that is structurally wrong for the task.

The crawl service is an API first: the tools above are an adapter in front of
it. When the task is a script or a scheduled collector rather than a one-off
request, call the central crawl API directly from inside the development
environment instead of driving it through a tool call.

## Before crawling

- Confirm the target is a public page the user is entitled to read.
- Prefer the primary or official source over an aggregator when both exist.
- Do not route around a login wall, paywall, or explicit access restriction.
- Keep the number of pages proportional to the question being answered.

## Collecting

- Retrieve the page, then keep the Markdown together with its source URL and
  the retrieval date.
- Preserve tables and headings; do not summarize while collecting.
- Record the exact URL that produced each block of text, including redirects
  that changed the final address.
- When a page fails or returns no usable text, record the failure instead of
  silently dropping the source.
- A site run returns several pages at once. Keep them as separate documents
  with their own URLs rather than concatenating the site into one blob, and say
  how many pages were actually visited.

## Verifying

- Cross-check any claim that carries weight against a second source, or
  against the primary source the page cites.
- Separate what the source states from your inference about it.
- Mark disagreement between sources explicitly; do not average conflicting
  numbers into one.
- Note the publication or revision date when currency matters to the answer.

## Reporting

Deliver:

1. the answer or the extracted material, with the source next to each claim;
2. a source list with URL and retrieval date;
3. pages that failed or were skipped, with the reason;
4. what still needs a human check.

For RAG ingestion, keep one document per source with the URL and retrieval
date at the top, and do not merge several sources into one document.

## Limits

- The service exposes three operations: health, page crawl, and same-site
  traversal. It is not a general browser and not a full API surface.
- Site traversal stays on the same site and is bounded: one level deep by
  default, five at most, with a server-side page ceiling. Treat a truncated run
  as a result to report, not as a failure to retry blindly.
- It does not search the internet. A request to "find pages about X" is a site
  traversal with a query, or a search step you perform before crawling.
- Interactive work belongs to `agent-browser`; a crawl retry will not fix a
  page that requires a session.
- Service credentials are injected centrally. If a crawl is refused, report the
  refusal — do not look for a token to supply.
