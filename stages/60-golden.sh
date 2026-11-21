#!/usr/bin/env bash
# Golden 이미지(회원 개발환경): 업스트림 재료를 받아 설치 서버에서 직접 빌드한다(수십 분, 인터넷 필요).
set -uo pipefail
case " $DEVMARU_MODULES " in *" golden "*) ;; *) echo "안내: golden 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
O=/opt/$PFX; D=$O/images/dev; VER=$(cat "$D/GOLDEN_VERSION" 2>/dev/null || cat "$KIT/VERSION"); IMG=$PFX-dev:$VER   # Golden 버전은 킷 버전과 따로 센다(golden/GOLDEN_VERSION)
# 포인터(GOLDEN_IMAGE)가 이 킷의 이전 이미지를 가리키면 새 이미지로 옮긴다. 운영자가 promote 로 더 높은 버전을 올렸으면 건드리지 않는다.
move_pointer(){ local P=$O/config/dev-container.env cur; cur=$(sed -n "s/^GOLDEN_IMAGE=$PFX-dev://p" "$P" 2>/dev/null)
  [ -n "$cur" ] && [ "$cur" != "$VER" ] && [ "$(printf '%s\n%s\n' "$cur" "$VER" | sort -V | tail -1)" = "$VER" ] || return 0
  sed -i "s|^GOLDEN_IMAGE=.*|GOLDEN_IMAGE=$IMG|" "$P" && echo "안내: Golden 포인터 $cur → $VER (되돌리려면 $P 의 GOLDEN_IMAGE 를 이전 값으로)"; }
echo "== Golden 이미지 빌드"
if docker image inspect "$IMG" >/dev/null 2>&1 && [ "${GOLDEN_REBUILD:-0}" != 1 ]; then
  echo "안내: 이미 있음 — $IMG (다시 빌드하려면 GOLDEN_REBUILD=1)"; move_pointer; echo "결과: 통과"; exit 0; fi
echo "  > 1/2 업스트림 재료 내려받기(스킬·플러그인·agent-browser 등)"
( cd "$D" && bash ./fetch-upstream.sh ) || { echo "실패: 업스트림 재료 내려받기 실패"; echo "결과: 실패"; exit 1; }
echo "  > 2/2 이미지 빌드 시작: $IMG (음성 모델 ${GOLDEN_VOICE:-0} · 사무 문서 도구 ${GOLDEN_OFFICE:-1}) — 처음에는 수십 분 걸립니다"
LOG=/var/log/$PFX-golden-build.log; : > "$LOG"
( while sleep 60; do echo "  > 빌드 진행 중… 경과 ${SECONDS}초 — $(tail -n1 "$LOG" | cut -c1-90)"; done ) & TICK=$!
trap 'kill $TICK 2>/dev/null' EXIT
S=$SECONDS
if DOCKER_BUILDKIT=1 docker build --progress=plain --build-arg "INSTALL_VOICE_MODELS=${GOLDEN_VOICE:-0}" --build-arg "INSTALL_OFFICE=${GOLDEN_OFFICE:-1}" -t "$IMG" "$D" >> "$LOG" 2>&1; then
  echo "성공: Golden 이미지 $IMG ($((SECONDS-S))초, 로그 $LOG)"; move_pointer
  echo "결과: 통과"
else
  echo "실패: Golden 빌드 실패 — 마지막 줄:"; tail -n 15 "$LOG" | cut -c1-160 | sed 's/^/  > /'
  echo "결과: 실패"; exit 1
fi
