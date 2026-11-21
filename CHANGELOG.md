# 📝 변경 내역

> 데브마루의 버전별 변경 내역입니다. 최신 버전이 위에 있습니다.
>
> 업데이트할 때 `sudo <접두어>-update` 가 **현재 버전 이후의 변경 내역을 먼저 보여 주고**, 확인한 뒤에 적용합니다.
>
> 변경 내역만 보려면 `sudo <접두어>-update --check` 를 쓰세요(아무것도 바꾸지 않습니다).

---

## 1.2.2 — 2026-11-17

### 🔧 개선

- 🧰 **Golden 이미지 갱신(운영 서버 Golden 0.6.0 반영)** — Claude Code 2.1.326 · Codex 0.169.0 · Paseo 0.16.0 · Antigravity 1.5.9 · Vercel CLI 65.16.0 · pnpm 12.21.0 · Playwright 1.65.1. Dockerfile 의 설치 순서를 정리해 빌드 캐시가 더 잘 맞고, 이미지에 남던 npm 캐시(`/root/.npm`)를 지웠습니다(운영 서버 실측 이미지 약 1.25GB 감소).
- 🧩 **스킬 갱신** — effective-html 번들이 8종(`one-pager` 추가)으로 늘어 Core 스킬이 22종이 됩니다. ui-ux-pro-max · agent-browser 0.43.0 · superpowers 플러그인 v7.0.2 로 올렸습니다(커밋 고정은 `golden/fetch-upstream.sh`).
- 📜 **회원 기본 전역 지침 갱신** — `config/agent-defaults` 가 `2026.11.19-1` 로 바뀌었습니다. `agent-config-link` 가 Antigravity 의 전역 지침(`~/.gemini/config/AGENTS.md`)도 연결합니다. 이미 있는 회원 파일은 덮어쓰지 않으므로(`KEEP`) **새로 만드는 회원에게만** 새 기본값이 적용됩니다.
- 🚀 **`ai-app renew` 가 앱 디렉터리 설정(dir)을 보존**하고, `kordoc-api` 에 OCR·메모·QR 코드 등 새 옵션(`--ocr-rec auto|printed`, `--ocr-det medium`, `--memos` 등, Kordoc REST API 1.11.0)을 반영했습니다.
- 🐤 **`golden canary` 가 옛 canary 데이터를 정리합니다** — 기본은 «목록만» 보여 주고, `AI_CANARY_PRUNE=apply` 일 때만 지웁니다(이번 버전 + 높은 2개 + 떠 있는 canary 는 보존).
- 📦 **서비스 이미지 갱신** — Kordoc 4.24.68(API 1.11.0), n8n 2.47.5, Ollama 0.40.16. 관리형 MCP(kordoc · markitdown · crawl4ai)의 MCP SDK 를 1.32.2 로 올렸습니다.
- 🩹 **설치기가 단계 출력의 깨진 UTF-8 에서 멈추던 것을 고쳤습니다**(`UnicodeDecodeError`) — Golden 빌드 진행 줄을 `cut -c` 가 바이트 단위로 자르면(한글·`…` 가 섞인 빌드 로그) 문자가 중간에서 끊겨 설치기가 중단되던 것을 `errors="replace"` 로 읽도록 바꿨습니다.
- 🩹 **모듈을 일부만 골라 설치한 서버에서 막히던 곳을 고쳤습니다**(Ubuntu 26.04 새 설치 시험에서 확인):
  - `openssh-server` 가 없는 최소 이미지에서 3단계(파일 배포)가 `/etc/ssh/sshd_config.d` 때문에 멈추던 것 → 기본 도구에 `openssh-server` 를 추가했습니다.
  - **막 설치돼 아직 접속을 한 번도 받지 않은 sshd** 에서 3단계 검증(`sshd -t`)이 «Missing privilege separation directory: /run/sshd» 로 실패하던 것(Ubuntu 26.04 의 소켓 활성화 sshd) → 검증 전에 `/run/sshd` 를 만듭니다(`agent-setup` 도 같습니다).
  - **files 모듈을 고르지 않으면 `member-add` 가 «SFTPGo API key unavailable» 로 실패**하던 것 → SFTPGo 계정만 건너뛰고 나머지는 진행합니다(회원 삭제 `member-remove` 도 같은 조건).
  - **n8n 모듈을 고르지 않으면 회원 DB 발급이 «database "n8n" does not exist» 로 실패**하던 것 → n8n 이 설치된 경우에만 보호 DB 목록에 넣습니다.
