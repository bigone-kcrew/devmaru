# 🤖 AGENTS.md — devmaru 서버를 관리하는 AI 에이전트를 위한 안내

> 이 문서는 **Claude Code · Codex 같은 AI 에이전트**가 이 서버의 설치·점검·운영을 도울 때 먼저 읽는 안내서입니다.
>
> 관리자(사람)가 서버에 SSH 접속 권한을 주었다는 전제입니다. 사람이 읽어도 됩니다.
>
> `<접두어>` 는 설치 때 정한 접두어입니다(기본 `devmaru`). 설치된 서버의 `/opt/<접두어>/AGENTS.md` 에는 실제 접두어로 치환된 사본이 있습니다.

---

## 🧭 먼저 알아 둘 것

- 이 서버는 **데브마루**: 회원별 개발환경(컨테이너)과 PostgreSQL · Caddy · (선택) n8n · SFTPGo · Kordoc 등을 한 대에 올린 환경입니다.
- 설정은 `/etc/<접두어>/site.env`(비밀 없음), 비밀은 `/opt/<접두어>/config/env/*.env` 와 `/etc/<접두어>/secrets/`(root 전용)에 있습니다.
- 명령은 모두 `<접두어>-*` 형식이고 `/usr/local/sbin` · `/usr/local/bin` 에 있습니다. 요약은 `sudo <접두어>-help`.
- 상세 문서: `/opt/devmaru-kit/docs/` — `INSTALL.md`(설치) · `OPERATIONS.md`(운영) · `ARCHITECTURE.md`(구조).

---

## 🚦 행동 규칙 (반드시 지키세요)

1. **읽기 전용부터.** 상태를 먼저 확인하고(`doctor --json`, `--plan`, `--check`), 그 결과를 근거로 판단합니다.
2. **오류가 나면 멈추세요.** 추측으로 고치지 말고, 원인과 제안하는 수정 내용을 관리자에게 설명한 뒤 승인을 받습니다.
3. **파괴적인 작업은 반드시 사람이 승인합니다.** 아래 «승인이 필요한 명령»은 실행하지 말고 **명령을 준비해서 관리자에게 보여 주세요.**
4. **비밀을 출력하지 마세요.** `*.env` · `secrets/` · 토큰 · 비밀번호 · 페어링 링크는 열어 보거나 대화·로그에 옮기지 않습니다. 필요하면 «어디에 있는지»만 안내합니다.
5. **회원의 대화·작업물을 열람하지 마세요.** `/srv/<접두어>/users/<ID>` 와 회원 컨테이너의 세션 제목·대화·파일 내용은 관리 작업에 필요하지 않습니다. 개수·상태 같은 **집계**만 봅니다.
6. **sudo 비밀번호를 대신 입력하거나 우회하지 마세요.** root 권한이 필요하면 «`! sudo <명령>` 을 실행해 주세요»처럼 관리자에게 맡깁니다.
7. **변경 전 백업·계획.** 설정 파일을 고치기 전에 `.bak.<날짜>` 사본을 만들고, 가능한 명령은 `--plan` 으로 먼저 확인합니다.
8. **한 번에 하나씩.** 여러 서비스를 동시에 건드리지 말고, 변경 뒤 `doctor` 로 확인합니다.

---

## 🔎 안전하게 쓸 수 있는 명령 (읽기 전용)

| 명령 | 용도 |
|---|---|
| `sudo <접두어>-doctor --json` | 전체 상태 점검 결과를 JSON 으로 (`status`, `warnings`, `checks[]`) |
| `sudo <접두어>-doctor` | 같은 점검을 사람이 읽기 쉬운 형식으로 |
| `sudo <접두어>-member-status <ID>` | 회원 계정 · DB 상태 |
| `sudo <접두어>-member-tmux-status` | 회원 tmux 세션 유무(집계) |
| `sudo <접두어>-member-update-all --check` | 회원 Golden 갱신 사전 점검 |
| `sudo <접두어>-site-caddy status` | 회원 웹 블록 일치 여부 |
| `sudo <접두어>-mcp-remote list` | 외부 MCP 후보와 켜짐 여부 |
| `sudo <접두어>-service-update <서비스>\|--all --plan\|--check` | 서비스별 업데이트 계획·점검(읽기 전용). `--apply` 는 승인 필요 |
| `sudo <접두어>-restore list\|plan` | 백업 복원 계획(읽기 전용) |
| `sudo <접두어>-firewall plan\|status` | 방화벽 계획·상태(읽기 전용) |
| `sudo <접두어>-agent-key status` · `<접두어>-agent-setup status` · `<접두어>-agent-audit` | agent 모듈 키·계정 상태, 감사 로그(읽기 전용) |
| `sudo python3 /opt/devmaru-kit/bin/devmaru-install --plan --config /etc/<접두어>/site.env` | 설치 계획만 표시(변경 없음) |
| `docker ps -a` · `docker logs <컨테이너> --tail 50` | 컨테이너 상태 · 최근 로그 |

`doctor --json` 의 `status` 가 `pass` 이고 `checks` 에 `fail` 이 없으면 정상입니다. `warn` 은 원인을 확인해 관리자에게 알립니다.

