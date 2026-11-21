FROM python:3.12-slim

RUN pip install --no-cache-dir \
    "fastapi>=0.116,<1" \
    "uvicorn[standard]>=0.35,<1" \
    "httpx>=0.28,<1" \
 && useradd --uid 10001 --create-home gateway

COPY src/server.py /app/server.py

USER 10001:10001
WORKDIR /app

EXPOSE 3431

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "3431"]
