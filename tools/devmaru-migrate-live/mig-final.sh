#!/usr/bin/env bash
# mig-final.sh — 전환 때 모든 그룹을 «최종 동기화» 하고, 그룹마다 일치(전송 0·삭제 0)를 표로 확인한다. 구 서버에서 root, tmux 안에서:
#   sudo bash mig-final.sh apply [--yes] [--skip-stopcheck]   정지 확인(mig-stopcheck.sh) → 확인 문구 → migrate-groups.conf 순서대로 최종 동기화
#   sudo bash mig-final.sh verify [--fast]                     각 그룹을 시험 실행해 «전송 0·삭제 0» 이면 일치(stop 그룹은 체크섬 비교라 느리다; --fast 는 생략)
# 그룹별 옵션: live → --final --stopped(삭제 반영) · stop → --final --stopped(+체크섬) · conf → 덮어쓰기만(삭제 없음).
# 실패한 그룹이 있어도 끝까지 가고 마지막에 목록을 낸다. 같은 명령을 다시 실행하면 바뀐 것만 다시 보낸다(재실행 안전).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
run(){
load_conf; D=$MIG_DIR; R=${MIG_RSYNC:-$D/mig-rsync.sh}
MODE=${1:-}; shift || true; FAST=0; YES=0; SKIP=0
while [ $# -gt 0 ]; do case "$1" in --fast) FAST=1;; --yes) YES=1;; --skip-stopcheck) SKIP=1;; *) fail "알 수 없는 옵션: $1";; esac; shift; done
case "$MODE" in apply|verify) ;; *) fail "사용법: $0 apply [--yes] [--skip-stopcheck] | verify [--fast]";; esac
need_root
if [ "$MODE" = apply ]; then
  if [ $SKIP = 1 ]; then warn "정지 확인을 건너뛴다(--skip-stopcheck) — 가동 중인 쓰기가 최종본을 망가뜨릴 수 있다"
  else bash "${MIG_STOPCHECK:-$D/mig-stopcheck.sh}" || fail "정지 확인 실패 — 최종 동기화를 시작하지 않는다"; fi
  [ $YES = 1 ] || confirm "최종 동기화 $NEW_HOSTNAME"
fi
FAILS=(); T0=$(date +%s); printf '%-16s %-6s %-8s %-10s %-8s\n' 그룹 종류 결과 전송파일 삭제
while read -r g; do
  load_group "$g"; fl=()
  case "$G_TYPE" in live) fl=(--final --stopped);; stop) fl=(--final --stopped); [ "$MODE" = verify ] && [ $FAST = 0 ] && fl+=(--checksum);; esac
  [ "$MODE" = apply ] && fl+=(--apply)
  out=$(bash "$R" "$g" "${fl[@]}" 2>&1 </dev/null); rc=$?
  n=$(printf '%s\n' "$out" | grep -a '^Number of regular files transferred' | sed -E 's/.*: //; s/,//g' | awk '{s+=$1} END{print s+0}')
  d=$(printf '%s\n' "$out" | grep -a '^Number of deleted files' | sed -E 's/.*: //; s/,//g' | awk '{s+=$1} END{print s+0}')
  if [ "$MODE" = apply ]; then { [ $rc = 0 ] || [ $rc = 24 ]; } && st=완료 || st=실패
  else [ "$n" = 0 ] && [ "$d" = 0 ] && [ $rc = 0 ] && st=일치 || st=불일치; fi
  case "$st" in 실패|불일치) FAILS+=("$g($st rc=$rc)");; esac
  printf '%-16s %-6s %-8s %-10s %-8s\n' "$g" "$G_TYPE" "$st" "$n" "$d"
done < <(group_names)
say; say "소요 $(( ($(date +%s)-T0)/60 ))분 · 그룹별 로그: $LOG_DIR"
if [ ${#FAILS[@]} = 0 ]; then
  say "모두 $([ "$MODE" = apply ] && echo "완료 — 다음: sudo bash $0 verify" || echo 일치)"; return 0
fi
say "문제 그룹: ${FAILS[*]}"
say "다시: 원인을 고친 뒤 같은 명령을 다시 실행(바뀐 것만 보낸다) 또는 그룹 하나만 sudo bash $D/mig-rsync.sh <그룹> --final --stopped --apply"
return 1
}
run "$@"; exit $?
