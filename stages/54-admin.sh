#!/usr/bin/env bash
# 웹 관리 화면(admin 모듈): 켜져 있으면 전용 비특권 계정·소켓 폴더·PAM 서비스 파일·감사 로그 자리·systemd 유닛 2개(도우미=root, 웹=비특권)를 만들고,
#   꺼져 있으면 유닛·Caddy 블록·PAM 파일을 지운다(TOTP 비밀 파일·감사 로그는 보존). 여러 번 실행해도 결과가 같다(유닛이 바뀌지 않으면 재시작하지 않아 로그인 세션이 유지된다).
#   Caddy 블록 자체는 50 단계가 만든다(modules/admin.caddy). TOTP 등록은 설치 뒤 관리자가 sudo <접두어>-admin-setup totp-enroll 로 한다.
set -uo pipefail
has(){ case " ${DEVMARU_MODULES:-} " in *" $1 "*) return 0;; esac; return 1; }
C=/etc/caddy; WU=$PFX-admin-web; HU=$PFX-admin-helper; WS=$PFX-admin-web
LC=$PFX-member-lifecycle; UD=/etc/systemd/system; PAMF=/etc/pam.d/$PFX-admin; RUNDIR=/run/$PFX-admin; LOGD=/var/log/$PFX; SECD=/etc/$PFX/secrets; TMPF=/etc/tmpfiles.d/$PFX-admin.conf; LRF=/etc/logrotate.d/$PFX-admin-audit
PORT="${ADMIN_WEB_PORT:-8433}"; LPORT="${ADMIN_LOCAL_PORT:-8444}"; LAN="${ADMIN_LAN_ADDR:-}"
echo "== 웹 관리 화면"
reload_caddy(){ command -v caddy >/dev/null 2>&1 || return 0
  if caddy validate --config "$C/Caddyfile" >/dev/null 2>&1; then chown -R caddy:caddy /var/log/caddy 2>/dev/null; systemctl reload caddy >/dev/null 2>&1; return 0; fi; return 1; }

if ! has admin; then
  # 꺼져 있다: 예전에 켰다면 서비스·유닛·PAM 파일·Caddy 블록을 치운다(TOTP 파일·감사 로그·웹 계정은 그대로 둔다)
  gone=0
  for u in "$WS" "$HU"; do
    if [ -e "$UD/$u.service" ]; then systemctl disable --now "$u.service" >/dev/null 2>&1; rm -f "$UD/$u.service"; gone=1; fi
  done
  if [ -e "$UD/$LC.timer" ] || [ -e "$UD/$LC.service" ]; then systemctl disable --now "$LC.timer" >/dev/null 2>&1; rm -f "$UD/$LC.timer" "$UD/$LC.service"; gone=1; fi   # 삭제 수명주기 타이머(상태 파일 <ID>.lifecycle.json 은 보존)
  [ "$gone" = 1 ] && systemctl daemon-reload
  for f in "$PAMF" "$TMPF" "$LRF"; do [ -e "$f" ] && { rm -f "$f"; gone=1; }; done
  [ -d "$RUNDIR" ] && { rm -f "$RUNDIR/helper.sock"; rmdir "$RUNDIR" 2>/dev/null; }
  if grep -q '^# >>> admin-web$' "$C/Caddyfile" 2>/dev/null; then
    cp -a "$C/Caddyfile" "$C/Caddyfile.pre-admin-off"
    sed -i '/^# >>> admin-web$/,/^# <<< admin-web$/d' "$C/Caddyfile"
    if reload_caddy; then echo "성공: Caddy 에서 admin 블록 제거"; gone=1
    else cp -a "$C/Caddyfile.pre-admin-off" "$C/Caddyfile"; echo "경고: Caddy 설정 검증 실패 — admin 블록 제거를 되돌렸습니다(sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 50 로 다시 만드세요)"; fi
    rm -f "$C/Caddyfile.pre-admin-off"
  fi
  [ "$gone" = 1 ] && echo "성공: admin 꺼짐 — 서비스 중지·유닛·PAM 파일 제거(TOTP 파일·감사 로그는 보존)"
  echo "결과: 통과"; exit 0
