import os
import tempfile
from importlib.metadata import version
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import PlainTextResponse
from markitdown import MarkItDown

APP_VERSION = "0.1.0"
MARKITDOWN_VERSION = version("markitdown")

MAX_FILE_MB = int(os.getenv("MAX_FILE_MB", "100"))
MAX_FILE_BYTES = MAX_FILE_MB * 1024 * 1024

app = FastAPI(
    title="@@BRAND@@ MarkItDown API",
    version=APP_VERSION,
)

converter = MarkItDown(enable_plugins=False)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "@@PFX@@-markitdown",
        "api": APP_VERSION,
        "markitdown": MARKITDOWN_VERSION,
    }


@app.get("/version")
def get_version():
    return {
        "service": "@@PFX@@-markitdown",
        "api": APP_VERSION,
        "markitdown": MARKITDOWN_VERSION,
    }


@app.post("/v1/convert", response_class=PlainTextResponse)
async def convert_file(file: UploadFile = File(...)):
    filename = Path(file.filename or "upload.bin").name

    suffix = Path(filename).suffix.lower()

    kordoc_first = {".pdf", ".hwp", ".hwpx"}
    if suffix in kordoc_first:
        raise HTTPException(
            status_code=415,
            detail=f"{suffix} is handled by Kordoc in @@BRAND@@",
        )
    tmp_path = None

    try:
        total = 0

        with tempfile.NamedTemporaryFile(
            prefix="markitdown-",
            suffix=suffix,
            delete=False,
        ) as tmp:
            tmp_path = tmp.name

            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break

                total += len(chunk)

                if total > MAX_FILE_BYTES:
                    raise HTTPException(
                        status_code=413,
                        detail=f"File exceeds {MAX_FILE_MB} MB limit",
                    )

                tmp.write(chunk)

        try:
            result = converter.convert_local(tmp_path)
        except Exception as exc:
            raise HTTPException(
                status_code=422,
                detail=f"Conversion failed: {type(exc).__name__}",
            ) from exc

        markdown = getattr(result, "markdown", None)
        if markdown is None:
            markdown = getattr(result, "text_content", None)

        if not isinstance(markdown, str):
            raise HTTPException(
                status_code=500,
                detail="Converter returned no Markdown text",
            )

        return markdown

    finally:
        await file.close()

        if tmp_path:
            try:
                os.unlink(tmp_path)
            except FileNotFoundError:
                pass
