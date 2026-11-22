#!/usr/bin/env bash
# mig-status.sh — 그룹별 마지막 전송 상태(완료·시험실행·진행중·실패·중단?)와 마지막 로그 줄. 읽기 전용. 로그 폴더를 읽을 수 있어야 한다(보통 sudo).
#   sudo bash mig-status.sh
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
run(){
load_conf
printf '%-16s %-8s %-12s %s\n' 그룹 상태 시작 요약
while read -r g; do
  f=$(ls -t "$LOG_DIR/$g"-[0-9]*.log 2>/dev/null | head -1)
  [ -n "$f" ] || { printf '%-16s %-8s %-12s %s\n' "$g" "-" "-" "기록 없음"; continue; }
  st=$(basename "$f" | sed -E 's/.*-([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})[0-9]{2}\.log/\2-\3 \4:\5/')
  body=$(tr '\r' '\n' < "$f"); n=$(printf '%s\n' "$body" | grep -a '^Number of regular files transferred' | sed -E 's/.*: //; s/,//g' | awk '{s+=$1} END{print s+0}')
  if pgrep -f "mig-rsync.sh $g( |\$)" >/dev/null 2>&1; then s=진행중; d=$(printf '%s\n' "$body" | grep -av '^ *$' | tail -1 | sed 's/^ *//' | cut -c1-70)
  elif printf '%s\n' "$body" | grep -aq '^rsync error'; then s=실패; d=$(printf '%s\n' "$body" | grep -a '^rsync error' | tail -1 | cut -c1-70)
  elif printf '%s\n' "$body" | grep -aq '^total size is'; then
    if printf '%s\n' "$body" | grep -aq 'DRY RUN'; then s=시험실행; d="보낼 파일 ${n}개(쓰지 않음)"; else s=완료; d="보낸 파일 ${n}개"; fi
  else s="중단?"; d="요약 없음 — 같은 명령을 다시 실행하면 이어서 보낸다(--partial)"; fi
  printf '%-16s %-8s %-12s %s\n' "$g" "$s" "$st" "$d"
done < <(group_names)
}
run "$@"; exit $?
