#!/usr/bin/env bash
# mig-rsync.sh — 구 서버 → 신 서버 그룹 전송(push). 구 서버에서 root 로 실행: sudo bash mig-rsync.sh …
#   mig-rsync.sh list                                  그룹 목록(migrate-groups.conf)
#   mig-rsync.sh <그룹> [옵션]                          기본은 시험 실행(--dry-run, 아무것도 쓰지 않음)
# 옵션
#   --apply              실제 전송
#   --seed               정지 필요(stop) 그룹을 서비스 가동 중에 «밑그림» 으로 복사(최종본 아님)
#   --final --stopped    서비스 정지 뒤 최종 동기화: --delete-after(삭제 반영). stop 그룹 최종 «적용» 에는 --checksum 이 자동으로 붙는다
#                        conf 그룹은 --final 이어도 삭제하지 않는다(신 서버 설치기가 만든 파일 보존)
#   --checksum           크기·시각이 같아도 내용으로 비교(양쪽 전부 읽어 느리다)
#   --subdir <이름>      원본 아래 하위 폴더 하나만(회원별 나눠 보내기)
#   --bwlimit <KB/s>     속도 제한(기본: migrate.conf BWLIMIT, 0=제한 없음)
#   --usermap <X> / --groupmap <X>   X 는 «이름»(양쪽 번호를 찾아 구번호:신번호로 바꾼다) 또는 «구번호:신번호»
# 신 서버 수신은 RUSER 의 «sudo -n rsync»(REMOTE_RSYNC)로 받아 uid/gid·ACL·xattr 를 보존한다. 비밀 파일 내용은 출력하지 않는다(파일 목록도 남기지 않음 — 통계만).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"

# 이름 → 「구번호:신번호」(같으면 빈 값). kind: passwd|group
resolve_map(){
  local kind=$1 tok=$2 l r
  case "$tok" in *:*) echo "$tok"; return 0;; esac
  l=$(getent "$kind" "$tok" | cut -d: -f3); r=$(remote "getent $kind $tok" 2>/dev/null | cut -d: -f3)
  [ -n "$l" ] && [ -n "$r" ] || fail "$kind «$tok» 가 $([ -z "$l" ] && echo 구 || echo 신) 서버에 없다"
  [ "$l" = "$r" ] || echo "$l:$r"
}

run(){
load_conf
[ "$#" -ge 1 ] || fail "사용법: $0 list | <그룹> [--apply] [--seed | --final --stopped] [--checksum] [--subdir 이름] [--bwlimit N] [--usermap X] [--groupmap X]"
if [ "$1" = list ]; then
  while read -r g; do load_group "$g"; printf '%-16s %-5s %s\n' "$g" "$G_TYPE" "${G_SRCS[*]}"; [ -z "$G_NOTE" ] || printf '%22s%s\n' "" "$G_NOTE"; done < <(group_names)
  exit 0
fi
G=$1; shift; load_group "$G" || fail "알 수 없는 그룹: $G ($0 list)"
APPLY=0; SEED=0; FINAL=0; STOPPED=0; CK=0; SUB=""; BW=$BWLIMIT; UM=("${G_UMAP[@]}"); GM=("${G_GMAP[@]}")
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=1;; --seed) SEED=1;; --final) FINAL=1;; --stopped) STOPPED=1;; --checksum) CK=1;;
  --subdir) SUB=${2:-}; shift;; --bwlimit) BW=${2:-}; shift;;
  --usermap) UM+=("${2:-}"); shift;; --groupmap) GM+=("${2:-}"); shift;;
  *) fail "알 수 없는 옵션: $1";; esac; shift; done
