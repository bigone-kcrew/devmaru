#!/usr/bin/env bash
# Caddy: 템플릿 + 선택 모듈을 합쳐 /etc/caddy/Caddyfile 을 만들고 검증·적용한다.
set -euo pipefail
O=/opt/$PFX; C=/etc/caddy
has(){ case " $DEVMARU_MODULES " in *" $1 "*) return 0;; esac; return 1; }
echo "== 웹 서버(Caddy)"
install -d -m 0755 "$C/members.d" "$C/sites.d" "$C/apps.d" /var/log/caddy
[ -e "$C/geo-allow.caddy" ] || cat > "$C/geo-allow.caddy" <<'X'
# 접속 허용 대역 스니펫 — 멤버 사이트·Paseo 블록이 import 하고 @allowed 에 맞는 요청만 통과시킨다.
# 기본은 모두 허용. 국가·대역을 제한하려면 remote_ip 뒤의 목록을 허용할 대역으로 바꾼다.
(geo_allow) {
	@allowed remote_ip 0.0.0.0/0 ::/0
}
X
[ -e "$C/$PFX-shared.caddy" ] || : > "$C/$PFX-shared.caddy"
chown caddy:caddy /var/log/caddy 2>/dev/null || true
T=$(mktemp)
LC=""; [ "${TLS_MODE:-acme}" = internal ] && LC=$'\tlocal_certs\n'
{ printf '{\n\temail %s\n%s}\n\n' "$ADMIN_EMAIL" "$LC"; cat "$O/caddy/Caddyfile.tmpl"
  has files && cat "$O/caddy/modules/files.caddy"; has cockpit && cat "$O/caddy/modules/cockpit.caddy"
  has n8n && cat "$O/caddy/modules/n8n.caddy"; has uptime-kuma && cat "$O/caddy/modules/uptime-kuma.caddy"; has smb && cat "$O/caddy/modules/smb-acme.caddy"; true; } > "$T"
[ -f "$C/Caddyfile" ] && cp -a "$C/Caddyfile" "$C/Caddyfile.bak.$(date +%Y%m%d-%H%M%S)"
install -m 0644 "$T" "$C/Caddyfile"; rm -f "$T"
if caddy validate --config "$C/Caddyfile" >/dev/null 2>&1; then echo "성공: caddy validate"
else caddy validate --config "$C/Caddyfile" 2>&1 | tail -5; echo "실패: Caddyfile 검증 실패"; exit 1; fi
# root 로 validate 하면 로그 파일이 root 소유로 생긴다 — caddy 가 못 연다
chown -R caddy:caddy /var/log/caddy
systemctl enable caddy >/dev/null 2>&1; systemctl reload-or-restart caddy
sleep 2; systemctl is-active --quiet caddy && echo "성공: caddy 동작 중" || { echo "실패: caddy 가 시작되지 않음(journalctl -u caddy)"; exit 1; }
echo "결과: 통과"
