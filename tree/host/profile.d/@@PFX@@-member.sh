# @@BRAND@@ member interactive SSH bootstrap
#
# 일반 회원:
#   SSH 로그인 -> dev-<username> -> /workspace
#
# 관리자 @@ADMIN_USER@@:
#   호스트에 그대로 유지
#
# 비대화형 SSH / SCP / SFTP:
#   영향 없음

if [ -n "${USER:-}" ] \
   && [ "$USER" != "@@ADMIN_USER@@" ] \
   && [ -d "/srv/@@PFX@@/users/$USER" ]; then

  # 필요할 때 직접 사용할 수 있는 실행 명령.
  tmx() {
    command @@PFX@@-dev-tmux "$@"
  }

  # 실제 대화형 SSH 터미널에서만 개발환경으로 자동 진입.
  if [[ $- == *i* ]] \
     && [ -n "${SSH_CONNECTION:-}" ] \
     && [ -t 0 ] \
     && [ -t 1 ] \
     && [ -z "${@@PFX_UP@@_DEV:-}" ]; then

    echo
    echo "=============================================="
    echo " @@BRAND@@ 개발환경"
    echo "=============================================="
    echo
    echo "회원 ID        : $USER"
    echo "개발환경        : dev-$USER"
    echo "개인 작업공간  : /workspace"
    echo
    echo "개발환경으로 연결합니다."
    echo
    echo "처음에는 아래 명령만 알아도 됩니다."
    echo
    echo "  claude    Claude Code 실행"
    echo "  codex     Codex 실행"
    echo "  tmx       여러 Agent를 함께 사용할 작업 세션"
    echo
    echo "GitHub는 선택 기능입니다."
    echo "필요할 때 Agent에게 \"GitHub 연결해줘\"라고 말하거나"
    echo "@@PFX@@-github-connect 를 실행하세요."
    echo
    echo "도움말: https://@@PORTAL_HOST@@/"
    echo

    exec @@PFX@@-dev
  fi
fi
