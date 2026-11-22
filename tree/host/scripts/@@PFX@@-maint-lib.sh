#!/usr/bin/env bash
# @@PFX@@-maint-lib.sh — 정비 락(서버 전체에서 한 번에 하나). 다른 스크립트가 source 해서 쓴다.
#
#   maint_lock <작업이름>   잡으면 0. 다른 정비 작업이 잡고 있으면 안내를 stderr 로 내고 종료 코드 75(EX_TEMPFAIL)로 exit.
#
# - 락 파일: /run/@@PFX@@-maintenance.lock (tmpfs — 재부팅하면 사라진다). 프로세스가 끝나면 락도 자동으로 풀린다.
# - **상태를 바꾸는 경로에만** 건다(update 적용·service-update --apply·restore apply·member-update-all 적용·golden rc·backup-run).
#   읽기 전용 명령(--check · --plan · status · --json)은 락을 잡지도, 락 때문에 막히지도 않는다.
# - 재진입: 잡은 쪽이 환경변수 @@PFX_UP@@_MAINT_HELD 를 내보내므로, 그 안에서 실행되는 하위 명령이 다시 부르면 다시 잡지 않는다.
# - 잡고 있는 작업은 `sudo @@PFX@@-maintenance status [--json]` 로 본다(읽기 전용).
MAINT_LOCK_FILE=${@@PFX_UP@@_MAINT_LOCK:-/run/@@PFX@@-maintenance.lock}

maint_lock() {
  local name=${1:-unknown} holder
  [[ -n ${@@PFX_UP@@_MAINT_HELD:-} ]] && return 0
  if ! exec {MAINT_FD}<>"$MAINT_LOCK_FILE"; then
    echo "경고: 정비 락 파일을 열 수 없어 락 없이 진행합니다: $MAINT_LOCK_FILE" >&2
    return 0
  fi
  if ! flock -n "$MAINT_FD"; then
    holder=$(head -c 200 "$MAINT_LOCK_FILE" 2>/dev/null | tr -d '\000' | head -n1)
    echo "실패: 다른 정비 작업이 실행 중이라 '$name' 을 시작하지 않습니다${holder:+ — 실행 중: $holder}" >&2
    echo "      끝나기를 기다린 뒤 다시 실행하세요(상태: sudo @@PFX@@-maintenance status)." >&2
    exit 75
  fi
  printf '%s pid=%s since=%s\n' "$name" "$$" "$(date -Is)" > "$MAINT_LOCK_FILE"
  export @@PFX_UP@@_MAINT_HELD="$name"
}