fi

# ── 켜져 있다 ──
for f in /usr/local/sbin/$PFX-admin-helper /usr/local/sbin/$PFX-admin-web /usr/local/sbin/$PFX-member-list /usr/local/sbin/$PFX-member-suspend /usr/local/sbin/$PFX-member-archive /usr/local/sbin/$PFX-member-lifecycle /usr/local/libexec/$PFX-admin/admin_common.py /usr/local/libexec/$PFX-admin/admin_pam.py; do
  [ -e "$f" ] || { echo "경고: $f 가 없습니다(20 단계를 먼저 실행하세요) — admin 을 켜지 못했습니다"; echo "결과: 통과"; exit 0; }
done
for p in "$PORT" "$LPORT"; do case "$p" in ''|*[!0-9]*) echo "경고: ADMIN_WEB_PORT·ADMIN_LOCAL_PORT 는 숫자여야 합니다($p) — admin 을 켜지 못했습니다"; echo "결과: 통과"; exit 0;; esac
  { [ "$p" -ge 1024 ] && [ "$p" -le 65535 ]; } || { echo "경고: 포트는 1024~65535 입니다($p) — admin 을 켜지 못했습니다"; echo "결과: 통과"; exit 0; }; done
if { ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT " ; } && ! systemctl is-active --quiet "$WS.service"; then
  echo "경고: 127.0.0.1:$PORT 를 다른 프로그램이 쓰고 있습니다 — site.env 의 ADMIN_WEB_PORT 를 바꾸고 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 50,54' 로 다시 실행하세요"; echo "결과: 통과"; exit 0
fi
# 도우미는 libpam 을 ctypes 로 부른다 — 없으면 로그인이 전부 실패하므로 여기서 멈춘다
{ python3 -I -c 'import ctypes.util,sys; sys.exit(0 if ctypes.util.find_library("pam") else 1)' 2>/dev/null || ldconfig -p 2>/dev/null | grep -q 'libpam\.so\.0'; } \
  || { echo "실패: libpam 을 찾을 수 없습니다(패키지 libpam0t64 · 10 단계 확인)"; exit 1; }
# 관리자 리눅스 계정 비밀번호(로그인에 쓰임) — 확인만 한다
st=$(passwd -S "$ADMIN_USER" 2>/dev/null | awk '{print $2}')
[ "$st" = P ] && echo "성공: 관리자 계정($ADMIN_USER) 비밀번호 설정됨" || echo "경고: 관리자 계정($ADMIN_USER)의 비밀번호 상태가 '${st:-알 수 없음}' 입니다(P 여야 웹 로그인 가능) — 'sudo passwd $ADMIN_USER' 로 설정하세요"
# 웹 전용 계정: 로그인 불가·홈 없음, docker·sudo·adm 그룹 금지
id "$WU" >/dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$WU" || { echo "실패: 계정 $WU 를 만들지 못했습니다"; exit 1; }
for g in $(id -nG "$WU" 2>/dev/null); do case "$g" in docker|sudo|adm|root) echo "실패: $WU 가 $g 그룹에 속해 있습니다 — 웹 계정은 권한 그룹에 넣지 않습니다(sudo gpasswd -d $WU $g)"; exit 1;; esac; done
WUID=$(id -u "$WU")
# 소켓 폴더: root 소유·웹 계정 그룹만 접근. 재부팅 뒤에도 서비스보다 먼저 생기도록 tmpfiles 에도 둔다
install -d -o root -g "$WU" -m 0750 "$RUNDIR"
install -d -m 0755 /etc/tmpfiles.d
printf 'd %s 0750 root %s -\n' "$RUNDIR" "$WU" > "$TMPF"; chmod 0644 "$TMPF"
# 감사 로그: root 0640, 그룹 adm(도우미가 시작 때 같은 값으로 맞춘다). 폴더가 이미 있으면 권한을 건드리지 않는다
[ -d "$LOGD" ] || install -d -o root -g adm -m 0750 "$LOGD"
[ -e "$LOGD/admin-audit.log" ] || { : > "$LOGD/admin-audit.log"; chown root:adm "$LOGD/admin-audit.log"; chmod 0640 "$LOGD/admin-audit.log"; }
# 감사 로그 주간 회전·8주 보관. 도우미는 기록할 때마다 파일을 새로 열므로(audit_write: os.open O_APPEND) copytruncate 없이 create 로 충분하다
install -d -m 0755 /etc/logrotate.d
printf '%s\n' "$LOGD/admin-audit.log {" '    weekly' '    rotate 8' '    missingok' '    notifempty' '    compress' '    delaycompress' '    create 0640 root adm' '}' > "$LRF"; chmod 0644 "$LRF"
# PAM 서비스 파일: pam_unix 만(common-auth·faillock 금지 — 웹 무차별 대입이 관리자 SSH 계정을 잠그지 않게)
t=$(mktemp); printf 'auth     required pam_unix.so\naccount  required pam_unix.so\n' > "$t"; install -m 0644 -o root -g root "$t" "$PAMF"; rm -f "$t"
echo "성공: PAM 서비스 파일 $PAMF (pam_unix 만)"
# 비밀 폴더가 없으면 root 전용으로 만든다(TOTP 파일이 여기 생긴다)
[ -d "$SECD" ] || install -d -o root -g root -m 0700 "$SECD"

