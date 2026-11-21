ARG UV_VERSION=0.13.8

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uvbin

# Paseo 로컬 음성 모델 — 멤버 홈(SSD) 3벌 대신 이미지 1벌 (2026-10-02).
# 메인 단계와 캐시가 독립이라 CLI 버전이 바뀌어도 다시 받지 않는다.
# 출처는 k2-fsa/sherpa-onnx 릴리스. Paseo 카탈로그에 체크섬이 없어 SHA256 을 직접 고정했고
# GitHub 자산 digest 와 일치함을 확인했다. 풀린 365개 파일은 kk 홈의 것과 이름·크기가 같았다.
FROM ubuntu:26.04 AS paseo-models
ARG PARAKEET_V2_SHA256=6fc4426b54aa549a0019b8a75b8dea59164e71790a37ac56a045ad57f915f714
ARG INSTALL_VOICE_MODELS=1
ARG KOKORO_SHA256=912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl bzip2 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    mkdir -p /out; cd /tmp; \
    if [ "${INSTALL_VOICE_MODELS}" = 1 ]; then \
    curl -fsSL --retry 3 -o parakeet.tar.bz2 \
      https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2; \
    echo "${PARAKEET_V2_SHA256}  parakeet.tar.bz2" | sha256sum -c -; \
    tar -xjf parakeet.tar.bz2 -C /out; \
    curl -fsSL --retry 3 -o kokoro.tar.bz2 \
      https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2; \
    echo "${KOKORO_SHA256}  kokoro.tar.bz2" | sha256sum -c -; \
    tar -xjf kokoro.tar.bz2 -C /out; \
    rm -f /tmp/*.tar.bz2; \
    test -f /out/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/encoder.int8.onnx; \
    test -f /out/kokoro-en-v0_19/model.onnx; \
    test "$(find /out -type f | wc -l)" = 366; \
    fi; \
    chown -R root:root /out; \
    chmod -R a-w,a+rX /out

FROM ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=@@TZ@@ \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bash-completion \
    ca-certificates \
    curl \
    wget \
    git \
    openssh-client \
    tmux \
    less \
    locales \
    shellcheck \
    ripgrep \
    fd-find \
    fzf \
    tree \
    jq \
    yq \
    acl \
    sqlite3 \
    postgresql-client \
    zip \
    unzip \
    tar \
    gzip \
    xz-utils \
    p7zip-full \
    file \
    rsync \
    gnu-coreutils \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    pkg-config \
    openssl \
    dnsutils \
    iputils-ping \
    iproute2 \
    netcat-openbsd \
    lsof \
    procps \
    socat \
    imagemagick \
    ffmpeg \
    bubblewrap \
    uidmap \
    util-linux \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 26.04 build-essential requires coreutils-from-uutils.
# Keep the distro provider installed, but prefer GNU mkdir.
# uutils mkdir 0.8.0 incorrectly creates sticky directories on
# @@BRAND@@ member workspaces, which breaks SFTPGo deletion semantics.
RUN test -x /usr/bin/gnumkdir \
    && ln -sf /usr/bin/gnumkdir /usr/local/bin/mkdir \
    && test "$(readlink -f /usr/local/bin/mkdir)" = "/usr/bin/gnumkdir" \
    && mkdir --version | head -n 1 | grep -F "GNU coreutils"

RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

WORKDIR /workspace

# --------------------------------------------------------------------
# Runtime versions
# [0.6-struct] B1: 도구 버전·체크섬 ARG 는 쓰는 RUN 바로 앞에 둔다(핀 하나가 바뀌어도 그 뒤 레이어만 다시 빌드). ARG 이름은 @@PFX@@-golden-rc·selftest·checks 가 읽으므로 바꾸지 않는다.
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# Runtime toolchain
# --------------------------------------------------------------------

# Node.js 24 LTS
#
# Pin the exact NodeSource Debian package used by the Golden Image.
# setup_24.x only configures the NodeSource 24.x repository; apt must not
# silently advance the runtime during a later rebuild.
ARG NODE_VERSION=24.22.3
ARG NODEJS_DEB_VERSION=24.22.3-1nodesource1

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends "nodejs=${NODEJS_DEB_VERSION}" \
    && test "$(dpkg-query -W -f='${Version}' nodejs)" = "${NODEJS_DEB_VERSION}" \
    && test "$(node --version)" = "v${NODE_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

# pnpm via Corepack

ENV COREPACK_HOME=/opt/corepack \
    COREPACK_DEFAULT_TO_LATEST=0 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

ARG PNPM_VERSION=12.21.0
RUN mkdir -p "${COREPACK_HOME}" \
&& corepack enable \
&& corepack prepare "pnpm@${PNPM_VERSION}" --activate \
&& chmod -R a+rX "${COREPACK_HOME}" \
&& test "$(pnpm --version)" = "${PNPM_VERSION}"

# Bun
ENV BUN_INSTALL=/opt/bun
ARG BUN_VERSION=1.4.4
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && ln -s /opt/bun/bin/bun /usr/local/bin/bun \
    && ln -s /opt/bun/bin/bunx /usr/local/bin/bunx

# GitLab CLI (glab) — gitlab.aigov.go.kr 등 회원이 쓰는 GitLab 용. 릴리스 tarball 을 핀·체크섬으로 받는다.
# 인증은 회원이 직접 한다(HTTPS + 개인 액세스 토큰: glab auth login --stdin). 토큰은 회원 홈에 저장된다.
ARG GLAB_VERSION=1.130.0
ARG GLAB_SHA256=ce06313b2075af25180cd195ab3496d42bc5857c85a1c12ba996838dfe9d822c
RUN curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz" -o /tmp/glab.tgz \
    && echo "${GLAB_SHA256}  /tmp/glab.tgz" | sha256sum -c - \
    && tar -xzf /tmp/glab.tgz -C /tmp bin/glab \
    && install -m 0755 /tmp/bin/glab /usr/local/bin/glab \
    && rm -rf /tmp/glab.tgz /tmp/bin \
    && test "$(glab --version | head -1 | awk '{print $2}')" = "${GLAB_VERSION}"

# GitHub CLI (gh) — Ubuntu 패키지(2.46.0)는 보안 권고가 다수 지난 낡은 버전이라 상류 릴리스 tarball 을 핀·체크섬으로 받는다(0.5.0).
ARG GH_VERSION=2.104.0
ARG GH_SHA256=98cb101ad87dbbd3f6b2f2bfcbd43197ccd07643140121d8a9cfaa91eadbc24e
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tgz \
    && echo "${GH_SHA256}  /tmp/gh.tgz" | sha256sum -c - \
    && tar -xzf /tmp/gh.tgz -C /tmp "gh_${GH_VERSION}_linux_amd64/bin/gh" \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tgz "/tmp/gh_${GH_VERSION}_linux_amd64" \
    && test "$(gh --version | head -1 | awk '{print $3}')" = "${GH_VERSION}"

# uv
COPY --from=uvbin /uv /uvx /usr/local/bin/

# Shared Python runtime for Optional Catalog Skills.
# The Optional Skills themselves are not bundled in the Golden Image.

ARG PYTHON_PPTX_VERSION=1.0.2
ARG LXML_VERSION=6.1.3
ARG PILLOW_VERSION=13.0.0
ARG XLSXWRITER_VERSION=3.3.1
ARG TYPING_EXTENSIONS_VERSION=4.16.0

RUN uv pip install --system --break-system-packages --no-cache \
    "python-pptx==${PYTHON_PPTX_VERSION}" \
    "lxml==${LXML_VERSION}" \
    "Pillow==${PILLOW_VERSION}" \
    "XlsxWriter==${XLSXWRITER_VERSION}" \
    "typing_extensions==${TYPING_EXTENSIONS_VERSION}" \
    && python3 -c 'import os,pptx,lxml,PIL,xlsxwriter; assert pptx.__version__==os.environ["PYTHON_PPTX_VERSION"]; assert lxml.__version__==os.environ["LXML_VERSION"]; assert PIL.__version__==os.environ["PILLOW_VERSION"]; assert xlsxwriter.__version__==os.environ["XLSXWRITER_VERSION"]; print("PYTHON_PPTX_RUNTIME=PASS")'

# --------------------------------------------------------------------
# Browser runtime
# --------------------------------------------------------------------

ARG PLAYWRIGHT_VERSION=1.65.1

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PLAYWRIGHT_SKIP_BROWSER_GC=1

RUN npx -y playwright@${PLAYWRIGHT_VERSION} \
      install --with-deps chromium \
    && chmod -R a+rX /opt/ms-playwright \
    && rm -rf /root/.npm

# --------------------------------------------------------------------
# Shared AI / deployment tools
# --------------------------------------------------------------------

# Build-time latest baseline
# [0.6-struct] B3: 도구별 RUN(한 도구의 핀 변경이 다른 도구의 설치를 다시 돌리지 않는다) · B2: npm 캐시 /root/.npm 은 같은 RUN 에서 지운다.
ARG CLAUDE_CODE_VERSION=2.1.326
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && rm -rf /root/.npm \
    && claude --version | grep -F "${CLAUDE_CODE_VERSION}"

ARG CODEX_VERSION=0.169.0
RUN npm install -g @openai/codex@${CODEX_VERSION} \
    && rm -rf /root/.npm \
    && codex --version | grep -F "${CODEX_VERSION}"

ARG PASEO_VERSION=0.16.0
RUN npm install -g @getpaseo/cli@${PASEO_VERSION} \
    && rm -rf /root/.npm \
    && paseo --version | grep -Fx "${PASEO_VERSION}"

ARG VERCEL_VERSION=65.16.0
RUN npm install -g vercel@${VERCEL_VERSION} \
    && rm -rf /root/.npm

# Google Antigravity CLI
ENV AGY_CLI_DISABLE_AUTO_UPDATE=true

ARG ANTIGRAVITY_VERSION=1.5.9
ARG ANTIGRAVITY_URL=https://github.com/google-antigravity/antigravity-cli/releases/download/1.5.9/agy_cli_linux_x64.tar.gz
ARG ANTIGRAVITY_SHA256=8b1f5e56779f2434a0af36f1b715a8392a084de550f8c68bc79821f95fabf3fa
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    curl -fsSL "${ANTIGRAVITY_URL}" -o "${tmp}/agy.tar.gz"; \
    echo "${ANTIGRAVITY_SHA256}  ${tmp}/agy.tar.gz" | sha256sum -c -; \
    tar -xzf "${tmp}/agy.tar.gz" -C "${tmp}"; \
    test -x "${tmp}/antigravity"; \
    install -m 0755 "${tmp}/antigravity" /usr/local/bin/agy; \
    /usr/local/bin/agy --version | grep -Fx "${ANTIGRAVITY_VERSION}"; \
    rm -rf "${tmp}"


# ---------------------------------------------------------------------

COPY entrypoint.sh /usr/local/bin/@@PFX@@-entrypoint
COPY @@PFX@@-user-bootstrap.sh /usr/local/bin/@@PFX@@-user-bootstrap
COPY @@PFX@@-workspace-create /usr/local/bin/@@PFX@@-workspace-create
COPY @@PFX@@-shared-workspace-create /usr/local/bin/@@PFX@@-shared-workspace-create

# Member-local CLIs (~/.local/bin) must win in every interactive bash, not only login shells.
# Otherwise `npm install -g` (prefix=~/.local) updates a copy that a non-login shell never runs,
# and the CLI's "update available" prompt repeats forever (0.4.23, codex).
RUN printf '%s\n' \
      '' \
      '# @@PFX@@: prefer member-local CLIs in interactive shells' \
      'if [ -d "$HOME/.local/bin" ]; then' \
      '  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac' \
      'fi' >> /etc/bash.bashrc

# @@BRAND@@ tmux baseline and workspace launchers
COPY tmux.conf /etc/tmux.conf
COPY tmx /usr/local/bin/tmx
COPY smx /usr/local/bin/smx
COPY @@PFX@@-shared-worktree-create /usr/local/bin/@@PFX@@-shared-worktree-create
COPY smw /usr/local/bin/smw
COPY @@PFX@@-skill-sync /usr/local/bin/@@PFX@@-skill-sync
COPY @@PFX@@-skill /usr/local/bin/@@PFX@@-skill
COPY @@PFX@@-plugin-sync /usr/local/bin/@@PFX@@-plugin-sync
COPY @@PFX@@-paseo-plugin-sync /usr/local/bin/@@PFX@@-paseo-plugin-sync
COPY paseo-plugins/@@PFX@@-managed-mcp /opt/@@PFX@@/paseo-plugins/@@PFX@@-managed-mcp
COPY @@PFX@@-ssh-key-add /usr/local/bin/@@PFX@@-ssh-key-add
COPY @@PFX@@-ssh-key-list /usr/local/bin/@@PFX@@-ssh-key-list
COPY @@PFX@@-ssh-key-remove /usr/local/bin/@@PFX@@-ssh-key-remove
COPY @@PFX@@-paseo-pair /usr/local/bin/@@PFX@@-paseo-pair
COPY kordoc-api /usr/local/bin/kordoc-api



COPY skills /opt/@@PFX@@/skills


# Ponytail pinned Core Skill
#
# Only the main ponytail skill is promoted to @@BRAND@@ Core. Companion modes
# remain optional until separately reviewed.
COPY upstream/ponytail/@@PFX_UP@@-UPSTREAM.txt /opt/@@PFX@@/upstream/ponytail/@@PFX_UP@@-UPSTREAM.txt

ARG PONYTAIL_VERSION=5.3.3
ARG PONYTAIL_COMMIT=7801d061243d7b753bad0e0b3c057cd250b11755
ARG PONYTAIL_SKILL_SHA256=9badd22a32e19cb884e46dfa8d3aae82bb81dfa5484105b8b4f0262df823a509
RUN test -f /opt/@@PFX@@/skills/ponytail/SKILL.md \
    && grep -Fx "name: ponytail" /opt/@@PFX@@/skills/ponytail/SKILL.md >/dev/null \
    && grep -Fx "license: MIT" /opt/@@PFX@@/skills/ponytail/SKILL.md >/dev/null \
    && echo "${PONYTAIL_SKILL_SHA256}  /opt/@@PFX@@/skills/ponytail/SKILL.md" | sha256sum -c - \
    && grep -Fx "version=${PONYTAIL_VERSION}" /opt/@@PFX@@/upstream/ponytail/@@PFX_UP@@-UPSTREAM.txt >/dev/null \
    && grep -Fx "commit=${PONYTAIL_COMMIT}" /opt/@@PFX@@/upstream/ponytail/@@PFX_UP@@-UPSTREAM.txt >/dev/null


# @@BRAND@@ 자체 제작 Core Skill — Catalog 에서 승격 (0.4.11)
#
# 두 skill 모두 COPY skills 로 이미 들어와 있다. 여기서는 출처 기록을 배치하고
# 내용이 승격 시점 그대로인지 검증한다.

ARG WEB_CRAWL_SKILL_SHA256=0f609737035c0f2df9585faeaa2dac539081f8815469fafdb6333607b3003594
RUN test -f /opt/@@PFX@@/skills/api-finder/SKILL.md \
    && grep -Fx "name: api-finder" /opt/@@PFX@@/skills/api-finder/SKILL.md >/dev/null \
    && true \
    && test -f /opt/@@PFX@@/skills/api-finder/references/UPSTREAM-ATTRIBUTION.md \
    && test -f /opt/@@PFX@@/skills/web-crawl/SKILL.md \
    && grep -Fx "name: web-crawl" /opt/@@PFX@@/skills/web-crawl/SKILL.md >/dev/null \
    && true


# 0.5.2: @@PFX@@-publish — 멤버 웹 공개·내 DB 절차(Core skill). COPY skills 로 이미 들어와 있고 여기서는 이름·내용 해시를 확인한다.
ARG AI_PUBLISH_SKILL_SHA256=ed54fc90f89795228b7765b360027702721a7112f1405a577980722844387a70
RUN test -f /opt/@@PFX@@/skills/@@PFX@@-publish/SKILL.md \
    && grep -Fx "name: @@PFX@@-publish" /opt/@@PFX@@/skills/@@PFX@@-publish/SKILL.md >/dev/null \
    && true


# Archify canonical Skill + runtime bundle
COPY upstream/archify/archify-v3.2.0.zip /tmp/archify-v3.2.0.zip
COPY upstream/archify/@@PFX_UP@@-UPSTREAM.txt /opt/@@PFX@@/upstream/archify/@@PFX_UP@@-UPSTREAM.txt

ENV ARCHIFY_UPDATE_CHECK_DISABLED=1

ARG ARCHIFY_VERSION=3.2.0
ARG ARCHIFY_ZIP_SHA256=70e210265c59f24dcbdf2a502ff671104b5454e7ee7d3554aecd86bad32384f5
RUN test ! -e /opt/@@PFX@@/skills/archify \
    && echo "${ARCHIFY_ZIP_SHA256}  /tmp/archify-v3.2.0.zip" | sha256sum -c - \
    && unzip -q /tmp/archify-v3.2.0.zip -d /opt/@@PFX@@/skills \
    && test -f /opt/@@PFX@@/skills/archify/SKILL.md \
    && test "$(jq -r '.version' /opt/@@PFX@@/skills/archify/package.json)" = "${ARCHIFY_VERSION}" \
    && cd /opt/@@PFX@@/skills/archify \
    && node bin/archify.mjs doctor >/tmp/archify-doctor.txt \
    && test "$(node scripts/check-update.mjs)" = '{"status":"silent","reason":"disabled"}' \
    && rm -f /tmp/archify-v3.2.0.zip /tmp/archify-doctor.txt

# Effective HTML pinned eight-skill bundle
COPY upstream/effective-html/effective-html-5ce160a3e76dc1c0f9301f8a1903704ec607636a.tar.gz /tmp/effective-html.tar.gz
COPY upstream/effective-html/@@PFX_UP@@-UPSTREAM.txt /opt/@@PFX@@/upstream/effective-html/@@PFX_UP@@-UPSTREAM.txt

ARG EFFECTIVE_HTML_TGZ_SHA256=3c7282f9eab805c04def3d71c41c36d364b10d3427900c3ca53c8e764bb71ad1
RUN for skill in \
      big-pics-little-words \
      design-artifact \
      html \
      html-diagram \
      html-plan \
      html-prototype \
      html-wireframe \
      one-pager; do \
        test ! -e "/opt/@@PFX@@/skills/${skill}"; \
    done \
    && true \
    && tar -xzf /tmp/effective-html.tar.gz \
         --strip-components=1 \
         -C /opt/@@PFX@@/skills \
    && for skill in \
      big-pics-little-words \
      design-artifact \
      html \
      html-diagram \
      html-plan \
      html-prototype \
      html-wireframe \
      one-pager; do \
        test -f "/opt/@@PFX@@/skills/${skill}/SKILL.md"; \
        grep -Fx "name: ${skill}" "/opt/@@PFX@@/skills/${skill}/SKILL.md" >/dev/null; \
    done \
    && rm -f /tmp/effective-html.tar.gz

# UI/UX Pro Max pinned seven-skill bundle
COPY upstream/ui-ux-pro-max/ui-ux-pro-max-e59ff376a41f7ca47b7541ad5c116495cbade3ee.tar.gz /tmp/ui-ux-pro-max.tar.gz
COPY upstream/ui-ux-pro-max/@@PFX_UP@@-UPSTREAM.txt /opt/@@PFX@@/upstream/ui-ux-pro-max/@@PFX_UP@@-UPSTREAM.txt

ARG UI_UX_PRO_MAX_TGZ_SHA256=d1f3f353aa6dd01270967814a02ab706f812dae21b44378a949e495b31938679
RUN for skill in \
      banner-design \
      brand \
      design \
      design-system \
      slides \
      ui-styling \
      ui-ux-pro-max; do \
        test ! -e "/opt/@@PFX@@/skills/${skill}"; \
    done \
    && true \
    && tar -xzf /tmp/ui-ux-pro-max.tar.gz \
         --strip-components=2 \
         -C /opt/@@PFX@@/skills \
    && for skill in \
      banner-design \
      brand \
      design \
      design-system \
      slides \
      ui-styling \
      ui-ux-pro-max; do \
        test -f "/opt/@@PFX@@/skills/${skill}/SKILL.md"; \
        grep -Fx "name: ${skill}" "/opt/@@PFX@@/skills/${skill}/SKILL.md" >/dev/null; \
    done \
    && python3 -m py_compile \
         /opt/@@PFX@@/skills/ui-ux-pro-max/scripts/search.py \
         /opt/@@PFX@@/skills/design-system/scripts/search-slides.py \
    && node --check /opt/@@PFX@@/skills/design-system/scripts/generate-tokens.cjs \
    && rm -f /tmp/ui-ux-pro-max.tar.gz

# agent-browser pinned native CLI + Skill runtime
#
# Reuse the existing Playwright Chromium under PLAYWRIGHT_BROWSERS_PATH.
# Do not run `agent-browser install` in the Golden Image or at member startup.

COPY upstream/agent-browser/agent-browser-linux-x64-v0.43.0 /tmp/agent-browser
COPY upstream/agent-browser/agent-browser-skill-data-0.43.0.tar.gz /tmp/agent-browser-skill-data.tar.gz
COPY upstream/agent-browser/skill/SKILL.md /opt/@@PFX@@/skills/agent-browser/SKILL.md
COPY upstream/agent-browser/@@PFX_UP@@-UPSTREAM.txt /opt/@@PFX@@/upstream/agent-browser/@@PFX_UP@@-UPSTREAM.txt

ENV AGENT_BROWSER_SKILLS_DIR=/opt/@@PFX@@/agent-browser/skill-data

ARG AGENT_BROWSER_VERSION=0.43.0
ARG AGENT_BROWSER_SHA256=8e69c9fb662514c9cf36e4911e94e913742ba066e55102486350e049dd847612
ARG AGENT_BROWSER_SKILL_DATA_SHA256=12f35fe3253762741a43be5bd203708c42c3b9df92b0032cd504e651540c1b14
RUN test ! -e /usr/local/bin/agent-browser \
    && echo "${AGENT_BROWSER_SHA256}  /tmp/agent-browser" | sha256sum -c - \
    && true \
    && install -m 0755 /tmp/agent-browser /usr/local/bin/agent-browser \
    && mkdir -p /opt/@@PFX@@/agent-browser \
    && tar -xzf /tmp/agent-browser-skill-data.tar.gz \
         -C /opt/@@PFX@@/agent-browser \
    && test -f /opt/@@PFX@@/agent-browser/skill-data/core/SKILL.md \
    && test -f /opt/@@PFX@@/skills/agent-browser/SKILL.md \
    && grep -Fx "name: agent-browser" /opt/@@PFX@@/skills/agent-browser/SKILL.md >/dev/null \
    && test "$(agent-browser --version)" = "agent-browser ${AGENT_BROWSER_VERSION}" \
    && agent-browser skills get core >/tmp/agent-browser-core.txt \
    && test -s /tmp/agent-browser-core.txt \
    && rm -f \
         /tmp/agent-browser \
         /tmp/agent-browser-skill-data.tar.gz \
         /tmp/agent-browser-core.txt

# Core Skill 총량 검증 — 모든 번들 추출이 끝난 뒤에만 유효하다.
# 번들 하나가 조용히 빠지는 것을 여기서 잡는다.
RUN test "$(ls -1 /opt/@@PFX@@/skills | wc -l)" = "22" \
    || { echo "ERROR: Core Skill 수가 22가 아니다: $(ls -1 /opt/@@PFX@@/skills | tr '\n' ' ')" >&2; exit 1; }


# @@BRAND@@ pinned native plugins
COPY plugins/superpowers/v7.0.2 /opt/@@PFX@@/plugins/superpowers/v7.0.2
COPY plugins/superpowers/@@PFX_UP@@-UPSTREAM.txt /opt/@@PFX@@/plugins/superpowers/@@PFX_UP@@-UPSTREAM.txt

ARG SUPERPOWERS_VERSION=7.0.2
ARG SUPERPOWERS_COMMIT=22f0b463e7a5e579904dd6211a520321035526f7
RUN test -d /opt/@@PFX@@/plugins/superpowers/v7.0.2/.git \
    && test "$(git -C /opt/@@PFX@@/plugins/superpowers/v7.0.2 rev-parse HEAD)" = "${SUPERPOWERS_COMMIT}" \
    && test "$(git -C /opt/@@PFX@@/plugins/superpowers/v7.0.2 describe --tags --exact-match)" = "v${SUPERPOWERS_VERSION}" \
    && test "$(jq -r '.version' /opt/@@PFX@@/plugins/superpowers/v7.0.2/.claude-plugin/plugin.json)" = "${SUPERPOWERS_VERSION}" \
    && test "$(jq -r '.version' /opt/@@PFX@@/plugins/superpowers/v7.0.2/.codex-plugin/plugin.json)" = "${SUPERPOWERS_VERSION}" \
    && test -z "$(git -C /opt/@@PFX@@/plugins/superpowers/v7.0.2 remote)" \
    && test -z "$(git -C /opt/@@PFX@@/plugins/superpowers/v7.0.2 status --porcelain)" \
    && test -f /opt/@@PFX@@/plugins/superpowers/@@PFX_UP@@-UPSTREAM.txt

ENV SUPERPOWERS_DISABLE_TELEMETRY=true

# hyperframes 는 기본으로 사용 데이터를 보낸다 (2026-09-24 실측: 1건 전송 확인).
# DO_NOT_TRACK 은 여러 도구가 공통으로 존중하는 관례 변수다.
ENV HYPERFRAMES_NO_TELEMETRY=1 \
    DO_NOT_TRACK=1

COPY workspace-base /opt/@@PFX@@/bootstrap/workspace-base

# Reject editor/backup artifacts from Golden Image payloads.
RUN if find \
       /opt/@@PFX@@/skills \
       /opt/@@PFX@@/bootstrap/workspace-base \
       -type f \
       \( -name '*.bak' -o -name '*.bak-*' -o -name '*~' \
          -o -name '*.orig' -o -name '*.rej' \
          -o -name '*.swp' -o -name '*.swo' \) \
       -print -quit | grep -q .; then \
       echo "ERROR: backup artifact found in Golden Image payload" >&2; \
       find \
         /opt/@@PFX@@/skills \
         /opt/@@PFX@@/bootstrap/workspace-base \
         -type f \
         \( -name '*.bak' -o -name '*.bak-*' -o -name '*~' \
            -o -name '*.orig' -o -name '*.rej' \
            -o -name '*.swp' -o -name '*.swo' \) \
         -print >&2; \
       exit 1; \
     fi

RUN chmod 755 \
    /usr/local/bin/@@PFX@@-entrypoint \
    /usr/local/bin/@@PFX@@-user-bootstrap \
    /usr/local/bin/@@PFX@@-workspace-create \
    /usr/local/bin/@@PFX@@-shared-workspace-create \
    /usr/local/bin/tmx \
    /usr/local/bin/smx \
    /usr/local/bin/@@PFX@@-shared-worktree-create \
    /usr/local/bin/smw \
    /usr/local/bin/@@PFX@@-skill-sync \
    /usr/local/bin/@@PFX@@-skill \
    /usr/local/bin/@@PFX@@-plugin-sync \
    /usr/local/bin/@@PFX@@-paseo-plugin-sync \
    /usr/local/bin/@@PFX@@-ssh-key-add \
    /usr/local/bin/@@PFX@@-ssh-key-list \
    /usr/local/bin/@@PFX@@-ssh-key-remove \
    /usr/local/bin/@@PFX@@-paseo-pair \
    /usr/local/bin/kordoc-api \
  && chmod 644 /etc/tmux.conf \
  && bash -n /usr/local/bin/tmx \
  && bash -n /usr/local/bin/smx \
  && bash -n /usr/local/bin/@@PFX@@-shared-worktree-create \
  && bash -n /usr/local/bin/smw \
  && bash -n /usr/local/bin/@@PFX@@-skill-sync \
  && bash -n /usr/local/bin/@@PFX@@-skill \
  && bash -n /usr/local/bin/@@PFX@@-plugin-sync \
  && bash -n /usr/local/bin/@@PFX@@-paseo-plugin-sync \
  && test -f /opt/@@PFX@@/paseo-plugins/@@PFX@@-managed-mcp/paseo-plugin.json \
  && test -f /opt/@@PFX@@/paseo-plugins/@@PFX@@-managed-mcp/index.server.ts \
  && bash -n /usr/local/bin/@@PFX@@-ssh-key-add \
  && bash -n /usr/local/bin/@@PFX@@-ssh-key-list \
  && bash -n /usr/local/bin/@@PFX@@-ssh-key-remove \
  && bash -n /usr/local/bin/@@PFX@@-paseo-pair \
  && bash -n /usr/local/bin/kordoc-api \
  && shellcheck \
       /usr/local/bin/tmx \
       /usr/local/bin/smx \
       /usr/local/bin/@@PFX@@-shared-worktree-create \
       /usr/local/bin/smw \
       /usr/local/bin/@@PFX@@-skill-sync \
       /usr/local/bin/@@PFX@@-skill \
       /usr/local/bin/@@PFX@@-plugin-sync \
       /usr/local/bin/@@PFX@@-paseo-plugin-sync \
       /usr/local/bin/@@PFX@@-ssh-key-add \
       /usr/local/bin/@@PFX@@-ssh-key-list \
       /usr/local/bin/@@PFX@@-ssh-key-remove \
       /usr/local/bin/@@PFX@@-paseo-pair \
       /usr/local/bin/kordoc-api \
  && tmux -L @@PFX@@-build-check -f /etc/tmux.conf \
       new-session -d -s @@PFX@@-build-check \
  && tmux -L @@PFX@@-build-check \
       show-options -g prefix | grep -qx 'prefix C-a' \
  && tmux -L @@PFX@@-build-check \
       show-options -g mouse | grep -qx 'mouse on' \
  && tmux -L @@PFX@@-build-check kill-server

# Persistent member containers are accessed with docker exec.
# Keep PID 1 signal-aware so docker stop can shut Paseo down cleanly.
COPY @@PFX@@-container-keeper /usr/local/bin/@@PFX@@-container-keeper

RUN chmod 0755 /usr/local/bin/@@PFX@@-container-keeper \
    && bash -n /usr/local/bin/@@PFX@@-container-keeper \
    && shellcheck /usr/local/bin/@@PFX@@-container-keeper

# Paseo 로컬 음성 모델 경로 설정 (config.json providers.local.modelsDir). keeper 가 첫 기동 때 한 번 호출한다.
COPY @@PFX@@-paseo-models-config /usr/local/bin/@@PFX@@-paseo-models-config

RUN chmod 0755 /usr/local/bin/@@PFX@@-paseo-models-config \
    && bash -n /usr/local/bin/@@PFX@@-paseo-models-config \
    && shellcheck /usr/local/bin/@@PFX@@-paseo-models-config

# 0.5.0: Paseo 직접 연결(파일 다운로드)을 멤버가 켜고 끄는 명령. 호스트 쪽 @@PFX@@-paseo-caddy 가 멤버별 서브도메인을 맡는다.
COPY @@PFX@@-paseo-host /usr/local/bin/@@PFX@@-paseo-host

RUN chmod 0755 /usr/local/bin/@@PFX@@-paseo-host \
    && bash -n /usr/local/bin/@@PFX@@-paseo-host \
    && shellcheck /usr/local/bin/@@PFX@@-paseo-host

# 0.5.1: 멤버 웹 공개 도구 — @@PFX@@-site(정적 페이지 publish/), @@PFX@@-app(서버 앱 공개 · 내 PostgreSQL · 시작 골격). 0.5.0 까지는 호스트 파일을 마운트해 전달했다.
COPY @@PFX@@-site /usr/local/bin/@@PFX@@-site
COPY @@PFX@@-app /usr/local/bin/@@PFX@@-app

RUN chmod 0755 /usr/local/bin/@@PFX@@-site /usr/local/bin/@@PFX@@-app \
    && bash -n /usr/local/bin/@@PFX@@-site \
    && bash -n /usr/local/bin/@@PFX@@-app \
    && shellcheck /usr/local/bin/@@PFX@@-site /usr/local/bin/@@PFX@@-app

# Paseo 로컬 음성 모델 (읽기 전용, 이미지 1벌).
# 데몬은 모델 디렉터리에 필요한 모델이 모두 있으면 내려받지 않는다. 경로는 @@PFX@@-paseo-models-config 가
# 멤버의 config.json(providers.local.modelsDir)에 지정한다 — 환경변수는 managed 데몬이 지워 쓸 수 없다.
# silero-vad 는 Paseo 패키지 내장 파일이고 데몬이 모델 디렉터리로 복사하므로,
# 읽기 전용 경로에서도 동작하도록 미리 넣어 둔다. 패키지 구조가 바뀌면 여기서 빌드가 실패한다.
# 소유권·권한은 models 단계에서 이미 root/읽기 전용으로 확정했다 — 여기서 chown -R 을 하면 1GB 레이어가 한 번 더 생긴다(0.4.24 첫 시도에서 실측).
COPY --from=paseo-models /out /opt/@@PFX@@/paseo-models
RUN set -eux; \
    a=/usr/lib/node_modules/@getpaseo/cli/node_modules/@getpaseo/server/dist/server/server/speech/providers/local/sherpa/assets/silero_vad.onnx; \
    test -f "$a"; \
    install -d -m 0755 /opt/@@PFX@@/paseo-models/silero-vad; \
    install -m 0644 "$a" /opt/@@PFX@@/paseo-models/silero-vad/silero_vad.onnx
# [0.6.1-office] 사무 문서 도구 — LibreOffice(Impress·Writer·Calc)와 한글 글꼴(Noto CJK·Nanum). pptx·docx·xlsx 변환·렌더링·재계산용.
# 버전은 고정하지 않는다: Ubuntu 26.04 저장소 «최신» 이라 빌드 시점마다 달라질 수 있다(ARG 로 핀을 두지 않는다). 실제 버전은 빌드 로그·selftest 출력으로 본다.
# 캐시: 핀 ARG 를 쓰는 모든 레이어 뒤, OS 업데이트 레이어 앞에 둔다 — 도구·스킬 핀이 바뀌어도 이 ~580MB 레이어는 다시 받지 않고, 이 레이어가 바뀌면 아래 OS 업데이트 레이어만 다시 만든다.
# 빌드 시 검증은 실패하면 빌드를 멈춘다(`soffice` 와 한글 글꼴이 없는 이미지가 RC 까지 가지 않게). 프로필은 임시 HOME 에 만들고 지운다.
ARG INSTALL_OFFICE=1
RUN if [ "${INSTALL_OFFICE}" = 1 ]; then \
    apt-get update \
    && apt-get install -y --no-install-recommends \
       libreoffice-impress libreoffice-writer libreoffice-calc \
       fonts-noto-cjk fonts-nanum \
    && rm -rf /var/lib/apt/lists/* \
    && h="$(mktemp -d)" && HOME="$h" soffice --headless --version | grep -E '^LibreOffice [0-9]+\.[0-9]+' && rm -rf "$h" \
    && fc-list :lang=ko family | grep -E 'Noto Sans CJK KR|Nanum' >/dev/null; \
    fi
# 어떤 RUN 에서도 쓰지 않는 출처 commit 핀 — @@PFX@@-golden-check 가 읽으므로 지우지 않는다(AUDIT B6).
# 값이 바뀌어도 아래 레이어만 다시 만들어지게 맨 끝에 둔다.
ARG EFFECTIVE_HTML_COMMIT=5ce160a3e76dc1c0f9301f8a1903704ec607636a
ARG UI_UX_PRO_MAX_COMMIT=e59ff376a41f7ca47b7541ad5c116495cbade3ee
# OS 패키지 보안·버그 업데이트(0.5.0). 앞쪽 apt 레이어는 빌드 캐시를 재사용하므로 마지막에 한 번 올린다.
# nodejs 는 NODEJS_DEB_VERSION 으로 고정한 것이라 hold 해서 건드리지 않는다. OS_UPDATE_DATE 를 릴리스마다 바꾸면 이 레이어만 새로 만들어진다.
ARG OS_UPDATE_DATE=20261117
RUN apt-get update \
    && apt-mark hold nodejs \
    && apt-get -y --no-install-recommends upgrade \
    && apt-mark unhold nodejs \
    && test "$(dpkg-query -W -f='${Version}' nodejs)" = "${NODEJS_DEB_VERSION}" \
    && rm -rf /var/lib/apt/lists/* \
    && install -d /opt/@@PFX@@ && echo "os-update ${OS_UPDATE_DATE}" > /opt/@@PFX@@/os-update.txt

ENTRYPOINT ["/usr/local/bin/@@PFX@@-entrypoint"]

STOPSIGNAL SIGTERM

CMD ["/usr/local/bin/@@PFX@@-container-keeper"]
