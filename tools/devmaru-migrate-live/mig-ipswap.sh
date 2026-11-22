#!/usr/bin/env bash
# mig-ipswap.sh — netplan 고정 IP 를 안전하게 바꾼다. root 로 실행: sudo bash mig-ipswap.sh …
#   mig-ipswap.sh <지금IP> <바꿀IP>                          계획: diff·사전 점검만(아무것도 바꾸지 않음)
#   mig-ipswap.sh <지금IP> <바꿀IP> --apply                  콘솔(모니터·키보드)에서: netplan try — 제한 시간 안에 Enter 로 확정하지 않으면 자동 원복
#   mig-ipswap.sh <지금IP> <바꿀IP> --apply --remote         원격(SSH)에서: 적용 + «N초 뒤 자동 원복» systemd 타이머.
#                                                            바뀐 IP 로 다시 접속해 «sudo systemctl stop <접두어>-ipswap-revert.timer» 로 확정
#   옵션: --timeout <초>(기본 콘솔 120 · 원격 300) · --yes(확인 문구 생략)
# 안전 장치: 바꿀 IP 가 이미 응답하면(arping -D, 없으면 ping) 적용 거부 — 상대 서버가 먼저 비워야 한다.
#   지금IP 가 든 netplan 파일이 정확히 1개여야 한다 · netplan generate 문법 검사 실패 시 원복 · 백업 <파일>.bak.pre-ipswap-<시각>.
# 두 서버 맞교환 순서(같은 IP 가 동시에 두 대에 있으면 안 된다): 구 → 임시 IP, 신 → 구 IP 승계, 구 → 보관 IP. 단계마다 확정한 뒤 다음으로.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
run(){
load_conf; NP=${MIG_NETPLAN_DIR:-/etc/netplan}; UNIT="$PFX-ipswap-revert"
FROM=${1:-}; TO=${2:-}; shift 2 2>/dev/null || true; APPLY=0; REMOTE=0; YES=0; TIMEOUT=""
while [ $# -gt 0 ]; do case "$1" in --apply) APPLY=1;; --remote) REMOTE=1;; --yes) YES=1;; --timeout) TIMEOUT=${2:-}; shift;; *) fail "알 수 없는 옵션: $1";; esac; shift; done
re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'; [[ "$FROM" =~ $re && "$TO" =~ $re ]] || fail "사용법: $0 <지금IP> <바꿀IP> [--apply [--remote]] [--timeout 초] [--yes]"
[ "$FROM" != "$TO" ] || fail "두 주소가 같다"
TIMEOUT=${TIMEOUT:-$([ $REMOTE = 1 ] && echo 300 || echo 120)}; case "$TIMEOUT" in ''|*[!0-9]*) fail "--timeout 은 초 단위 숫자";; esac
need_root
mapfile -t F < <(grep -l -E "(^|[^0-9.])${FROM//./\\.}/[0-9]+" "$NP"/*.yaml 2>/dev/null)
[ ${#F[@]} = 1 ] || fail "$FROM 이 든 netplan 파일이 ${#F[@]}개다(정확히 1개여야 한다): ${F[*]:-없음}"
FILE=${F[0]}; IFACE=$(ip -o -4 addr show 2>/dev/null | awk -v ip="$FROM/" 'index($4,ip)==1{print $2; exit}')
say "== IP 교체 $FROM → $TO · 파일 $FILE · 인터페이스 ${IFACE:-?(이 서버에 $FROM 이 없다)}"
BUSY=0
if command -v arping >/dev/null && [ -n "$IFACE" ]; then arping -D -q -c 2 -I "$IFACE" "$TO" >/dev/null 2>&1 || BUSY=1
elif ping -c1 -W1 "$TO" >/dev/null 2>&1; then BUSY=1
else say "  참고: arping 이 없어 ping 으로만 확인했다(방화벽이 ping 을 막으면 못 잡는다 — iputils-arping 설치 권장)"; fi
if [ $BUSY = 1 ]; then
  [ $APPLY = 0 ] || fail "$TO 가 이미 응답한다(다른 장비·상대 서버가 사용 중) — 그쪽이 먼저 비운 뒤 적용한다. 중단"
  say "  점검: $TO 는 지금 사용 중 — 계획은 보여 주지만 적용은 상대가 비운 뒤에만 된다"
else say "  점검: $TO 는 응답이 없다(비어 있음)"; fi
NEW=$(sed -E "s#(^|[^0-9.])${FROM//./\\.}/#\\1${TO}/#g" "$FILE")
say "  변경(diff):"; diff "$FILE" <(printf '%s\n' "$NEW") | sed 's/^/    /'
if [ $APPLY = 0 ]; then say "(계획만 — 콘솔: $0 $FROM $TO --apply / 원격: --apply --remote)"; return 0; fi
[ $YES = 1 ] || confirm "$TO"
BAK="$FILE.bak.pre-ipswap-$(date +%Y%m%d-%H%M%S)"; cp -p "$FILE" "$BAK" || fail "백업 실패"
printf '%s\n' "$NEW" > "$FILE"; chmod --reference="$BAK" "$FILE" 2>/dev/null
netplan generate >/dev/null 2>&1 || { cp -p "$BAK" "$FILE"; fail "netplan 문법 검사 실패 — 원복함"; }
say "  백업: $BAK"
if [ $REMOTE = 1 ]; then
  systemctl stop "$UNIT.timer" >/dev/null 2>&1 || true   # 이전 단계의 타이머가 남아 있으면 정리
  systemd-run --on-active="${TIMEOUT}s" --unit="$UNIT" /bin/sh -c "cp -p '$BAK' '$FILE' && netplan apply" >/dev/null || { cp -p "$BAK" "$FILE"; fail "원복 타이머를 만들지 못했다 — 적용하지 않음(원복)"; }
  say "  원복 타이머 ${TIMEOUT}초. $TO 로 다시 접속해 확정: sudo systemctl stop $UNIT.timer"
  say "  확정 전에 외부에서 서비스·SSH 도달을 확인하세요. 시간이 지나면 $FROM 으로 자동으로 돌아간다."
  netplan apply; say "  적용함 — 이 세션은 끊길 수 있다."
else
  say "  netplan try — ${TIMEOUT}초 안에 Enter 로 확정하지 않으면 자동 원복"
  netplan try --timeout "$TIMEOUT" || { cp -p "$BAK" "$FILE"; fail "확정되지 않았다 — 파일 원복함"; }
  command -v arping >/dev/null && [ -n "$IFACE" ] && arping -U -c 3 -I "$IFACE" "$TO" >/dev/null 2>&1 && say "  arping -U 로 이웃 장비에 새 주소 알림"
  say "  확정됨."
fi
}
run "$@"; exit $?
