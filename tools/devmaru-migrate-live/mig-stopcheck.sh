#!/usr/bin/env bash
# mig-stopcheck.sh — «다 멈췄다» 를 확인한다(읽기 전용). 구 서버에서 root: sudo bash mig-stopcheck.sh
# 최종 동기화(mig-final.sh apply)가 먼저 이것을 부른다. 하나라도 실패면 종료 코드 1.
#   1. 루트 도커 컨테이너가 0개
#   2. 회원별 루트리스 도커(/run/user/*/docker.sock)의 컨테이너가 0개 — 루트 «docker ps» 에는 안 보인다
#   3. 호스트 프로세스: containerd-shim(어느 도커든 떠 있는 컨테이너) · postgres · EXTRA_PROC_PATTERNS(재시작 가드 스크립트 등)
#   4. stop 그룹 원본에 postmaster.pid 가 없다(DB 정상 종료). 0 이 아닌 SQLite *-wal 파일은 경고(정상 종료면 보통 없다)
#   5. <접두어>-* 타이머가 돌고 있으면 경고(정지 뒤 다시 무언가를 켤 수 있다)
# 프로세스는 pid·사용자·이름만 보여 준다(명령줄 인자에 비밀이 있을 수 있어 출력하지 않는다).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
run(){
load_conf; need_root; bad=0
ok(){ say "  PASS $*"; }; ng(){ say "  FAIL $*"; bad=1; }; wn(){ say "  WARN $*"; }
say "== 정지 확인"
if command -v docker >/dev/null; then
  n=$(docker ps -q 2>/dev/null | wc -l); [ "$n" = 0 ] && ok "루트 도커 실행 중 컨테이너 0" || ng "루트 도커 실행 중 컨테이너 $n 개: $(docker ps --format '{{.Names}}' | paste -sd' ')"
fi
for sock in "${MIG_ROOT:-}"/run/user/*/docker.sock; do
  [ -S "$sock" ] || { [ "${MIG_TEST:-}" = 1 ] && [ -e "$sock" ]; } || continue
  u=$(echo "$sock" | sed -E 's#.*/run/user/([0-9]+)/docker.sock#\1#')
  n=$(DOCKER_HOST="unix://$sock" docker ps -q 2>/dev/null | wc -l)
  [ "$n" = 0 ] && ok "루트리스 도커(uid $u) 컨테이너 0" || ng "루트리스 도커(uid $u) 실행 중 컨테이너 $n 개 — 그 회원의 docker 로 멈춰야 한다"
done
pat='containerd-shim|bin/postgres( |$)|postgres: '; [ -z "$EXTRA_PROC_PATTERNS" ] || pat="$pat|$EXTRA_PROC_PATTERNS"
pids=$(pgrep -f -- "$pat" 2>/dev/null | grep -vx "$$" || true)
if [ -z "$pids" ]; then ok "호스트 프로세스(containerd-shim·postgres$([ -n "$EXTRA_PROC_PATTERNS" ] && echo "·$EXTRA_PROC_PATTERNS")) 없음"
else ng "아직 떠 있는 프로세스: $(ps -o pid=,user=,comm= -p "$(echo $pids | tr ' ' ,)" 2>/dev/null | awk '{printf "%s(%s,%s) ",$3,$1,$2}')"; fi
while read -r g; do load_group "$g"; [ "$G_TYPE" = stop ] || continue
  for s in "${G_SRCS[@]}"; do d="${MIG_ROOT:-}$s"; [ -d "$d" ] || continue
    p=$(find "$d" -maxdepth 3 -name postmaster.pid 2>/dev/null | head -1)
    [ -z "$p" ] && ok "$g: postmaster.pid 없음($s)" || ng "$g: postmaster.pid 가 남아 있다(${p#"${MIG_ROOT:-}"}) — DB 가 정상 종료되지 않았다"
    w=$(find "$d" -maxdepth 6 -name '*-wal' -size +0 2>/dev/null | head -3)
    [ -z "$w" ] || wn "$g: 비어 있지 않은 SQLite WAL — 쓰는 프로세스가 끝났는지 확인(.db·-wal·-shm 세 파일을 함께 옮긴다): $(echo "$w" | sed "s#^${MIG_ROOT:-}##" | paste -sd' ')"
  done
done < <(group_names)
if command -v systemctl >/dev/null; then
  t=$(systemctl list-units "$PFX-*.timer" --state=active --plain --no-legend 2>/dev/null | awk '{print $1}' | paste -sd' ')
  [ -z "$t" ] || wn "켜져 있는 타이머: $t — sudo systemctl stop $t"
fi
[ $bad = 0 ] && say "결과: 정지 확인 통과" || say "결과: 정지 확인 실패 — 위 FAIL 을 해결한 뒤 다시"
return $bad
}
run "$@"; exit $?
