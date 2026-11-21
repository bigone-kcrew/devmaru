#!/usr/bin/env bash
# Cockpit(웹 관리 콘솔, 선택): 설치하고 127.0.0.1:9090 에만 열어 Caddy(관리자 대역 제한)로 노출한다.
set -uo pipefail
case " $DEVMARU_MODULES " in *" cockpit "*) ;; *) echo "안내: cockpit 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
echo "== Cockpit 설정"
dpkg -s cockpit >/dev/null 2>&1 || { DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y -qq cockpit >/dev/null 2>&1 || { echo "실패: cockpit 설치 실패"; echo "결과: 실패"; exit 1; }; }
install -d /etc/cockpit /etc/systemd/system/cockpit.socket.d
cat > /etc/cockpit/cockpit.conf <<X
[WebService]
Origins = https://$COCKPIT_HOST wss://$COCKPIT_HOST
ProtocolHeader = X-Forwarded-Proto
X
printf '[Socket]\nListenStream=\nListenStream=127.0.0.1:9090\n' > /etc/systemd/system/cockpit.socket.d/listen.conf
systemctl daemon-reload; systemctl enable cockpit.socket >/dev/null 2>&1; systemctl restart cockpit.socket
sleep 1
ss -ltn 2>/dev/null | grep -q '127.0.0.1:9090' && echo "성공: Cockpit 127.0.0.1:9090 (외부 직접 접속 불가)" || { echo "실패: Cockpit 이 127.0.0.1:9090 에서 열리지 않음"; echo "결과: 실패"; exit 1; }
echo "안내: https://$COCKPIT_HOST/ — 관리자 대역($ADMIN_CIDRS)에서만 열리며, 리눅스 계정($ADMIN_USER)으로 로그인합니다"
echo "결과: 통과"