- 📄 **사무 문서 도구를 기본으로 포함합니다** — LibreOffice(Impress·Writer·Calc)와 한글 글꼴(Noto CJK·Nanum)이 개발환경 이미지에 들어가 pptx·docx·xlsx 를 변환·확인할 수 있습니다(`soffice --headless --convert-to`). 이미지가 약 **+0.6GB** 늘고 빌드 때 Ubuntu 저장소에서 내려받습니다. 용량이 부담이거나 저장소에 접근할 수 없으면 설정 파일(또는 마법사)에서 `GOLDEN_OFFICE=0` 으로 제외하세요.
- 🪟 **Windows 11 설치 안내 + WSL2 준비 스크립트(실험적)** — `docs/INSTALL.md` 에 «Windows PC 에 설치하려면» 절을 추가했습니다. **권장은 Hyper-V·VirtualBox 의 Ubuntu 26.04 VM**(Windows 위에서 직접 시험하지는 못함)이고, WSL2 는 `windows/install-windows.ps1` 로 지원합니다(**실험적**). 이 스크립트는 distro 설치, 부팅 때 distro 를 켜 두는 작업, mirrored 네트워킹(또는 `-Network portproxy`), 같은 LAN 에서만 열리는 방화벽 규칙, 회원 SSH 포트(기본 2222)를 준비하며 `-Apply` 없이 실행하면 계획만 보여 주고 `-Uninstall` 로 되돌립니다. 시험한 범위는 Windows 11 Pro 10.0.26300 · WSL 2.7.3 한 대(스크립트로 만든 distro 에 처음부터 설치, 재부팅 뒤 자동 복구, mirrored·portproxy 두 방식)이며, 사전 점검은 WSL 을 감지하면 경고를 냅니다(차단하지 않음).
- README · ROADMAP 의 버전·스킬 수 표기를 현재 값에 맞췄습니다.

### ✅ 이번 버전에서 확인한 것 · ⚠️ 확인하지 못한 것

**확인한 것** (Ubuntu 26.04 VM 과 Windows 11 WSL2 에서 직접 시험)
- 깨끗한 VM 에서 **처음부터 설치**(최소 모듈 · files·n8n 포함 두 가지)와 회원 등록·DB 발급·회원 SSH 경계(컨테이너 안에서만 실행)·한글 문서 변환.
- **1.2.1 → 1.2.2 `devmaru-update`**: 새 킷 받기·sha256 검증·변경 내역 표시·적용(Golden 이미지 재빌드 포함, 약 9분), 설정·회원 데이터 유지. 실행 중인 회원 컨테이너는 이전 이미지 그대로이고 `member-update-all` 로 바꿉니다(설계대로).
- WSL2 에서 재부팅 뒤 자동 복구(약 2분), 두 네트워크 방식(mirrored · portproxy)과 전환·`-Uninstall`.

**확인하지 못한 것**
- 자동 로그인이 꺼진 Windows PC, 다른 Windows 빌드, 회원이 많을 때의 부하.
- 방화벽·Samba·Cockpit 모듈, 실제 공인 도메인 인증서(`TLS_MODE=acme`)로의 설치.
- 이번 시험은 모두 한 번씩이며, 회원 수십 명 규모나 장기 운영은 시험하지 않았습니다.

### ⬆️ 1.2.1 에서 올릴 때 알아 둘 것

`sudo <접두어>-update` 로 올립니다. Golden 소스가 바뀌어 이미지를 **다시 빌드**하며(콜드 빌드 수십 분 걸릴 수 있음), 이미지 태그는 `1.2.2` 가 됩니다. 이후 `<접두어>-member-update-all` 로 회원 컨테이너를 새 이미지로 바꿉니다. 설정·회원 데이터는 그대로입니다.

---

## 1.2.1 — 2026-11-06

### 🔧 개선

