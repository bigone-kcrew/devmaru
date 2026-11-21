#!/usr/bin/env bash
set -euo pipefail

AI_USER="${AI_USER:-member}"
AI_UID="${AI_UID:-1000}"
AI_GID="${AI_GID:-1000}"
@@PFX_UP@@_GID="${@@PFX_UP@@_GID:-@@GID@@}"

AI_HOME="/home/${AI_USER}"

# Primary group
if ! getent group "${AI_GID}" >/dev/null 2>&1; then
    groupadd --gid "${AI_GID}" "${AI_USER}"
fi

# Shared @@PFX@@ group
if ! getent group "${@@PFX_UP@@_GID}" >/dev/null 2>&1; then
    groupadd --gid "${@@PFX_UP@@_GID}" @@PFX@@
fi

# User
if ! id "${AI_USER}" >/dev/null 2>&1; then
    useradd \
        --uid "${AI_UID}" \
        --gid "${AI_GID}" \
        --home-dir "${AI_HOME}" \
        --no-create-home \
        --shell /bin/bash \
        "${AI_USER}"
fi

# Ensure supplementary membership for shared resources
usermod -aG @@PFX@@ "${AI_USER}"

mkdir -p \
    "${AI_HOME}/.local/bin" \
    "${AI_HOME}/.paseo"

chown -h "${AI_UID}:${AI_GID}" \
    "${AI_HOME}" \
    "${AI_HOME}/.local" \
    "${AI_HOME}/.local/bin" \
    "${AI_HOME}/.paseo" \
    2>/dev/null || true

export HOME="${AI_HOME}"
export USER="${AI_USER}"
export LOGNAME="${AI_USER}"
# PATH 는 root 구간에서 건드리지 않는다 — 멤버가 쓸 수 있는 ~/.local/bin 을 앞세우면
# root 로 도는 setpriv·rm·sleep·jq 가 멤버 파일로 바뀐다. 멤버 프로세스는 아래 env PATH= 로만 받는다.
MEMBER_PATH="${AI_HOME}/.local/bin:${PATH}"

# Synchronize @@BRAND@@ managed skills as the member.
if command -v @@PFX@@-skill-sync >/dev/null 2>&1; then
    if ! setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            @@PFX@@-skill-sync; then
        echo "WARNING: @@PFX@@-skill-sync failed; continuing startup." >&2
    fi
fi

# Synchronize @@BRAND@@ managed native plugins as the member.
# Plugin conflicts or user overrides are non-fatal and must not block startup.

if command -v @@PFX@@-plugin-sync >/dev/null 2>&1; then
    if ! setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            @@PFX@@-plugin-sync; then
        echo "WARNING: @@PFX@@-plugin-sync reported a conflict or non-fatal failure; continuing startup." >&2
    fi
fi

# MCP 허브를 Paseo «전에» 띄운다 — Paseo 가 세션을 자동 재개하는 순간 허브가 이미 응답해야 한다
# (keeper 가 뜨는 건 이 스크립트가 끝난 뒤라 그동안 http 등록 MCP 가 연결 실패했다). 이후 keeper 가 이 허브를 이어받는다.
# 허브 파일이 없거나 DISABLED 이면 건너뛴다. 실패해도 기동을 막지 않는다.
MCP_HUB=/opt/@@PFX@@/managed-mcp/hub/hub.mjs
if [[ -f "${MCP_HUB}" && ! -e /opt/@@PFX@@/managed-mcp/hub/DISABLED ]]; then
    setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            sh -c 'nohup node "$0" >>/tmp/@@PFX@@-mcp-hub.log 2>&1 &' "${MCP_HUB}" || true
    for _ in {1..20}; do
        curl -fsS -m 1 http://127.0.0.1:18940/healthz >/dev/null 2>&1 && break
        sleep 0.5
    done
fi

cd /workspace

# Paseo PID state is container-local and becomes stale after container restart/recreation.
rm -f "${AI_HOME}/.paseo/paseo.pid"

setpriv \
    --reuid="${AI_UID}" \
    --regid="${AI_GID}" \
    --init-groups \
    --inh-caps=-all \
    --ambient-caps=-all \
    -- env \
        HOME="${AI_HOME}" \
        USER="${AI_USER}" \
        LOGNAME="${AI_USER}" \
        PATH="${MEMBER_PATH}" \
        paseo daemon start >/dev/null 2>&1 || true

