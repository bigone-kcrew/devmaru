FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN pip install --no-cache-dir \
    'markitdown[docx,pptx,xls,xlsx,outlook]==0.1.9' \
    'fastapi>=0.116,<1' \
    'uvicorn[standard]>=0.35,<1' \
    'python-multipart>=0.0.20,<1'

COPY src/server.py /app/server.py

RUN useradd --system --uid 10001 --create-home markitdown

USER 10001:10001

EXPOSE 3410

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "3410"]
