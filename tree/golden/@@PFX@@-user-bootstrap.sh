#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

echo "===== @@BRAND@@ 사용자 환경 준비 ====="
echo "회원 ID: $(id -un)"
echo "홈 경로: ${HOME}"
echo

mkdir -p \
    "${HOME}/.local/bin" \
    "${HOME}/.claude" \
    "${HOME}/.codex" \
    "${HOME}/.config"

# «워크스페이스 프로젝트는 HDD 다» — ${HOME} 은 SSD 다. 사람·에이전트가 습관적으로
# ~/workspace 에 프로젝트를 만들면 SSD 에 쌓인다(2026-09-30 실측 사고: 회원 프로젝트
# 하나가 7.2G 째 SSD 에 놓여 있었다). ${HOME}/workspace 를 정본 HDD 마운트(/workspace)로
# 잇는 심볼릭 링크를 매 기동마다 자기치유한다.
if [[ -e "${HOME}/workspace" && ! -L "${HOME}/workspace" ]]; then
    echo "🔴 ${HOME}/workspace 가 이미 «실제 디렉터리» 다 — 심볼릭 링크로 못 바꾼다."
    echo "   내용을 /workspace 로 옮긴 뒤 재기동하면 다음번엔 자동으로 링크가 걸린다."
elif [[ ! -e "${HOME}/workspace" ]]; then
    ln -s /workspace "${HOME}/workspace"
fi

# Allow users to self-update npm-installed CLI tools without root.
if command -v npm >/dev/null 2>&1; then
    current_npm_prefix="$(npm config get prefix 2>/dev/null || true)"
    if [[ "${current_npm_prefix}" != "${HOME}/.local" ]]; then
        npm config set prefix "${HOME}/.local"
    fi
fi

# Synchronize @@BRAND@@ managed skills into agent discovery paths.
if command -v @@PFX@@-skill-sync >/dev/null 2>&1; then
    echo "@@BRAND@@ Skill을 동기화합니다."
    @@PFX@@-skill-sync
fi

# Synchronize @@BRAND@@ managed MCP registrations.
if command -v @@PFX@@-mcp-sync >/dev/null 2>&1; then
    echo
    echo "@@BRAND@@ MCP를 동기화합니다."
    @@PFX@@-mcp-sync
fi

echo
echo "===== 설치된 주요 도구 ====="
echo "Claude Code: $(claude --version)"
echo "Codex CLI: $(codex --version)"
echo "Paseo: $(paseo --version)"
echo "Antigravity: $(agy --version)"
echo "Vercel: $(vercel --version)"
echo
echo "@@BRAND@@ 사용자 환경 준비가 완료되었습니다."
