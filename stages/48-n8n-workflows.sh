#!/usr/bin/env bash
# n8n 워크플로 템플릿(선택): N8N_WORKFLOWS=generic 이면 범용 템플릿을 «비활성»으로 가져온다. MAIL_MODE=n8n 이면 온보딩 메일 템플릿만이라도 가져온다.
set -uo pipefail
case " $DEVMARU_MODULES " in *" n8n "*) ;; *) echo "안내: n8n 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
WF="${N8N_WORKFLOWS:-none}"; MM="${MAIL_MODE:-none}"
if [ "$WF" != generic ] && [ "$MM" != n8n ]; then echo "안내: n8n 워크플로 템플릿 가져오기를 선택하지 않음(N8N_WORKFLOWS=none)"; echo "결과: 통과"; exit 0; fi
echo "== n8n 워크플로 템플릿"
for i in $(seq 1 30); do docker exec "${N8N_CONTAINER:-n8n}" n8n list:workflow >/dev/null 2>&1 && break; sleep 3; done
if [ "$WF" = generic ]; then ARGS=(--all); else ARGS=(member-onboarding); fi
if out=$("${N8N_WF_BIN:-/usr/local/sbin/$PFX-n8n-workflows}" install "${ARGS[@]}" 2>&1); then
  echo "$out" | sed 's/^성공:/성공:/; s/^  /  > /'
  echo "안내: 가져온 워크플로는 비활성입니다. n8n 화면(https://$N8N_HOST/)에서 자격증명을 고른 뒤 활성화하세요 — 자세한 방법: docs/N8N.md"
  echo "결과: 통과"
else
  echo "$out" | tail -n 5 | sed 's/^/  > /'; echo "경고: n8n 워크플로 가져오기 실패 — 나중에 sudo $PFX-n8n-workflows install --all 로 다시 시도하세요"; echo "결과: 통과"
fi