- 🚢 **`service-update` 롤백이 태그·설정 변경도 되돌립니다** — 성공할 때마다 compose 디렉터리를 `last-good` 으로 저장하고, 올린 뒤 헬스가 실패하면 그것으로 복원합니다(이전에는 바꾼 compose 로 돌아가 이전 버전으로 못 돌아갔습니다). last-good 이 없으면 이미지 줄만 되돌립니다. 실패한 변경은 `compose.yml.failed-<시각>` 으로 남습니다. 데이터·DB 는 여전히 자동 복원하지 않습니다. → [서비스 업데이트](docs/SERVICE-UPDATE.md)
- 🔥 **방화벽이 docker 게시 포트에도 적용됩니다** — `apply` 가 `/etc/ufw/after.rules` 에 `DOCKER-USER` 블록을 넣습니다(자동 롤백·`rollback` 때 함께 원복). `plan` 이 docker 게시 포트의 허용/차단을 보여 줍니다. **주의:** 방화벽을 적용하면 SFTP 2022 가 외부에서 실제로 막힙니다. 외부에서 Files(SFTP)를 쓰려면 `ADMIN_CIDRS` 로 대역을 열어야 합니다. → [방화벽](docs/FIREWALL.md)
- 👤 **`member-add` 가 기존 회원 컨테이너 갱신을 안내합니다** — `WORKSPACE_OTHERS=read` 이고 다른 회원 컨테이너가 있으면 완료 메시지에 `member-update-all` 안내가 나옵니다(자동 재생성은 하지 않습니다). `doctor` 경고에도 같은 명령이 나옵니다.
- 🧪 **Golden 도구 정리** — `rc` 가 끝날 때 `releases/<버전>.changes` 작성 안내를 냅니다(없으면 `promote` 가 멈춥니다). `promote` 오류 문구에 할 일을 적었고, 승격 뒤 단발 빌드 이미지로 롤백했을 때 `check` 가 거짓 경고(종료 1)를 내던 것을 고쳤습니다. 파일로 돌릴 때 `rc` 출력 순서가 뒤섞이던 것도 바로잡았습니다.
- 📖 `docs/GOLDEN.md`: Ubuntu 26.04 의 sudo 는 `-E` 를 무시하므로 `sudo CANARY_USER=… ` · `sudo GOLDEN_VOICE=1 …` 형태로 정정했습니다.
- README 의 버전 표기를 현재 버전에 맞췄습니다.

### ✅ 이번 버전에서 확인한 것