# 도우미 유닛은 member-add(useradd·docker·메일·Caddy reload 를 root 로 실행)를 돌리므로 ProtectSystem·주소 제한·시스템콜/capability 제한을 걸지 않는다(설계서 §E 의 완화 세트). 웹 유닛은 엄격하게 유지. VM 에서 실제 member-add 로 확인할 것.
HOSTS="--allow-host ${ADMIN_HOST:-admin.$DOMAIN} --allow-host localhost:$LPORT"; [ -n "$LAN" ] && HOSTS="$HOSTS --allow-host $LAN"
write_unit(){ # <이름> — 표준입력을 유닛 파일로. 내용이 바뀌었으면 changed=1
  local t f="$1"; case $f in *.timer|*.service) ;; *) f=$f.service;; esac; t=$(mktemp); cat > "$t"
  if cmp -s "$t" "$UD/$f" 2>/dev/null; then rm -f "$t"; else install -m 0644 -o root -g root "$t" "$UD/$f"; rm -f "$t"; changed=1; fi; }
changed=0
write_unit "$HU" <<UNIT
[Unit]
Description=$BRAND 웹 관리 도우미(root — 인증·세션·작업 실행, 웹 계정만 소켓에 접속 가능)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -I /usr/local/sbin/$PFX-admin-helper --allow-uid $WUID --admin-user $ADMIN_USER --socket-group $WU --audit-group adm --reserved-ids /opt/$PFX/scripts/$PFX-reserved-ids
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictRealtime=yes
LockPersonality=yes
SystemCallArchitectures=native
UMask=0077
MemoryMax=512M
TasksMax=128

[Install]
WantedBy=multi-user.target
UNIT
write_unit "$WS" <<UNIT
[Unit]
Description=$BRAND 웹 관리 화면(127.0.0.1 전용 · 비특권 계정, 공개는 Caddy)
After=network.target $HU.service
Wants=$HU.service

[Service]
Type=simple
User=$WU
Group=$WU
ExecStart=/usr/bin/python3 -I /usr/local/sbin/$PFX-admin-web --port $PORT $HOSTS
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
IPAddressDeny=any
IPAddressAllow=localhost
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
UMask=0077
MemoryMax=256M
TasksMax=64

