#!/usr/bin/env bash
# API 카탈로그(공개 API 목록): 업스트림 목록을 내려받아 회원 컨테이너가 읽기 전용으로 쓰는 catalog.json 을 만든다.
set -uo pipefail
O=/opt/$PFX; C=$O/api-catalog
echo "== API 카탈로그"
if [ -r "$C/data/catalog.json" ] && [ "${CATALOG_REFRESH:-0}" != 1 ]; then echo "안내: 이미 있음 — $C/data/catalog.json"; echo "결과: 통과"; exit 0; fi
install -d "$C/src" "$C/data" "$C/reports"
echo "  > 업스트림 목록 내려받는 중(git clone)"
if python3 "$C/bin/$PFX-api-catalog-sync" >/tmp/$PFX-catalog-sync.log 2>&1 || python3 "$C/bin/api-catalog-sync" >/tmp/$PFX-catalog-sync.log 2>&1; then
  [ -r "$C/data/catalog.json" ] && echo "성공: catalog.json ($(du -h "$C/data/catalog.json" | cut -f1))" || { echo "실패: 동기화는 끝났으나 catalog.json 이 없음"; echo "결과: 실패"; exit 1; }
  chmod -R a+rX "$C/data"
  echo "결과: 통과"
else
  tail -n 8 /tmp/$PFX-catalog-sync.log | sed 's/^/  > /'; echo "실패: API 카탈로그 동기화 실패(인터넷·github 접속 확인)"; echo "결과: 실패"; exit 1
fi
