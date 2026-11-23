# 운영 가이드

> 설치가 끝난 뒤 **관리자가 매일·가끔 하는 일**을 모았습니다.
>
> 회원 추가·삭제, DB, 웹 공개, 업데이트, 점검, 백업까지 명령 중심으로 설명합니다.
>
> 아래 `<접두어>` 는 설치 때 정한 접두어입니다(기본 `devmaru`). 명령은 모두 서버에서 `sudo` 로 실행합니다.

| 하는 일 | 대표 명령 |
|---|---|
| [회원 추가 · 삭제 · 상태](#1-회원-관리) | `<접두어>-member-add` · `member-remove` · `member-status` |
| [회원 안내 전달 채널](ONBOARDING.md) | `<접두어>-onboard-deliver --check` · `<접두어>-member-link` |
| [회원 DB](#2-회원-db) | `<접두어>-member-db-setup` |
| [웹 공개 관리](#3-웹-공개-관리) | `<접두어>-site-caddy` |
| [업데이트](#4-업데이트) | `<접두어>-update` · `member-update-all` · `service-update` |
| [점검 · 로그](#5-점검과-로그) | `<접두어>-doctor` |
| [백업·복구·이관](#6-백업) | `<접두어>-backup-run` · `restore` · `migrate` (→ [RECOVERY](RECOVERY.md)) |
| 방화벽 | `<접두어>-firewall` (→ [FIREWALL](FIREWALL.md)) |
| AI 에이전트 계정(선택) | `<접두어>-agent-key` · `agent-setup` · `agent-audit` (→ [AGENT](AGENT.md)) |
| [외부 MCP 서비스](#7-외부-mcp-서비스) | `<접두어>-mcp-remote` |

---

## 1. 회원 관리

### 회원 추가

```bash
sudo <접두어>-member-add alice --email alice@example.org
```

한 번에 다음이 만들어집니다.

- 리눅스 계정 · 회원 전용 폴더(`/srv/<접두어>/users/alice`) · 개발 컨테이너(`dev-alice`)
- 초기 비밀번호(12자, 헷갈리는 문자 제외) — 첫 로그인에서 바꾸도록 설정됩니다. 첫 로그인 전까지는 SSH 비밀번호 인증이 열려 있어 짧은 비밀번호는 추측 위험이 있으므로 12자로 했습니다(복사·붙여넣기로 전달하는 것이 기본)
- Paseo 페어링 QR · 링크, 온보딩 안내 파일
- 회원 전용 PostgreSQL DB와 접속 정보(`~/.pgpass`)
- `alice.<도메인>` 웹 공개 블록(Caddy)
- 파일 서비스(SFTPGo) 계정

**회원 ID 규칙:** 소문자로 시작, 소문자·숫자·`_`·`-`, 2~32자.

> **초기 비밀번호는 어떻게 전달되나요?**
>
> 메일 자동 발송을 설정했다면 회원에게 메일로 갑니다.
>
> 설정하지 않았다면 등록이 끝날 때 **화면에 한 번 표시**됩니다. 회원에게 안전한 방법(메신저 금지)으로 전달하세요.
>
> **전달 채널**(`ONBOARD_CHANNELS`)로 메일 · **1회 열람 링크** · webhook 알림 · 출력용 안내문도 고를 수 있습니다. 링크 재발급은 `sudo <접두어>-member-link issue <ID>`(봉인했거나 비밀번호가 이미 바뀐 회원은 거부). 자세한 내용은 [회원 안내 전달 가이드](ONBOARDING.md).
>
> 전달이 끝나면 임시 파일을 정리합니다.

```bash
sudo <접두어>-onboarding-seal alice        # 온보딩 폴더의 페어링·초기 안내 임시 파일 삭제
```

### Paseo 페어링 다시 만들기

```bash
sudo <접두어>-paseo-pair-create alice       # 링크 + 안내 파일
```

> 페어링 링크는 **재발급해도 같은 값인 영구 자격증명**처럼 다뤄야 합니다. 회원에게만 전달하세요.

### 회원 상태 보기

```bash
sudo <접두어>-member-status alice                          # 계정 · DB 상태
sudo docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep dev-    # 회원 컨테이너
sudo <접두어>-member-tmux-status                           # 모든 회원의 tmux 세션
```

### 회원 삭제

```bash
sudo <접두어>-member-remove alice            # 확인 질문이 나옵니다
sudo <접두어>-member-remove alice --force    # 질문 없이
```

삭제할 때 일어나는 일:

1. 개발 컨테이너 삭제
2. 회원 PostgreSQL 역할을 잠그고 **보관 표시**(90일 뒤 덤프 후 정리 대상)
3. 파일 서비스·Samba 계정 삭제
4. 리눅스 계정과 홈 삭제, `alice.<도메인>` 웹 블록 삭제

> **데이터가 삭제될 수 있습니다.** 삭제 전에 필요하면 회원 폴더(`/srv/<접두어>/users/<ID>`)를 백업하세요.

---

## 2. 회원 DB

회원을 추가하면 DB가 자동으로 만들어집니다. 다시 하거나 암호를 바꿔야 할 때만 아래를 씁니다.

```bash
sudo <접두어>-member-db-setup alice                 # 새로 만들기(이미 있으면 거부 — 기존 앱이 끊기지 않게)
sudo <접두어>-member-db-setup alice --rotate        # 암호를 새로 정하고 ~/.pgpass 갱신
sudo <접두어>-member-db-setup alice --dry-run       # 무엇을 할지만 표시
```

- DB 이름은 기본 `<ID>_db` 입니다(`--db` 로 지정 가능).
- 회원 역할은 DB 생성이 가능하고 연결은 20개로 제한되며, **다른 회원의 DB는 접속할 수 없습니다.**
- ID에 하이픈(`-`)이 있으면 DB 이름 규칙(영문·숫자·밑줄) 때문에 자동 생성이 건너뛰어집니다.

---

## 3. 웹 공개 관리

회원이 만든 사이트는 `<ID>.<도메인>` 으로 공개됩니다. Caddy 블록은 등록할 때 자동으로 만들어지지만, 수동으로 다룰 수도 있습니다.

```bash
sudo <접두어>-site-caddy status           # 회원별 블록·포트 일치 여부, 공용 on/off (읽기 전용)
sudo <접두어>-site-caddy add alice        # 블록 만들기
sudo <접두어>-site-caddy remove alice     # 블록 삭제
sudo <접두어>-site-caddy shared on|off    # 공용 정적 공개(portal 주소 아래 <프로젝트>/) 켜기·끄기
```

접속 허용 대역(국가 등)을 제한하려면 `/etc/caddy/geo-allow.caddy` 를 고치고 `sudo systemctl reload caddy` 합니다. 자세한 방법은 [설치 가이드](INSTALL.md)의 «자주 하는 작업»을 보세요.

---

## 4. 업데이트

### 새 릴리스 적용

```bash
sudo <접두어>-update [릴리스 주소]       # 주소를 생략하면 설치할 때 쓴 주소
sudo <접두어>-member-update-all --check   # 회원 컨테이너 갱신 사전 점검
sudo <접두어>-member-update-all           # 전체 회원을 새 Golden 이미지로 갱신
```

- `update` 는 모든 설치 단계를 **다시 실행**합니다(비밀·설정은 유지, Golden 은 버전이 바뀔 때만 다시 빌드).
- **실행 중인 회원 컨테이너는 `update` 만으로는 바뀌지 않습니다.** 새 Golden 을 쓰려면 `member-update-all` 이 필요합니다.

> **`member-update-all` 의 원칙**
>
> - 전체 회원을 한꺼번에 갱신합니다(일부만 갱신하지 않습니다).
> - 리눅스 계정 · `/home` · workspace 는 유지하고, `dev-*` 컨테이너만 다시 만듭니다.
> - **실행 중인 tmux 세션이 하나라도 있으면 전체를 중단합니다.** `--check` 로 READY/BUSY 를 먼저 확인하세요.
> - 관리자 계정은 갱신 대상에서 제외됩니다.

```bash
sudo <접두어>-member-tmux-status            # 누가 작업 중인지 확인
sudo <접두어>-member-tmux-kill-all --yes    # 강제 종료(작업 중인 Claude/Codex 도 종료되므로 주의)
sudo <접두어>-member-runtime-recreate-all --check    # 컨테이너 설정만 다시 적용할 때(이미지 변경 없이)
```

### Golden 이미지(개발환경) 업데이트

Golden 은 회원 컨테이너가 쓰는 개발환경 이미지입니다. **새 릴리스에 들어 있는 버전으로** 빌드됩니다.

1. `sudo <접두어>-update` — 새 릴리스를 받고, Golden 버전이 바뀌었으면 설치 서버에서 **새로 빌드**합니다(수 분~수십 분).
2. `sudo <접두어>-member-update-all --check` — 회원 컨테이너 갱신 사전 점검(READY/BUSY).
3. `sudo <접두어>-member-update-all` — 전체 회원을 새 이미지로 갱신합니다.

| 하고 싶은 일 | 방법 |
|---|---|
| 현재 Golden 이미지 확인 | `grep '^GOLDEN_IMAGE=' /opt/<접두어>/config/dev-container.env` |
| 같은 버전을 처음부터 다시 빌드 (고급) | `sudo env GOLDEN_REBUILD=1 <접두어>-update --force` — 환경변수로 전달합니다 |
| 에이전트 CLI(Claude Code · Codex …) 최신화 | 회원이 컨테이너 안에서 CLI 자체 업데이트를 할 수 있습니다. 이미지에 고정된 버전을 바꾸려면 새 릴리스를 받습니다 |

> **현재 한계**
>
> - 회원 컨테이너 갱신은 전체를 한 번에 합니다. 새 이미지를 **먼저 격리 컨테이너로 검증하는(RC·canary)** 운영자 흐름은 [Golden 운영](GOLDEN.md) 을 보세요.
> - 그래서 갱신 전에 `--check` 로 작업 중인 회원이 없는지 확인하고, 이전 이미지를 지우지 않은 상태에서 진행하세요.
> - Golden 안의 도구 버전을 직접 고르는 기능은 없습니다(릴리스가 정한 버전).

### 루트 서비스(PostgreSQL · n8n · SFTPGo · Kordoc …) 업데이트

각 서비스의 이미지 버전은 **릴리스에 고정**되어 있습니다. 서비스를 올리는 정식 방법은 새 릴리스 적용입니다.

```bash
sudo <접두어>-update --check     # 새 릴리스와 변경 내역(서비스 버전 변경 포함) 확인
sudo <접두어>-update             # 확인 뒤 적용: compose 재적용 → 필요한 이미지 pull/빌드 → 서비스 재시작
sudo <접두어>-doctor             # 적용 뒤 점검
```

적용 전에 **백업을 먼저** 하세요(`sudo <접두어>-backup-run`). 특히 PostgreSQL · n8n · SFTPGo 는 데이터가 있습니다.

> **알아 둘 한계**
>
> - 서비스 하나만 올릴 때는 `sudo <접두어>-service-update <서비스> --plan` → `--apply` (백업·헬스 확인·실패 시 롤백, [SERVICE-UPDATE](SERVICE-UPDATE.md)). compose 의 이미지 태그를 직접 고치면 **다음 `update` 가 릴리스 값으로 되돌립니다.**
> - **PostgreSQL 주 버전(현재 18) 올리기는 지원하지 않습니다.** 데이터 디렉터리가 호환되지 않아 덤프·복원 같은 별도 절차가 필요합니다.
> - 업데이트 중에는 해당 서비스가 잠시 재시작됩니다. 회원이 많은 시간대는 피하세요.
> - 전체 `update` 의 롤백은 백업과 이전 릴리스(`update <이전 릴리스 주소>`)를 사용합니다(서비스 개별 롤백은 `service-update` 가 합니다).

> Golden canary 는 다음 버전에서 검토합니다.

---

## 5. 점검과 로그

```bash
sudo <접두어>-doctor          # 컨테이너 · DB 확장 · Caddy · 포털 · Golden 이미지 · 디스크를 한 번에 점검
sudo <접두어>-help            # 관리 명령 요약
```

| 보고 싶은 것 | 위치 |
|---|---|
| 설치 로그 | `/var/log/<접두어>-install.log` |
| Golden 빌드 로그 | `/var/log/<접두어>-golden-build.log` |
| 회원 등록 로그 | `/srv/<접두어>/logs/member-add/` |
| 웹 접근 로그 | `/var/log/caddy/access.log` |
| 서비스 로그 | `docker logs <컨테이너>` (예: `postgres`, `n8n`, `kordoc`) |

| 설정·데이터 | 위치 |
|---|---|
| 설치 설정 (비밀 없음) | `/etc/<접두어>/site.env` |
| 비밀 | `/opt/<접두어>/config/env/*.env` · `/etc/<접두어>/secrets/` (root 만 읽음) |
| Golden 이미지 설정 | `/opt/<접두어>/config/dev-container.env` |
| 회원 데이터 | `/srv/<접두어>/users/<ID>` |
| 온보딩 | `/srv/<접두어>/onboarding/<ID>` |
| 관리 스크립트 | `/opt/<접두어>/scripts/` |

---

## 6. 백업

`backup` 모듈을 선택했다면 restic 저장소가 준비되어 있습니다.

```bash
sudo <접두어>-backup-run                  # DR 스냅샷(DB 덤프 · 설정 · 회원 메타 · n8n · SFTPGo)
sudo <접두어>-backup-run --images         # 위 + 로컬 빌드 이미지 보관본(용량 큼)
sudo systemctl enable --now <접두어>-backup-weekly.timer    # 매주 일요일 새벽 자동 실행(기본은 꺼짐)
```

- 백업 결과는 `/var/lib/<접두어>/backup-last.status` 에 남습니다.
- 저장소는 `/srv/<접두어>/backups/restic`, 암호는 `/etc/<접두어>/secrets/restic-repository-password` 입니다.

> **저장소 암호 파일을 서버 밖에도 보관하세요.** 잃으면 백업을 복원할 수 없습니다.
>
> 같은 서버의 디스크에만 있는 백업은 디스크 고장에 대비가 되지 않습니다. 저장소를 다른 곳으로 복사하는 것도 권합니다.

**복구**는 `sudo <접두어>-restore`, 서버 이관은 `sudo <접두어>-migrate` 로 합니다 → [복구·이관 안내](RECOVERY.md). 아래는 도구 없이 직접 꺼내 보는 방법입니다.

```bash
export RESTIC_REPOSITORY=/srv/<접두어>/backups/restic
export RESTIC_PASSWORD_FILE=/etc/<접두어>/secrets/restic-repository-password
sudo -E restic snapshots                                   # 스냅샷 목록
sudo -E restic restore latest --target /tmp/restore        # 최신 스냅샷을 임시 폴더로 꺼내기
```

꺼낸 파일에서 필요한 것(DB 덤프, 설정 등)을 직접 골라 복원합니다. 복구 절차를 연습해 두는 것을 권합니다.

---

## 7. 외부 MCP 서비스

기본에서는 꺼져 있는 외부 공개 MCP 서비스(예: ALIO · K-Startup)를 «후보»로 켤 수 있습니다.

```bash
sudo <접두어>-mcp-remote list               # 후보와 켜짐 여부
sudo <접두어>-mcp-remote enable alio        # 켜기
sudo <접두어>-mcp-remote disable alio       # 끄기
```

켜도 **회원이 서비스 쪽에서 토큰을 신청**(GitHub 로그인)해 `~/.<접두어>/<이름>-token`(권한 600)에 저장해야 연결됩니다. 허브는 다음 요청부터 바로 반영합니다.

---

## 운영 원칙 요약

- **Golden 갱신은 전체 회원 대상으로만** 합니다. 계정 · 홈 · workspace 는 유지하고 컨테이너만 다시 만듭니다.
- **작업 중인 회원(tmux)이 있으면 갱신을 멈춥니다.** 먼저 `member-tmux-status` 로 확인하세요.
- **비밀은 설정 파일이 아니라 `secrets/` 와 `*.env`(root 600)에 있습니다.** `site.env` 는 비밀이 없습니다.
- **페어링 링크 · 초기 비밀번호는 회원에게만 전달**하고, 전달 뒤 `onboarding-seal` 로 정리합니다.
- 모든 명령은 **여러 번 실행해도 안전**하도록 만들었지만, 삭제(`member-remove`)는 되돌릴 수 없습니다.

---

## 문제 해결

| 증상 | 확인 |
|---|---|
| 회원이 로그인은 되는데 에이전트가 안 뜸 | `sudo docker ps -a \| grep dev-<ID>` 로 컨테이너 확인 → 없으면 `member-runtime-recreate-all` |
| `member-update-all` 이 «BUSY» 로 중단 | `member-tmux-status` 로 작업 중인 회원 확인 후 조율 |
| 회원 DB 접속 실패 | `member-status <ID>` 로 역할·DB 확인, 필요하면 `member-db-setup <ID> --rotate` |
| `<ID>.<도메인>` 이 안 열림 | `site-caddy status`, `journalctl -u caddy -n 50`, DNS(와일드카드 A 레코드) |
| MCP 연결 실패 | 회원 컨테이너에서 `claude mcp list` — 허브(`127.0.0.1:18940/healthz`) 응답 확인 |
| 디스크 부족 | `doctor` 의 `/srv` 여유 확인, 오래된 Docker 이미지·캐시 정리(`docker system df`) |

> 설치와 처음 설정은 [설치 가이드](INSTALL.md), 구조는 [구조 문서](ARCHITECTURE.md)를 보세요.
