#!/usr/bin/env bash
# 백업(선택): restic 저장소를 만들고 암호를 생성한다. 정기 실행(타이머)은 켜지 않는다 — 사용자가 정한다.
set -uo pipefail
case " $DEVMARU_MODULES " in *" backup "*) ;; *) echo "안내: backup 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
echo "== 백업 준비(restic)"
command -v restic >/dev/null 2>&1 || { apt-get -o DPkg::Lock::Timeout=300 install -y -qq restic >/dev/null 2>&1 || { echo "실패: restic 설치 실패"; echo "결과: 실패"; exit 1; }; }
echo "성공: restic $(restic version | awk '{print $2}')"
R=/srv/$PFX/backups/restic; P=/etc/$PFX/secrets/restic-repository-password
install -d -m 0700 "/srv/$PFX/backups" "/etc/$PFX/secrets"
[ -s "$P" ] || { umask 077; openssl rand -base64 33 > "$P"; chmod 0600 "$P"; echo "성공: 저장소 암호 생성 → $P"; }
if [ -f "$R/config" ]; then echo "안내: 저장소가 이미 있음 — $R"
else RESTIC_PASSWORD_FILE="$P" restic init --repo "$R" >/dev/null 2>&1 && echo "성공: restic 저장소 생성 → $R" || { echo "실패: restic init 실패"; echo "결과: 실패"; exit 1; }; fi
echo "경고: 저장소 암호 파일($P)을 서버 밖(비밀번호 관리자 등)에도 보관하세요 — 잃으면 백업을 복원할 수 없습니다."
echo "안내: 백업 실행: sudo $PFX-backup-run (정기 실행은 systemctl enable --now $PFX-backup-weekly.timer)"
echo "결과: 통과"