[ -z "$SUB" ] || [[ "$SUB" =~ ^[A-Za-z0-9._-]+$ && "$SUB" != . && "$SUB" != .. ]] || fail "--subdir 이름은 영문·숫자·._- 만"
case "$BW" in ''|*[!0-9]*) fail "--bwlimit 는 숫자(KB/s)";; esac
[ "$FINAL" = "$STOPPED" ] || fail "--final 과 --stopped(서비스 정지 선언)는 함께만 쓴다"
[ "$SEED" = 0 ] || [ "$G_TYPE" = stop ] || fail "--seed 는 stop 그룹에만 쓴다"
[ "$SEED" = 0 ] || [ "$FINAL" = 0 ] || fail "--seed 와 --final 은 함께 쓸 수 없다"
if [ "$APPLY" = 1 ] && [ "$G_TYPE" = stop ] && [ "$SEED" = 0 ] && [ "$FINAL" = 0 ]; then
  fail "$G 는 정지가 필요한 그룹이다 — 가동 중 밑그림이면 --seed, 최종이면 서비스를 멈춘 뒤 --final --stopped"; fi
[ "$APPLY" = 0 ] || need_root
guard_direction

MAPS=(); for t in "${UM[@]}"; do m=$(resolve_map passwd "$t") || exit 1; [ -z "$m" ] || MAPS+=(--usermap="$m"); done
for t in "${GM[@]}"; do m=$(resolve_map group "$t") || exit 1; [ -z "$m" ] || MAPS+=(--groupmap="$m"); done
mkdir -p "$LOG_DIR" 2>/dev/null && chmod 750 "$LOG_DIR" 2>/dev/null; LOG="$LOG_DIR/$G-$(date +%Y%m%d-%H%M%S).log"
MODE=$([ "$APPLY" = 1 ] && echo 전송 || echo "시험 실행(dry-run)")
say "== $G [$G_TYPE] $MODE$([ $SEED = 1 ] && echo ' · 밑그림(seed)')$([ $FINAL = 1 ] && echo ' · 최종')$([ $FINAL = 1 ] && [ "$G_TYPE" != conf ] && echo '(--delete-after)') · bwlimit=${BW}KB/s"
[ -z "$G_NOTE" ] || say "   $G_NOTE"; [ ${#MAPS[@]} = 0 ] || say "   번호 보정: ${MAPS[*]}"; say "   로그: $LOG"
rc_all=0
for s in "${G_SRCS[@]}"; do
  t="$s${SUB:+/$SUB}"; src="${MIG_ROOT:-}$t"; [ -d "$src" ] || { say "  건너뜀(없음): $t"; continue; }
  A=(-aHAXx --numeric-ids --partial --mkpath --info=stats2 --human-readable --bwlimit="$BW")
  [ -t 1 ] && A+=(--info=progress2)
  for i in "${G_INC[@]}"; do A+=(--include="$i"); done
  for e in "${G_EXC[@]}"; do A+=(--exclude="$e"); done
  [ ${#G_INC[@]} = 0 ] || A+=(--exclude="*")              # include 가 있으면 지정한 이름만
  A+=("${MAPS[@]}")
  { [ "$CK" = 1 ] || { [ "$FINAL" = 1 ] && [ "$G_TYPE" = stop ] && [ "$APPLY" = 1 ]; }; } && A+=(--checksum)   # stop 그룹 최종 적용은 체크섬 비교
  [ "$FINAL" = 1 ] && [ "$G_TYPE" != conf ] && A+=(--delete-after)
  [ "$APPLY" = 1 ] || A+=(--dry-run)
  say "-- $t"
  rsync "${A[@]}" -e "$RSH" --rsync-path="$REMOTE_RSYNC" -- "$src/" "$RUSER@$NEW_HOST:$t/" 2>&1 | tee -a "$LOG"; rc=${PIPESTATUS[0]}
  [ "$rc" = 0 ] || { say "  rsync 종료 코드 $rc$([ "$rc" = 24 ] && echo ' (전송 중 사라진 파일 — 가동 중 복사에서는 정상)')"; [ "$rc_all" != 0 ] && [ "$rc_all" != 24 ] || rc_all=$rc; }
done
say "== 끝(rc $rc_all)"; [ "$APPLY" = 1 ] || say "(시험 실행이었다. 실제로 보내려면 --apply)"
return "$rc_all"
}
run "$@"; exit $?
