#!/usr/bin/env bash
# SMB over QUIC(선택): Samba + 커널 QUIC 모듈(DKMS)로 Windows 11 네트워크 드라이브를 제공한다. 기본은 UDP 1443(QUIC)만 연다.
# 인증서: 공인 도메인이면 smb.<도메인> 의 Let's Encrypt(certbot, Caddy 80 포트 챌린지), TLS_MODE=internal 이면 자체 서명.
set -uo pipefail
case " $DEVMARU_MODULES " in *" smb "*) ;; *) echo "안내: smb 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
O=/opt/$PFX; SB=/srv/$PFX/samba; QUIC_COMMIT=bf47121683d987b0b20c79397704a6ae13911f88; QUIC_VER=bf471216
TRANSPORTS=${SMB_TRANSPORTS:-quic:1443}; warns=0
echo "== SMB(QUIC) 설정"
fail(){ echo "실패: $*"; echo "결과: 실패"; exit 1; }
warn(){ echo "경고: $*"; warns=$((warns+1)); }
[[ "$TRANSPORTS" =~ ^[a-z]+:[0-9]+(,[[:space:]]*[a-z]+:[0-9]+)*$ ]] || fail "SMB_TRANSPORTS 형식이 올바르지 않습니다(예: quic:1443 또는 tcp:445,quic:1443): $TRANSPORTS"
[ -r "$O/samba/smb.conf.tmpl" ] || fail "smb.conf 템플릿이 없습니다(20 단계를 다시 실행하세요)"

echo "  > 패키지 설치(samba · dkms · 커널 헤더$( [ "${TLS_MODE:-acme}" = internal ] || echo ' · certbot'))"
export DEBIAN_FRONTEND=noninteractive
PK="samba smbclient tdb-tools dkms build-essential openssl git linux-headers-$(uname -r)"
[ "${TLS_MODE:-acme}" = internal ] || PK="$PK certbot"
apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq $PK >/dev/null 2>&1 || fail "패키지 설치 실패($PK)"
echo "성공: 패키지(Samba $(smbd --version | awk '{print $2}'))"
# 배포판 기본 samba 서비스는 끈다 — 우리 설정으로 도는 <접두어>-samba-quic 만 쓴다
for u in smbd nmbd samba-ad-dc winbind; do systemctl disable --now "$u" >/dev/null 2>&1; done