[Install]
WantedBy=multi-user.target
UNIT
# 회원 삭제 수명주기: 하루 한 번 tick(기한 1일 전·도래 알림, ADMIN_AUTO_DELETE=1 일 때만 자동 삭제, 보관 기간이 지난 아카이브 정리). 자동 삭제 기본은 꺼짐
lc_before=$changed; changed=0
write_unit "$LC.service" <<UNIT
[Unit]
Description=$BRAND 회원 삭제 수명주기 점검(알림·보관 기간이 지난 아카이브 정리)
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/bin/python3 -I /usr/local/sbin/$LC tick
Nice=10
TimeoutStartSec=2h
NoNewPrivileges=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
LockPersonality=yes
UMask=0077
UNIT
write_unit "$LC.timer" <<UNIT
[Unit]
Description=$BRAND 회원 삭제 수명주기 점검(매일)

[Timer]
OnCalendar=*-*-* 04:20:00
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
lc_changed=$changed; changed=$lc_before
systemd-tmpfiles --create "$TMPF" >/dev/null 2>&1
systemctl daemon-reload
for u in "$HU" "$WS"; do systemctl enable "$u.service" >/dev/null 2>&1; done
systemctl enable "$LC.timer" >/dev/null 2>&1
if [ "$lc_changed" = 1 ] || ! systemctl is-active --quiet "$LC.timer"; then systemctl restart "$LC.timer" >/dev/null 2>&1; fi
systemctl is-active --quiet "$LC.timer" && echo "성공: 회원 삭제 수명주기 타이머 동작(매일 · 자동 삭제 $([ "${ADMIN_AUTO_DELETE:-0}" = 1 ] && echo 켬 || echo 꺼짐))" || echo "경고: 회원 삭제 수명주기 타이머가 올라오지 않았습니다 — journalctl -u $LC"
# 유닛이 바뀌었거나 멈춰 있을 때만 (재)시작한다 — 다시 실행해도 로그인 세션이 끊기지 않게
for u in "$HU" "$WS"; do
  if [ "$changed" = 1 ] || ! systemctl is-active --quiet "$u.service"; then systemctl restart "$u.service"; fi
done
for i in 1 2 3 4 5 6 7 8; do ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT " && break; sleep 1; done
if systemctl is-active --quiet "$HU.service" && systemctl is-active --quiet "$WS.service" && ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT "; then echo "성공: 도우미·웹 서비스 동작(웹 127.0.0.1:$PORT)"
else echo "경고: 도우미 또는 웹 서비스가 올라오지 않았습니다 — journalctl -u $HU -u $WS"; fi
if [ -s "$SECD/admin-totp" ]; then echo "성공: TOTP 등록됨"; else echo "안내: TOTP 가 아직 등록되지 않았습니다 — sudo $PFX-admin-setup totp-enroll (그때까지 웹 로그인 화면은 «등록 필요» 만 표시합니다)"; fi
grep -q '^# >>> admin-web$' "$C/Caddyfile" 2>/dev/null && echo "성공: Caddy 에 admin 블록 연결(https://${ADMIN_HOST:-admin.$DOMAIN}/ · SSH 터널 https://localhost:$LPORT/${LAN:+ · 사설 https://$LAN/})" \
  || echo "경고: Caddyfile 에 admin 블록이 없습니다 — 'sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/$PFX/site.env --yes --only 50,54' 로 다시 만드세요"
[ -n "$LAN" ] && echo "안내: 사설 IP 접속(https://$LAN/)은 방화벽(ADMIN_CIDRS 에 사설 대역 포함)과 ADMIN_WEB_CIDRS 에 해당 대역이 있어야 하고, 브라우저 인증서 경고(tls internal)를 확인한 뒤 수락해야 합니다(docs/FIREWALL.md)"
echo "안내: 접속 순서 = https://${ADMIN_HOST:-admin.$DOMAIN}/ → SSH 터널(ssh -L $LPORT:127.0.0.1:$LPORT <관리자>@<서버> 후 https://localhost:$LPORT/) → 사설 IP. 평문 HTTP 는 없습니다"
echo "결과: 통과"
