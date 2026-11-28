#!/usr/bin/env bash
# 사전 점검: OS · 자원 · 인터넷 · 포트 · DNS. 치명적이면 실패(중단), 권고는 경고.
set -uo pipefail
bad=0
fail(){ echo "실패: $*"; bad=1; }; pass(){ echo "성공: $*"; }; warn(){ echo "경고: $*"; }
echo "== 사전 점검"
[ "$(id -u)" = 0 ] && pass "root" || fail "root 로 실행해야 합니다"
. /etc/os-release
if [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 26.04 ]; then pass "Ubuntu 26.04"; else warn "Ubuntu 26.04 에서만 검증됨(현재 ${PRETTY_NAME:-?})"; fi
if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then warn "WSL 로 보입니다 — WSL2 는 실험적 지원입니다(windows/install-windows.ps1 로 Windows 쪽을 준비했는지, docs/INSTALL.md 확인). 운영 서버는 Ubuntu 서버나 VM 을 권장합니다"; fi
[ "$(uname -m)" = x86_64 ] && pass "x86_64" || fail "x86_64 만 지원합니다"
mem=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo); cpus=$(nproc)
[ "$mem" -ge 7 ] && pass "메모리 ${mem}GB" || fail "메모리 ${mem}GB — 최소 8GB 필요(Golden 빌드·서비스)"
[ "$mem" -ge 16 ] || warn "메모리 ${mem}GB — 회원 여러 명이면 16GB 이상 권장"
[ "$cpus" -ge 4 ] && pass "CPU ${cpus}코어" || warn "CPU ${cpus}코어 — 4코어 이상 권장"
mkdir -p /srv; free=$(df --output=avail -BG /srv | tail -1 | tr -dc 0-9)
[ "$free" -ge 60 ] && pass "/srv 여유 ${free}GB" || { [ "$free" -ge 30 ] && warn "/srv 여유 ${free}GB — Golden 이미지 빌드에 60GB 이상 권장" || fail "/srv 여유 ${free}GB — 최소 30GB 필요"; }
rootfree=$(df --output=avail -BG /var/lib | tail -1 | tr -dc 0-9)
[ "$rootfree" -ge 40 ] && pass "/var/lib(도커) 여유 ${rootfree}GB" || warn "/var/lib 여유 ${rootfree}GB — 도커 이미지에 40GB 이상 권장"
getent passwd "$ADMIN_USER" >/dev/null && pass "관리자 계정 $ADMIN_USER" || fail "관리자 계정 $ADMIN_USER 없음"
for u in https://github.com https://registry-1.docker.io/v2/ https://deb.nodesource.com https://dl.cloudsmith.io; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" 2>/dev/null || true)
  [ -n "$code" ] && [ "$code" != 000 ] && pass "인터넷 $u ($code)" || fail "인터넷 연결 실패: $u"
done
for p in 80 443; do
  if ss -ltn "sport = :$p" 2>/dev/null | grep -q LISTEN; then
    ss -ltnp "sport = :$p" 2>/dev/null | grep -q caddy && pass "포트 $p (caddy 사용 중 — 재설치)" || fail "포트 $p 를 다른 프로그램이 쓰고 있습니다"
  else pass "포트 $p 비어 있음"; fi
done
# 도커 네트워크 서브넷이 서버의 기존 경로와 겹치는지
while IFS='|' read -r n s; do
  case "$n" in ''|\#*) continue;; esac
  base=${s%%.*.*}; if ip -4 route | awk '{print $1}' | grep -E "^${s%/*}" | grep -qv "br-\|docker"; then :; fi
  ip -4 route | grep -qE "^${s%%/*} " && warn "서브넷 $s 가 이미 쓰이는 것 같습니다(networks.list 조정)"
done < <(sed "s/@@PFX@@/$PFX/g" "$KIT/config/networks.list")
if [ "${SKIP_DNS:-0}" = 1 ]; then warn "DNS 점검 건너뜀(--skip-dns)"
else
  my=$(curl -s -m 8 https://api.ipify.org || true)
  [ -n "$my" ] && echo "  > 이 서버의 공인 IP: $my"
  hosts="$DOMAIN $PORTAL_HOST"; case " ${DEVMARU_MODULES:-} " in *" admin "*) hosts="$hosts ${ADMIN_HOST:-admin.$DOMAIN}";; esac
  for h in $hosts; do
    ip=$(getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1}')
    if [ -z "$ip" ]; then warn "DNS: $h 이름이 아직 풀리지 않습니다 — A 레코드를 만드세요(인증서 발급에 필요)"
    elif [ -n "$my" ] && [ "$ip" != "$my" ]; then warn "DNS: $h → $ip (이 서버 공인 IP $my 와 다름)"
    else pass "DNS $h → $ip"; fi
  done
fi
[ "$bad" = 0 ] && echo "결과: 통과" || { echo "결과: 실패"; exit 1; }
