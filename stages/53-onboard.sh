#!/usr/bin/env bash
# 회원 안내 전달 채널 준비: ONBOARD_CHANNELS 에 link 가 있으면 1회 열람 링크 서비스(전용 계정·systemd·Caddy /start/*)를 켜고,
#   없으면 꺼 둔다. webhook·print 는 설정·비밀 파일만 점검한다. 채널 문제는 «경고» 로만 알린다(회원 등록은 어떤 채널이 실패해도 끝난다).
set -uo pipefail
CH="${ONBOARD_CHANNELS:-}"; has_ch(){ case " $CH " in *" $1 "*) return 0;; esac; return 1; }
C=/etc/caddy; SNIP=$C/$PFX-link.caddy; LU=$PFX-link; PORT="${ONBOARD_LINK_PORT:-8431}"
echo "== 회원 안내 전달 채널"
reload_caddy(){ command -v caddy >/dev/null 2>&1 || return 0
  if caddy validate --config "$C/Caddyfile" >/dev/null 2>&1; then chown -R caddy:caddy /var/log/caddy 2>/dev/null; systemctl reload caddy >/dev/null 2>&1; return 0; fi; return 1; }
if ! has_ch link; then
  # 꺼져 있다: 예전에 켰다면 서비스를 끄고 Caddy 연결을 비운다
  if [ -s "$SNIP" ] || systemctl is-enabled --quiet "$PFX-link.service" 2>/dev/null; then
    systemctl disable --now "$PFX-link.service" >/dev/null 2>&1; : > "$SNIP"; find "/run/$PFX-link" -mindepth 1 -delete 2>/dev/null   # 남은 1회 열람 링크 기록(비밀번호 포함)도 지운다
    reload_caddy && echo "성공: link 채널 꺼짐 — 서비스 중지·Caddy /start/* 연결 제거" || echo "경고: Caddy 설정 검증 실패 — $SNIP 를 확인하세요"
  fi
else
  [ -x /usr/local/sbin/$PFX-link-server ] || { echo "경고: $PFX-link-server 가 없습니다(20 단계를 먼저 실행하세요)"; echo "결과: 통과"; exit 0; }
  case "$PORT" in ''|*[!0-9]*) echo "경고: ONBOARD_LINK_PORT 는 숫자여야 합니다($PORT) — link 채널을 켜지 못했습니다"; echo "결과: 통과"; exit 0;; esac
  { [ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ]; } || { echo "경고: ONBOARD_LINK_PORT 는 1024~65535 입니다($PORT)"; echo "결과: 통과"; exit 0; }
  case "${ONBOARD_LINK_TTL_HOURS:-24}" in ''|*[!0-9]*) echo "경고: ONBOARD_LINK_TTL_HOURS 는 1~168 정수입니다";; esac
  id "$LU" >/dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$LU"
  if ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT " && ! systemctl is-active --quiet "$PFX-link.service"; then
    echo "경고: 127.0.0.1:$PORT 를 다른 프로그램이 쓰고 있습니다 — site.env 의 ONBOARD_LINK_PORT 를 바꾸고 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 53' 로 다시 실행하세요"; echo "결과: 통과"; exit 0
  fi
  systemctl daemon-reload; systemctl enable "$PFX-link.service" >/dev/null 2>&1; systemctl restart "$PFX-link.service"
  for i in 1 2 3 4 5 6 7 8; do /usr/local/sbin/$PFX-member-link --check >/dev/null 2>&1 && break; sleep 1; done
  if /usr/local/sbin/$PFX-member-link --check >/dev/null 2>&1; then echo "성공: 링크 서비스 동작·보안 헤더 확인(127.0.0.1:$PORT)"; else echo "경고: 링크 서비스 점검 실패 — journalctl -u $PFX-link · sudo $PFX-member-link --check"; fi
  prev=$(cat "$SNIP" 2>/dev/null || true)
  cat > "$SNIP" <<SN
	# 회원 안내 1회 열람 링크 — $PFX-link 서비스(127.0.0.1:$PORT)로 전달. /start/* 는 접근 로그를 남기지 않는다(log_skip) · 토큰이 든 경로는 로그 필터로도 지워진다
	handle /start/* {
		log_skip
		request_body {
			max_size 2KB
		}
		reverse_proxy 127.0.0.1:$PORT {
			header_up -X-Forwarded-For
			header_up X-Onboard-Client-IP {remote_host}
		}
	}
SN
  if ! grep -q "$PFX-link.caddy" "$C/Caddyfile" 2>/dev/null; then
    echo "경고: Caddyfile 에 /start/ 연결(import)이 없습니다 — 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 50,53' 로 Caddy 설정을 다시 만드세요"
  elif reload_caddy; then echo "성공: Caddy /start/* 연결(https://$DOMAIN/start/<토큰>)"
  else printf '%s' "$prev" > "$SNIP"; echo "경고: Caddy 설정 검증 실패 — /start/* 연결을 되돌렸습니다(caddy validate --config $C/Caddyfile)"; fi
fi
if has_ch webhook || has_ch print || has_ch link; then
  if out=$(/usr/local/sbin/$PFX-onboard-deliver --check 2>&1); then echo "성공: 전달 채널 설정 점검"; else echo "$out" | grep -v '^성공' | sed 's/^/  > /'; echo "경고: 일부 전달 채널 설정에 문제가 있습니다(회원 등록은 문제 없이 되고 화면 표시로 대신됩니다) — docs/ONBOARDING.md"; fi
fi
echo "안내: 전달 채널 = ${CH:-screen} · 회원 등록 때 순서대로 시도하고 모두 실패하면 화면에 표시합니다 (docs/ONBOARDING.md)"
echo "결과: 통과"
