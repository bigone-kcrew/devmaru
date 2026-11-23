#!/usr/bin/env bash
# 렌더링 → 배포: 템플릿 트리에 사용자 값을 넣고 서버 경로에 둔다. 그룹·디렉터리·도커 네트워크도 여기서 만든다.
set -euo pipefail
echo "== 파일 배포"
python3 - <<PY
import sys, os; sys.path.insert(0, os.environ["KIT"] + "/lib")
import devmaru_render as R
vals = {k: os.environ[k] for k in os.environ if k.isupper()}
left, bad = R.render_tree(os.environ["KIT"] + "/tree", os.environ["RENDERED"], vals)
if left or bad:
    print("실패: 렌더링 점검 실패", left[:3], bad[:3]); sys.exit(1)
print("성공: 렌더링 점검(미해결 토큰 0 · 문법 오류 0)")
PY
R="$RENDERED"; O=/opt/$PFX; S=/srv/$PFX
getent group "$PFX" >/dev/null || groupadd --gid "$GID" "$PFX"
[ "$(getent group "$PFX" | cut -d: -f3)" = "$GID" ] || { echo "실패: 그룹 $PFX 의 GID 가 $GID 가 아닙니다"; exit 1; }
usermod -aG "$PFX" "$ADMIN_USER"
echo "성공: 그룹 $PFX (gid $GID), $ADMIN_USER 추가"
install -d -o root -g "$PFX" -m 2775 "$O" "$S" "$S/users" "$S/shared" "$S/public" "$S/services"
# 온보딩 폴더: 그룹(회원 포함)이 쓸 수 없다 — 회원이 파일·심볼릭 링크를 심어 root 도구가 엉뚱한 파일을 읽거나 쓰게 하는 것을 막는다(0750, setgid 없음)
install -d -o root -g "$PFX" -m 0750 "$S/onboarding"
install -d -o root -g root -m 0755 "/etc/$PFX" "$S/admin-ops/site" "$S/admin-harness/bin" "$S/nvme" "$S/canary" "$S/public/portal" "$S/public/skills" "$S/public/tools" "$S/public/assets" "$O/config" "$O/config/env" "$O/images" "$O/compose" "$O/docs" "$O/tools"
install -d -o root -g root -m 0700 "/etc/$PFX/secrets"
cp_tree(){ [ -e "$R/$1" ] && { mkdir -p "$2"; rsync -a "$R/$1/" "$2/"; }; }
cp_tree host/scripts "$O/scripts"; cp_tree host/sbin /usr/local/sbin; cp_tree host/bin /usr/local/bin; cp_tree host/admin-bin "$S/admin-harness/bin"
cp_tree host/systemd /etc/systemd/system; cp_tree host/libexec /usr/local/libexec
# 문서가 안내하는 짧은 명령 이름(<접두어>-onboarding-seal)이 PATH 에 있게 한다 — 실제 파일은 $O/scripts 에 있다(1.4.0 은 이 링크가 없어 «command not found» 였다)
[ -x "$O/scripts/$PFX-onboarding-seal" ] && ln -sfn "$O/scripts/$PFX-onboarding-seal" "/usr/local/sbin/$PFX-onboarding-seal"
[ -d "$R/host/etc" ] && rsync -a --ignore-existing "$R/host/etc/" "/etc/$PFX/"   # 공개 샌드박스 설정·앱 한도(관리자가 고친 파일은 덮어쓰지 않는다)
# 회원 SSH 진입: 로그인 훅(자동으로 개발환경 입장) · sudoers(member-shell 한 명령만) · sshd 드롭인(회원 그룹만 비밀번호 로그인)
[ -d "$R/host/profile.d" ] && install -m 0644 "$R"/host/profile.d/* /etc/profile.d/
for f in "$R"/host/sudoers/*; do [ -f "$f" ] || continue; d=/etc/sudoers.d/$(basename "$f"); install -m 0440 "$f" "$d"; visudo -cf "$d" >/dev/null || { rm -f "$d"; echo "실패: sudoers 검증 실패 — $d"; exit 1; }; done
for f in "$R"/host/sshd/*; do [ -f "$f" ] || continue; d=/etc/ssh/sshd_config.d/$(basename "$f"); install -m 0644 "$f" "$d"; install -d -m 0755 /run/sshd; sshd -t || { rm -f "$d"; echo "실패: sshd 설정 검증 실패 — $d 를 되돌렸습니다"; exit 1; }; done
systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true
# SSH 비밀번호 변경 → 파일 서비스(SFTPGo)·Samba 비밀번호 동기화(PAM)
if [ -d "$R/host/pam" ]; then install -m 0644 "$R"/host/pam/* /usr/share/pam-configs/; pam-auth-update --package >/dev/null 2>&1 || echo "경고: pam-auth-update 실패 — 비밀번호 동기화가 꺼져 있을 수 있음"; fi
cp_tree golden "$O/images/dev"; rm -rf "$O"/images/dev/skills/memory-{save,forget,status}   # 1.2.0: 제거된 memory 스킬(rsync 는 지우지 않으므로 옛 설치에 남은 것을 치운다)
install -d -m 0755 "$O/images/dev/releases"   # Golden 운영 도구(<접두어>-golden)의 릴리스 기록 자리
cp_tree images/postgres "$O/images/postgres"; cp_tree compose "$O/compose"
cp_tree managed-mcp "$O/managed-mcp"; cp_tree member-tools "$O/member-tools"; cp_tree bootstrap "$O/bootstrap"
cp_tree config/agent-defaults "$O/config/agent-defaults"; cp_tree api-catalog/bin "$O/api-catalog/bin"; cp_tree caddy "$O/caddy"; cp_tree samba "$O/samba"; cp_tree n8n-workflows "$O/n8n-workflows"
systemctl daemon-reload
# 에이전트용 안내서: 실제 접두어·도메인으로 치환한 사본을 /opt/<접두어>/AGENTS.md 에 둔다
[ -f "$KIT/AGENTS.md" ] && { sed "s/<접두어>/$PFX/g; s#<도메인>#$DOMAIN#g" "$KIT/AGENTS.md" > "$O/AGENTS.md"; chmod 0644 "$O/AGENTS.md"; echo "성공: 에이전트 안내서 $O/AGENTS.md"; }
echo "성공: 파일 배포(스크립트 $(ls "$O/scripts" | wc -l)개, sbin/bin 링크 포함)"
# 도커 네트워크
while IFS='|' read -r n s; do
  case "$n" in ''|\#*) continue;; esac
  docker network inspect "$n" >/dev/null 2>&1 || docker network create --subnet "$s" "$n" >/dev/null
  echo "성공: 네트워크 $n ($s)"
done < <(sed "s/@@PFX@@/$PFX/g" "$KIT/config/networks.list")
# 접근 정책 초기 적용(공유 공간 /shared/workspaces·회원 목록 만들기). 정책은 site.env 의 WORKSPACE_OTHERS · SHARED_DEFAULT
"/usr/local/sbin/$PFX-access" apply --all >/dev/null 2>&1 && echo "성공: 접근 정책 적용(공유 공간 준비)" || echo "경고: 접근 정책 초기 적용 실패 — 설치 뒤 sudo $PFX-access apply --all"
echo "결과: 통과"
