#!/usr/bin/env bash
# 주기 작업(systemd 타이머) 켜기: 회원 사이트 공개 동기화 · 앱 동기화 · DB 정책. 백업 타이머는 사용자가 정한다.
set -uo pipefail
echo "== 주기 작업 켜기"
bad=0
for t in site-sync app-sync db-policy; do
  if systemctl enable --now "$PFX-$t.timer" >/dev/null 2>&1; then echo "성공: $PFX-$t.timer"; else echo "실패: $PFX-$t.timer 를 켜지 못함"; bad=1; fi
done
[ "$bad" = 0 ] && echo "결과: 통과" || { echo "결과: 실패"; exit 1; }
