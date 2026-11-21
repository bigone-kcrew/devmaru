#!/usr/bin/env bash
# 관리형 MCP 서버(kordoc·markitdown·crawl4ai)의 npm 의존성을 설치한다. 호스트에 Node 가 없으므로 Golden 이미지(같은 Node 버전)로 실행한다.
set -uo pipefail
O=/opt/$PFX; M=$O/managed-mcp; IMG=$PFX-dev:$(cat "$O/images/dev/GOLDEN_VERSION" 2>/dev/null || cat "$KIT/VERSION")
echo "== 관리형 MCP 의존성"
docker image inspect "$IMG" >/dev/null 2>&1 || { IMG=node:24-slim; echo "안내: Golden 이미지가 없어 $IMG 로 대신 설치"; }
bad=0
for d in "$M"/*/; do
  [ -f "$d/package.json" ] || continue; n=$(basename "$d")
  if [ -d "$d/node_modules/@modelcontextprotocol" ]; then echo "안내: $n 이미 설치됨"; continue; fi
  echo "  > $n npm ci"
  if docker run --rm --entrypoint bash -v "$d:/app" -w /app "$IMG" -lc 'npm ci --omit=dev --no-audit --no-fund >/tmp/npm.log 2>&1 || { tail -n 8 /tmp/npm.log; exit 1; }'; then echo "성공: $n 의존성"; else echo "실패: $n 의존성 설치 실패"; bad=1; fi
done
chmod -R a+rX "$M"
[ "$bad" = 0 ] && echo "결과: 통과" || { echo "결과: 실패"; exit 1; }
