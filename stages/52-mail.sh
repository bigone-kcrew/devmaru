#!/usr/bin/env bash
# 메일 자동 발송(선택): MAIL_MODE=smtp 이면 서버가 SMTP 로 직접 회원 등록 안내 메일을 보낸다(n8n 불필요).
#   MAIL_MODE=n8n 이면 n8n 워크플로 템플릿(48 단계)을 쓰므로 여기서는 안내만 한다. MAIL_MODE=none 이면 아무것도 하지 않는다.
set -uo pipefail
MM="${MAIL_MODE:-none}"
case "$MM" in
  smtp) ;;
  n8n) echo "== 메일 자동 발송 연동"; echo "안내: MAIL_MODE=n8n — 회원 등록 알림은 n8n 워크플로(member-onboarding)로 보냅니다."
       echo "안내: n8n 화면(https://$N8N_HOST/)에서 가져온 워크플로의 SMTP 자격증명을 고르고 활성화하세요(docs/N8N.md). 켜기 전에는 회원 등록 때 «화면 전달» 안내가 나옵니다."
       echo "결과: 통과"; exit 0 ;;
  *) echo "안내: 메일 자동 발송을 쓰지 않음(MAIL_MODE=none) — 회원 등록 때 초기 비밀번호가 화면에 표시됩니다"; echo "결과: 통과"; exit 0 ;;
esac
SEC=/etc/$PFX/secrets; CONF=$SEC/smtp.env; TMPPW=$SEC/mail-smtp-password; NM=/usr/local/sbin/$PFX-notify-mail
echo "== 메일 자동 발송 연동(SMTP 직접)"
fail(){ echo "실패: $*"; echo "결과: 실패"; exit 1; }
[ -x "$NM" ] || fail "$NM 이 없습니다(20 단계를 먼저 실행하세요)"
[ -n "${MAIL_SMTP_HOST:-}" ] && [ -n "${MAIL_FROM:-}" ] || fail "MAIL_SMTP_HOST·MAIL_FROM 이 설정되지 않았습니다"
install -d -m 0700 "$SEC"; umask 077
# 비밀번호: 설치기가 넣어 둔 임시 파일 → 없으면 기존 smtp.env 의 값을 유지(단계를 다시 실행해도 안전)
PW=""; if [ -r "$TMPPW" ]; then PW=$(cat "$TMPPW"); elif [ -r "$CONF" ]; then PW=$(sed -n 's/^SMTP_PASSWORD=//p' "$CONF" | head -1); fi
if [ -n "${MAIL_SMTP_USER:-}" ] && [ -z "$PW" ]; then echo "경고: SMTP 계정은 있는데 비밀번호가 없습니다 — 인증이 실패할 수 있습니다"; fi
{
  echo "# $PFX 메일 발송 설정 — devmaru-install 이 만들었다. root 만 읽는다(0600)."
  echo "SMTP_HOST=$MAIL_SMTP_HOST"; echo "SMTP_PORT=${MAIL_SMTP_PORT:-587}"; echo "SMTP_SECURITY=${MAIL_SMTP_SECURITY:-starttls}"
  echo "SMTP_USER=${MAIL_SMTP_USER:-}"; echo "SMTP_PASSWORD=$PW"; echo "MAIL_FROM=$MAIL_FROM"
  if [ "${MAIL_SMTP_VERIFY:-1}" = 0 ]; then echo "SMTP_VERIFY=0"; fi
} > "$CONF.new" && chmod 0600 "$CONF.new" && mv -f "$CONF.new" "$CONF" || { rm -f "$CONF.new"; fail "SMTP 설정 파일을 쓰지 못했습니다($CONF)"; }
rm -f "$TMPPW"; unset PW
echo "성공: SMTP 설정 저장 → $CONF (비밀번호는 이 파일에만 있습니다)"
if out=$("$NM" --check 2>&1); then echo "성공: ${out#성공: }"
else echo "$out" | tail -n 3 | sed 's/^/  > /'; echo "경고: SMTP 연결 시험에 실패했습니다 — 주소·포트·암호화·계정을 고친 뒤 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 52' 로 다시 실행하세요(그때까지 회원 등록 때 화면 전달 안내가 나옵니다)"; echo "결과: 통과"; exit 0; fi
if [ "${MAIL_TEST_SEND:-1}" != 0 ] && [ -n "${ADMIN_EMAIL:-}" ]; then
  if out=$("$NM" --test "$ADMIN_EMAIL" 2>&1); then echo "성공: ${out#성공: }"; else echo "$out" | tail -n 2 | sed 's/^/  > /'; echo "경고: 시험 메일 발송에 실패했습니다(연결은 되었습니다) — 보내는 주소(MAIL_FROM) 권한을 확인하세요"; fi
fi
echo "안내: 회원 등록($PFX-member-add) 때 초기 비밀번호와 Paseo QR 이 회원 메일로 갑니다. 시험: sudo $PFX-notify-mail --test <주소> · 설정은 docs/MAIL.md"
echo "결과: 통과"