공개 한 줄 설치로 1.2.0 새 설치, `devmaru-update` 의 GitLab 최신 릴리스 조회와 1.1.0→1.2.0 업데이트, `golden check|rc|selftest|canary|promote` 와 롤백·`member-update-all` 한 바퀴, `service-update` 실제 헬스 실패 롤백, 방화벽 자동 롤백. **아직 시험하지 못한 것:** 공인 인증서(Let's Encrypt) 발급, SMB 의 QUIC·Windows 접속, 메일 STARTTLS·인증, 방화벽 규칙의 재부팅 후 유지.

### ⬆️ 1.2.0 에서 올릴 때 알아 둘 것

`sudo <접두어>-update` 로 올립니다. Golden 이미지는 바뀌지 않아 다시 빌드하지 않으며, 설정·회원은 그대로 유지됩니다.

---

## 1.2.0 — 2026-11-05

### ✨ 새로 생긴 것

- 🔒 **회원 SSH 경계** — `ssh 회원@서버 '명령'` 이 호스트에서 실행되던 것을 막았습니다. 회원 그룹(관리자 계정 제외)은 sshd `ForceCommand` 로 모든 로그인·명령이 자기 개발환경(dev-<ID>) 안에서 실행되고, 포트 전달(-L)은 꺼집니다. sftp 는 파일 전송만 호스트에서 회원 권한으로 허용합니다. 포트 전달이 필요하면 `/etc/ssh/sshd_config.d/10-<접두어>.conf` 의 `AllowTcpForwarding` 을 바꿉니다.
- 🤖 **`agent` 모듈(선택, 기본 꺼짐)** — AI 에이전트 전용 계정 `<접두어>-agent`(SSH 키 전용 · 비밀번호 잠금 · 만료일), 키 관리 `<접두어>-agent-key add|remove|expire|status`
- 🛡 **제한된 sudo** — 점검·계획·백업 등 읽기성 명령만 비밀번호 없이(정확한 명령줄), 파괴적 명령은 사람 승인. `visudo -c` 실패 시 되돌림
- 📜 **감사 로그** — `/var/log/<접두어>/agent-audit.log`(sudo 로 실행된 명령, 주간 회전), `<접두어>-agent-audit [--tail N]` → [에이전트 계정](docs/AGENT.md)
- ♻️ **복구·이관** — `<접두어>-restore`(`list` · `plan`(기본) · `apply db|config|members|all`)와 `<접두어>-migrate export|import`(gpg 암호 묶음, 접두어·킷·Golden 버전 불일치 점검, 회원 workspace 는 rsync 안내로 분리). 둘 다 파괴적이라 에이전트 sudo 허용 목록에 넣지 않았습니다. → [복구·이관](docs/RECOVERY.md)
- 🚢 **서비스 개별 업데이트** — `<접두어>-service-update <서비스>|--all [--plan|--check|--apply]`: 백업 → 올리기 → 헬스 확인 → 실패 시 롤백. 기본은 `--plan`. → [서비스 업데이트](docs/SERVICE-UPDATE.md)
- 🔥 **방화벽 기본 구성(제안형)** — `<접두어>-firewall plan|apply|status|confirm|rollback`(ufw). 설치기는 적용하지 않고, apply 는 현재 SSH 접속을 점검한 뒤 적용하며 `confirm` 이 없으면 자동 롤백합니다. → [방화벽](docs/FIREWALL.md)
- 📂 **컨테이너 안 읽기 전용 마운트** — `WORKSPACE_OTHERS=read` 이면 다른 회원 workspace 가 컨테이너의 `/members/<회원>` 에 읽기 전용으로 보입니다. `SHARED_DEFAULT=ro`·readers/writers 는 `/shared` ACL 이 컨테이너 안에서도 적용됩니다. 기존 컨테이너는 `member-update-all` 로 재생성해야 반영됩니다. `access status` 가 어긋난 컨테이너를 알려 줍니다.
- 🧪 **Golden 갱신 도구** — `<접두어>-golden check|rc|selftest|canary|promote|progress`: `check`(읽기 전용) → `rc`(RC 빌드·selftest·canary) → `promote`(사람이 직접 승격) → `member-update-all`. 단발 빌드(설치·`update`)는 그대로입니다. 이미지 버전을 킷 버전과 분리했습니다(`GOLDEN_VERSION`). → [Golden](docs/GOLDEN.md)
- 🩺 **진단 묶음** — `<접두어>-support-bundle`: 비밀을 제외·마스킹한 진단 묶음(tar.gz, 권한 600)을 만듭니다(읽기 전용). `--selftest` 로 마스킹만 시험할 수 있습니다. → [지원](docs/SUPPORT.md)
- 👋 **회원 안내 템플릿** — 관리자가 회원에게 전달하는 시작 안내 한 장. → [회원 안내](docs/MEMBER-GUIDE.md)

### 🗑 제거

- 회원 기본 지침(`AGENTS.md`·`CLAUDE.md`)의 «Memory» 절을 뺐습니다 — 킷에 `memory` MCP 가 없어 에이전트가 없는 도구를 찾던 안내입니다. 호출 대상이 없는 Golden 스킬 `memory-save` · `memory-forget` · `memory-status` 는 킷에 실리지 않으며(1.1.0 킷에도 없었음), 옛 설치의 `images/dev/skills/` 에 남은 폴더가 있으면 `update` 가 지웁니다.

### 🔧 개선

- 설치 끝 체크리스트에 mail·smb 안내를 추가하고(해당 모듈을 골랐을 때만), `doctor` 에 smb 점검 2건을 더했습니다.
- `<접두어>-update` 가 새 Golden 을 빌드한 뒤 `GOLDEN_IMAGE` 포인터가 이전 킷 이미지를 가리키고 있으면 새 이미지로 옮깁니다(종전에는 처음 설치한 버전에 머물렀습니다). `promote` 로 더 높은 버전을 올린 서버는 건드리지 않습니다.
- 설치 가이드에 «준비물·하드웨어 기준», «DNS·포트 준비», «자주 나는 실패와 대처»를 추가했습니다(공인 인증서 발급은 아직 시험하지 못했음을 명시).
- 리허설 도구(`rehearsal/run.sh`)가 apt-daily 타이머를 막고 `systemd-run` 으로 설치기를 실행합니다(개발자용).

---

## 1.1.0 — 2026-11-04

### ✨ 새로 생긴 것

- 🔐 **접근 정책** — 관리자가 설정으로 정합니다.
  - `WORKSPACE_OTHERS=none|read` — 다른 회원이 내 workspace 를 읽을 수 있는지 (기본 `none`)
  - `SHARED_DEFAULT=rw|ro` — 공유 공간에서 회원의 기본 권한 (기본 `rw`)
  - 프로젝트별 `--readers` · `--writers`, 관리 명령 `<접두어>-access`(`status` · `set` · `apply` · `verify`)
  - 폴더 권한(ACL) · 파일 서비스(SFTPGo) · Windows 공유(Samba)를 함께 맞춥니다. → [접근 정책](docs/ACCESS.md)
- 🤖 **AI 에이전트와 함께 설치·운영** — Claude Code · Codex 가 읽는 안내서 `AGENTS.md` 와 [사용 가이드](docs/ADMIN-AGENT.md), `doctor --json` 을 추가했습니다.
- 📊 **`doctor --json`** — 점검 결과를 JSON 으로 출력합니다(자동화·에이전트용).
- 🔁 **업데이트가 변경 내역을 보여 줍니다** — `<접두어>-update` 는 최신 릴리스를 조회해 현재 버전 이후의 변경 내역을 보여 주고 확인을 받습니다.
  `--check` 로 확인만, `--yes` 로 질문 없이 적용할 수 있습니다.
- 📖 **문서** — [운영 가이드](docs/OPERATIONS.md)(회원 추가·삭제, DB, 웹 공개, 업데이트, 백업) · [설치 화면 둘러보기](docs/INSTALL-SCREENS.md)(터미널·웹 화면 스크린샷)

- ✉️ **메일 자동 발송 모듈** — SMTP 직접 발송 → n8n 웹훅 → 화면 수동 전달 순으로 대체합니다. → [메일](docs/MAIL.md)
- 🗄 **SMB 모듈(선택)** — Samba + SMB over QUIC(실패 시 tcp:445). QUIC 적재·Windows 11 접속은 미검증. → [SMB](docs/SMB.md)
- 🔁 **n8n 사용/미사용 선택과 워크플로 템플릿**(`member-onboarding`, `ops-notify`, 기본 비활성) → [n8n](docs/N8N.md)
- ✅ **첫 설정 체크리스트** — 설치 끝 화면(터미널·웹)과 설치 가이드에 서비스별로 안내합니다(비밀 값은 싣지 않음).

### 🔧 개선

- 웹 설치 화면: 진행 로그의 글자색을 어두운 배경에서도 잘 보이게 바꿨습니다(성공 초록 · 경고 주황 · 실패 빨강).
- 설치 가이드에 스크린샷을 넣고 형식(줄바꿈 · 표 · 아이콘)을 정리했습니다.
- 서드파티 구성요소 표에 출처 링크를 모두 달았습니다.

### 🐛 수정

- SSH 로 회원 컨테이너에 자동 입장하는 구성(로그인 훅·sudoers·sshd 드롭인)이 킷에 없던 것을 추가했습니다. 안내의 SSH 포트는 `SSH_PORT`(기본 22)를 따릅니다.
- Files(SFTPGo) 비밀번호 동기화(PAM)를 배포·적용합니다.
- 정적 공개용 샌드박스 Caddy 설정과 앱 공개 헬퍼(`app-sync-member` · `site-sync-member`)·타이머(단계 85)가 빠져 있던 것을 추가했습니다.
- Uptime Kuma 외부 접근 블록(관리자 대역 전용)을 추가했습니다. apt 잠금 충돌로 Cockpit 설치가 실패하던 것을 막았습니다.
- 관리형 MCP SDK 를 1.32.2 로 올렸습니다.

- `devmaru-help` 가 회원 추가 명령을 `member-add <username>` 으로만 안내하던 것을 `--email <address>` 를 포함하도록 고쳤습니다.

### ⬆️ 1.0.0 에서 올릴 때 알아 둘 것

0. ⚠️ **1.0.0 에 설치된 `update` 는 1.1.0 릴리스를 읽지 못하고 «현재 버전… 받을 릴리스» 한 줄만 보이고 멈춥니다**(tar 가 `*/VERSION` 을 두 곳에서 찾아 `head -1` 뒤 종료). 먼저 한 번만 `sudo sed -i "s#--wildcards '\*/VERSION'#--wildcards --no-wildcards-match-slash '*/VERSION'#" /usr/local/sbin/<접두어>-update` 를 실행한 뒤 아래 1번을 하세요. 1.1.0 이후는 고쳐져 있습니다.
1. `sudo <접두어>-update` 를 실행하면 변경 내역을 확인한 뒤 적용합니다. 설정·비밀은 그대로 유지됩니다.
2. **새 Golden 이미지**가 빌드됩니다(수 분~수십 분). 이어서 `sudo <접두어>-member-update-all --check` 후 `sudo <접두어>-member-update-all` 로 회원 컨테이너를 갱신해야 접근 정책의 새 동작이 적용됩니다.
3. 새 설정 키(`WORKSPACE_OTHERS` · `SHARED_DEFAULT`)의 기본값은 **기존 동작과 같습니다.** 설정을 바꾸지 않으면 달라지는 것이 없습니다.

---

## 1.0.0 — 2026-11-04

첫 공개 릴리스입니다.

- 설치기(터미널 · 웹 화면), 템플릿 트리, 접두어·서비스 이름·도메인을 설치할 때 정하는 구조
- 회원별 개발환경(Golden) · Paseo 원격 접속 · 웹 공개 · PostgreSQL · n8n · SFTPGo · Kordoc · MarkItDown · Crawl4AI
- `doctor` · `update` · restic 백업 · Cockpit(선택) · 외부 MCP 후보(`mcp-remote`)