# ---- QUIC 커널 모듈(전송에 quic 이 있을 때만)
QUIC_OK=0
if [[ ",$TRANSPORTS," != *quic:* ]]; then echo "안내: 전송에 quic 이 없어 QUIC 커널 모듈은 건너뜀($TRANSPORTS)"
elif modprobe quic 2>/dev/null; then QUIC_OK=1; echo "성공: quic 모듈이 이미 있음($(modinfo -n quic 2>/dev/null))"
else
  D=/usr/src/$PFX-quic-$QUIC_VER; G=$(mktemp -d)
  echo "  > QUIC 모듈 소스 받기(lxin/quic @ ${QUIC_COMMIT:0:8})"
  ( cd "$G" && git init -q && git fetch -q --depth 1 https://github.com/lxin/quic "$QUIC_COMMIT" && git checkout -q FETCH_HEAD && [ "$(git rev-parse HEAD)" = "$QUIC_COMMIT" ] ) || { rm -rf "$G"; fail "QUIC 소스를 받지 못했거나 커밋이 다릅니다"; }
  rm -rf "$D"; mkdir -p "$D"; cp -a "$G/modules" "$D/modules"; cp "$O/samba/quic-dkms/Makefile" "$O/samba/quic-dkms/dkms.conf" "$D/"; rm -rf "$G"
  # Ubuntu 7.0.0 ABI 38 이상은 새 네트워크 API 를 되가져오므로 상류 소스에 작은 호환 패치가 필요하다(GPL, 3개 파일)
  patch -p1 -s -d "$D" < "$O/samba/quic-dkms/ubuntu-abi38.patch" || fail "QUIC 호환 패치 적용 실패(상류 소스가 바뀌었을 수 있음)"
  dkms status "$PFX-quic/$QUIC_VER" 2>/dev/null | grep -q . || dkms add -m "$PFX-quic" -v "$QUIC_VER" >/dev/null 2>&1 || fail "dkms add 실패"
  echo "  > DKMS 빌드(커널 $(uname -r), 1~3분)"
  dkms build -m "$PFX-quic" -v "$QUIC_VER" -k "$(uname -r)" >/tmp/$PFX-quic-build.log 2>&1 || { tail -n 8 /tmp/$PFX-quic-build.log | sed 's/^/  > /'; fail "QUIC 모듈 빌드 실패(커널 헤더·소스 호환 확인, 로그 /tmp/$PFX-quic-build.log)"; }
  dkms install -m "$PFX-quic" -v "$QUIC_VER" -k "$(uname -r)" >/dev/null 2>&1 || fail "dkms install 실패"
  depmod -a
  if err=$(modprobe quic 2>&1); then QUIC_OK=1; echo "성공: QUIC 모듈 빌드·적재($(modinfo -n quic))"
  elif mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    warn "Secure Boot 가 켜져 있어 서명되지 않은 QUIC 모듈을 적재하지 못했습니다($err). DKMS 서명 키를 등록하세요: ① sudo mokutil --import /var/lib/dkms/mok.pub (비밀번호를 정함) ② 재부팅 → 파란 MOK 화면에서 «Enroll MOK» ③ 재부팅 뒤 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 56'. (또는 BIOS 에서 Secure Boot 를 끕니다)"
  else fail "modprobe quic 실패: $err"; fi
fi
echo quic > /etc/modules-load.d/$PFX-quic.conf

# ---- 디렉터리·설정
install -d -m 0755 "$SB" "$SB/state" "$SB/cache" "$SB/lock" "$SB/pid" "$SB/ncalrpc" /var/lib/$PFX/acme-webroot
install -d -m 0700 "$SB/private" "$SB/tls"
IF=""; [ "${SERVER_IP:-0.0.0.0}" != 0.0.0.0 ] && IF="    interfaces = $SERVER_IP
    bind interfaces only = yes"
awk -v tr="$TRANSPORTS" -v ifl="$IF" '{ if ($0=="__INTERFACES__") { if (ifl!="") print ifl } else { sub(/__TRANSPORTS__/, tr); print } }' "$O/samba/smb.conf.tmpl" > "$SB/smb.conf"
chmod 0644 "$SB/smb.conf"
testparm -s "$SB/smb.conf" >/dev/null 2>/tmp/$PFX-testparm.err || { sed 's/^/  > /' /tmp/$PFX-testparm.err | tail -5; fail "smb.conf 검증 실패"; }
echo "성공: smb.conf ($SB/smb.conf, 전송 $TRANSPORTS)"

# ---- 인증서
if [ "${TLS_MODE:-acme}" = internal ]; then
  if [ ! -s "$SB/tls/cert.pem" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 -keyout "$SB/tls/key.pem" -out "$SB/tls/cert.pem" -subj "/CN=$SMB_HOST" \
      -addext "subjectAltName=DNS:$SMB_HOST" -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1 || fail "자체 서명 인증서 생성 실패"
    cp "$SB/tls/cert.pem" "$SB/tls/ca.pem"; chmod 0600 "$SB/tls/key.pem"; chmod 0644 "$SB/tls/cert.pem" "$SB/tls/ca.pem"
  fi
  echo "성공: 자체 서명 인증서($SMB_HOST) — Windows 에서 신뢰하려면 cert.pem 을 «신뢰할 수 있는 루트»에 등록(docs/SMB.md)"
elif [ -s "$SB/tls/cert.pem" ]; then echo "안내: 인증서가 이미 있음($SB/tls/cert.pem)"
else
  echo "  > Let's Encrypt 인증서 발급($SMB_HOST — DNS A 레코드와 80 포트가 필요합니다)"
  if certbot certonly --webroot -w /var/lib/$PFX/acme-webroot -d "$SMB_HOST" -m "$ADMIN_EMAIL" --agree-tos --non-interactive \
       --deploy-hook "/usr/local/sbin/$PFX-samba-tls-deploy" >/tmp/$PFX-certbot.log 2>&1; then echo "성공: 인증서 발급·배포($SMB_HOST)"
  else
    tail -n 6 /tmp/$PFX-certbot.log | sed 's/^/  > /'
    warn "인증서 발급 실패 — DNS($SMB_HOST → 이 서버)와 80 포트를 확인한 뒤 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 56' 으로 다시 실행하세요(그때까지 SMB 서비스는 시작되지 않습니다)"
  fi
fi

# ---- 서비스
# 유닛은 시작 전에 quic 모듈을 적재한다 — quic 전송을 쓰지 않으면(예: tcp 만) 그 단계를 뺀다
UD=/etc/systemd/system/$PFX-samba-quic.service.d
if [[ ",$TRANSPORTS," == *quic:* ]]; then rm -rf "$UD"; else install -d "$UD"; printf '[Service]\nExecStartPre=\n' > "$UD/no-quic.conf"; fi
systemctl daemon-reload
NEEDQ=0; case ",$TRANSPORTS," in *quic:*) NEEDQ=1;; esac
if [ "$NEEDQ" = 1 ] && [ "$QUIC_OK" = 0 ]; then echo "안내: QUIC 모듈이 아직 없어 SMB 서비스는 시작하지 않았습니다(위 경고의 순서대로 처리한 뒤 56 단계를 다시 실행)"
elif [ -s "$SB/tls/cert.pem" ] && [ -s "$SB/tls/key.pem" ]; then
  systemctl enable "$PFX-samba-quic" >/dev/null 2>&1; systemctl restart "$PFX-samba-quic"; sleep 3
  systemctl is-active --quiet "$PFX-samba-quic" && echo "성공: $PFX-samba-quic 동작 중" || { journalctl -u "$PFX-samba-quic" -n 8 --no-pager | sed 's/^/  > /'; fail "$PFX-samba-quic 가 시작되지 않았습니다"; }
  for t in ${TRANSPORTS//,/ }; do
    p=${t#*:}; k=${t%%:*}
    if [ "$k" = quic ]; then ss -lun 2>/dev/null | grep -q ":$p " && echo "성공: UDP $p 리슨(QUIC)" || warn "UDP $p 가 열리지 않았습니다"
    else ss -ltn 2>/dev/null | grep -q ":$p " && echo "성공: TCP $p 리슨" || warn "TCP $p 가 열리지 않았습니다"; fi
  done
fi
echo "안내: 방화벽에서 위 포트(quic=UDP, tcp=TCP)를 열어야 외부에서 접속됩니다. 회원 등록 때 Samba 계정이 같이 만들어집니다(docs/SMB.md)"
echo "결과: 통과"