---

## ✋ 승인이 필요한 명령 (실행 전에 관리자에게 보여 주세요)

| 명령 | 위험 |
|---|---|
| `<접두어>-member-remove` | 계정·컨테이너·DB 보관 처리 — **되돌릴 수 없음** |
| `<접두어>-update` · `<접두어>-member-update-all` | 서비스 재적용 · 회원 컨테이너 재생성(작업 중 세션 영향) |
| `<접두어>-member-tmux-kill-all` | 회원의 실행 중 작업 강제 종료 |
| `<접두어>-member-db-setup --rotate` | DB 암호 교체(기존 앱이 끊길 수 있음) |
| `<접두어>-mcp-remote enable/disable` | 회원에게 보이는 서비스 변경 |
| `<접두어>-service-update … --apply` | 서비스 재시작(실패 시 자동 롤백) |
| `<접두어>-restore apply …` · `<접두어>-migrate import --apply` | 현재 데이터를 덮어씀 — **에이전트 sudo 허용 목록에 없음** |
| `<접두어>-firewall apply` · `rollback` | 접속 차단 위험(`confirm` 필요) |
| `<접두어>-agent-key add/remove/expire` · `<접두어>-agent-setup remove` | 에이전트 접근 권한 변경 |
| `<접두어>-migrate export` | 비밀이 든 암호 묶음 생성 |
| `devmaru-install` (`--plan` 제외) · 설정 파일 수정 | 서버 전체 변경 |
| `docker rm/prune` · `rm -rf` · Caddy·방화벽·SSH 설정 변경 | 서비스 중단 가능 |

---

## 🧰 자주 하는 일 — 절차

### 🚀 설치 (관리자가 설정 값을 알려 준 경우)

1. `/etc/<접두어>/site.env` 또는 설정 파일의 값(접두어 · 도메인 · 관리자 계정 · 모듈)을 관리자와 확인합니다.
2. `--plan` 으로 계획을 보여 주고 승인을 받습니다.
3. `sudo python3 /opt/devmaru-kit/bin/devmaru-install --config <파일> --yes` 로 설치합니다(관리자가 실행하도록 안내해도 됩니다).
4. 실패하면 **마지막 출력과 로그**(`/var/log/<접두어>-install.log`)를 보고 원인을 설명한 뒤, 승인을 받고 `--resume` 합니다.
5. 끝나면 `doctor --json` 으로 확인하고, 설치 화면의 «첫 설정 체크리스트»를 관리자에게 전달합니다.

### 🩺 점검 (정기)

`doctor --json` → `fail` 이 있으면 해당 컨테이너 로그를 확인하고 원인을 요약해 보고합니다. 디스크(`/srv` 여유)와 백업 상태(`/var/lib/<접두어>/backup-last.status`)도 봅니다.

### 👤 회원 추가

`sudo <접두어>-member-add <ID> --email <주소>` — 초기 비밀번호가 화면에 표시될 수 있으니 **출력 내용을 대화에 옮기지 말고** 관리자가 직접 전달하게 안내합니다.

### 🔁 업데이트

`<접두어>-update` 전에 `member-update-all --check`(READY/BUSY)와 `member-tmux-status` 로 작업 중인 회원을 확인하고, 관리자 승인 뒤 실행합니다.

### 💾 백업

`sudo <접두어>-backup-run` 은 읽기 전용에 가깝지만 부하가 있으니 시간대를 확인합니다. 복구는 `<접두어>-restore plan` 으로 계획을 보여 준 뒤 관리자의 승인 아래 `apply` 합니다.

---

## 🧩 알아 두면 좋은 것

- 컨테이너: `postgres`, `n8n`, `sftpgo`, `kordoc`, `markitdown`, `crawl4ai`(+`crawl4ai-api`), 회원 `dev-<ID>`. 선택한 모듈만 있습니다(`MODULES` in `site.env`).
- Golden 이미지 태그는 `/opt/<접두어>/config/dev-container.env` 의 `GOLDEN_IMAGE` 입니다.
- 설치기는 **여러 번 실행해도 안전**하게 만들었고, 비밀과 env 는 이미 있으면 유지합니다.
- 회원 접속은 Paseo 앱(페어링 링크) · SSH 입니다. 페어링 링크는 **영구 자격증명처럼** 다루며 열어 보지 않습니다.

---

## 🗺 앞으로

전용 에이전트 계정 · 제한된 sudo · 감사 로그는 **선택 모듈 `agent`**(기본 꺼짐)로 제공됩니다. 켜져 있으면 `<접두어>-agent` 계정이 허용 목록(`doctor`·`doctor --json`·`update --check`·`access status|verify|apply --all --plan`·`backup-run`)만 비밀번호 없이 실행할 수 있고, 그 밖의 명령은 사람 승인이 필요합니다. 기록은 `sudo <접두어>-agent-audit`. 자세한 내용은 [docs/AGENT.md](docs/AGENT.md). 모듈을 켜지 않았다면 **관리자가 sudo 를 직접 실행**하는 방식(`! sudo …`)을 권장합니다.