PASEO_CONFIG="${AI_HOME}/.paseo/config.json"
PASEO_BASELINE_MARKER="${AI_HOME}/.paseo/.@@PFX@@-baseline-v1"

# Paseo daemon may return before first-run config creation completes.
for _ in {1..10}; do
    [[ -f "${PASEO_CONFIG}" ]] && break
    sleep 0.5
done

if [[ -f "${PASEO_CONFIG}" && ! -L "${PASEO_CONFIG}" && ! -e "${PASEO_BASELINE_MARKER}" ]]; then
    tmp_config="$(mktemp)"

    if jq '
      .agents = (.agents // {}) |
      .agents.providers = (.agents.providers // {}) |
      .agents.providers.copilot = ((.agents.providers.copilot // {}) + {"enabled": false}) |
      .agents.providers.opencode = ((.agents.providers.opencode // {}) + {"enabled": false}) |
      .agents.providers.pi = ((.agents.providers.pi // {}) + {"enabled": false}) |
      .agents.providers.omp = ((.agents.providers.omp // {}) + {"enabled": false}) |
      .agents.providers.muse = ((.agents.providers.muse // {}) + {"enabled": false})
    ' "${PASEO_CONFIG}" > "${tmp_config}"; then

    chown "${AI_UID}:${AI_GID}" "${tmp_config}"
    chmod 0600 "${tmp_config}"
    mv "${tmp_config}" "${PASEO_CONFIG}"

    install -o "${AI_UID}" -g "${AI_GID}" -m 0600 /dev/null "${PASEO_BASELINE_MARKER}.tmp"
    mv -f "${PASEO_BASELINE_MARKER}.tmp" "${PASEO_BASELINE_MARKER}"

    setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            paseo daemon restart >/dev/null 2>&1 || true
    else
        echo "WARNING: paseo config.json 을 갱신하지 못했다(JSON 오류 등) — 이번 기동은 건너뛰고 다음에 다시 시도한다." >&2
        rm -f "${tmp_config}"
    fi
fi

# @@BRAND@@ Paseo 기본값 — 터미널 프로필과 Antigravity provider 활성.
#
# 왜 새 마커인가: 위의 baseline-v1 / agy-acp-v2 마커는 기존 회원에게 이미 있어
# 그 블록들은 다시 돌지 않는다. 여기에 얹으면 신규 회원에게만 적용된다.
#
# 왜 "키가 없을 때만" 인가: 회원이 직접 끈 설정을 되살리지 않기 위해서다.
# 기존 블록들은 antigravity.enabled 를 한 번도 쓰지 않는다 -- 그 키가 있다면
# 사람이 넣은 값이므로 존중한다.
#
# terminalProfiles 는 Paseo 에서 교체 의미다(병합이 아니다). 원하는 것을 모두
# 적어야 하며, 그래서 pi 와 opencode 는 자연히 목록에서 빠진다.
PASEO_TERMINAL_PROFILES_MARKER="${AI_HOME}/.paseo/.@@PFX@@-terminal-profiles-v2"

if [[ -f "${PASEO_CONFIG}" && ! -L "${PASEO_CONFIG}" && ! -e "${PASEO_TERMINAL_PROFILES_MARKER}" ]]; then
    tmp_config="$(mktemp)"

    if jq '
      .daemon = (.daemon // {}) |
      .daemon.terminalProfiles = (
        (.daemon.terminalProfiles // [
          { "id": "claude", "name": "Claude Code", "command": "claude",
            "args": ["{{{prompt}}}"], "icon": "claude" },
          { "id": "codex",  "name": "Codex",       "command": "codex",
            "args": ["{{{prompt}}}"], "icon": "codex" }
        ]) as $tp |
        if (.agents.providers.antigravity.enabled == false) then $tp
        elif ($tp | map(.id) | index("antigravity")) then $tp
        else $tp + [
          { "id": "antigravity", "name": "Antigravity", "command": "agy",
            "args": ["--prompt-interactive={{{prompt}}}"] }
        ] end
      ) |
      .agents = (.agents // {}) |
      .agents.providers = (.agents.providers // {}) |
      (if ((.agents.providers.antigravity // {}) | has("enabled")) then . else
        .agents.providers.antigravity =
          ((.agents.providers.antigravity // {}) + {"enabled": true})
      end)
    ' "${PASEO_CONFIG}" > "${tmp_config}"; then

    chown "${AI_UID}:${AI_GID}" "${tmp_config}"
    chmod 0600 "${tmp_config}"
    mv "${tmp_config}" "${PASEO_CONFIG}"

    install -o "${AI_UID}" -g "${AI_GID}" -m 0600 /dev/null "${PASEO_TERMINAL_PROFILES_MARKER}.tmp"
    mv -f "${PASEO_TERMINAL_PROFILES_MARKER}.tmp" "${PASEO_TERMINAL_PROFILES_MARKER}"

    setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            paseo reload >/dev/null 2>&1 || \
    setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            paseo daemon restart >/dev/null 2>&1 || true
    else
        echo "WARNING: paseo config.json 을 갱신하지 못했다(JSON 오류 등) — 이번 기동은 건너뛰고 다음에 다시 시도한다." >&2
        rm -f "${tmp_config}"
    fi
fi

# Paseo 0.11 이 번들 제공자로 넣은 Muse Code 를 기본으로 끈다 (2026-10-08 기존 회원 3명은 손으로 끔).
#
# 왜 새 마커인가: baseline-v1 은 기존 회원에게 이미 있어 다시 돌지 않는다.
# 왜 "키가 없을 때만" 인가: 회원이 직접 켜거나 끈 값은 존중한다.
PASEO_PROVIDERS_V3_MARKER="${AI_HOME}/.paseo/.@@PFX@@-providers-v3"

if [[ -f "${PASEO_CONFIG}" && ! -L "${PASEO_CONFIG}" && ! -e "${PASEO_PROVIDERS_V3_MARKER}" ]]; then
    tmp_config="$(mktemp)"

    if jq '
      .agents = (.agents // {}) |
      .agents.providers = (.agents.providers // {}) |
      (if ((.agents.providers.muse // {}) | has("enabled")) then . else
        .agents.providers.muse = ((.agents.providers.muse // {}) + {"enabled": false})
      end)
    ' "${PASEO_CONFIG}" > "${tmp_config}"; then

    chown "${AI_UID}:${AI_GID}" "${tmp_config}"
    chmod 0600 "${tmp_config}"
    mv "${tmp_config}" "${PASEO_CONFIG}"

    install -o "${AI_UID}" -g "${AI_GID}" -m 0600 /dev/null "${PASEO_PROVIDERS_V3_MARKER}.tmp"
    mv -f "${PASEO_PROVIDERS_V3_MARKER}.tmp" "${PASEO_PROVIDERS_V3_MARKER}"

    setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            paseo reload >/dev/null 2>&1 || \
    setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            paseo daemon restart >/dev/null 2>&1 || true
    else
        echo "WARNING: paseo config.json 을 갱신하지 못했다(JSON 오류 등) — 이번 기동은 건너뛰고 다음에 다시 시도한다." >&2
        rm -f "${tmp_config}"
    fi
fi

# Synchronize the @@BRAND@@ managed Paseo plugin.
#
# This runs after the Antigravity ACP v2 migration because Paseo must already
# be initialized and its daemon/config available. The helper owns the
# one-time plugin baseline and preserves post-baseline user disable/remove
# choices.
if command -v @@PFX@@-paseo-plugin-sync >/dev/null 2>&1; then
    if ! setpriv \
        --reuid="${AI_UID}" \
        --regid="${AI_GID}" \
        --init-groups \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- env \
            HOME="${AI_HOME}" \
            USER="${AI_USER}" \
            LOGNAME="${AI_USER}" \
            PATH="${MEMBER_PATH}" \
            @@PFX@@-paseo-plugin-sync; then
        echo "WARNING: @@PFX@@-paseo-plugin-sync reported a conflict or non-fatal failure; continuing startup." >&2
    fi
fi

exec setpriv \
    --reuid="${AI_UID}" \
    --regid="${AI_GID}" \
    --init-groups \
    --inh-caps=-all \
    --ambient-caps=-all \
    -- env PATH="${MEMBER_PATH}" "$@"
