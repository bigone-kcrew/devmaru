# @@BRAND@@ 멤버 Agent 프로젝트 작업 지침

이 문서는 @@BRAND@@ 멤버 계정에서 Claude Code·Codex·Antigravity에게 프로젝트 작업을 맡길 때 먼저 읽히는 공통 지침이다.

다운로드:

- [Agent 프로젝트 작업 지침(MD)](https://@@PORTAL_HOST@@/agent-project-brief.md)
- [전체 프로젝트 템플릿 ZIP](https://@@PORTAL_HOST@@/agent-project-template.zip)

ZIP은 문서와 디렉터리 구조를 함께 제공하는 샘플이다. 실제 값으로 바꾸기 전에는 실행·제출하지 않는다.

## Agent의 SSH 연결

### Agent가 사용자 PC에서 실행되는 경우

Agent는 사용자 PC의 SSH 개인키를 사용해 멤버 계정으로 접속한다.

```bash
ssh -p @@SSH_PORT@@ <member>@@@SSH_HOST@@
```

서버에는 공개키만 등록되어 있다. 개인키를 서버·컨테이너·프로젝트 폴더·Agent 대화에 업로드하거나 붙여넣지 않는다. 이미 사용 중인 SSH agent의 키를 그대로 사용할 수 있다.

### Agent가 이미 서버 SSH 세션 안에서 실행되는 경우

현재 세션이 이미 `@@SSH_HOST@@`의 멤버 계정이면 같은 서버로 SSH를 다시 실행하지 않는다. 현재 작업 디렉터리와 현재 계정을 확인한 뒤 그대로 작업한다.

```bash
whoami
pwd
```

다른 서버로의 추가 SSH 접속이 필요하면 개인키를 복사하지 말고 먼저 사용자에게 확인한다. SSH agent forwarding이나 별도 제한 키가 필요한 작업은 관리자 승인 없이 진행하지 않는다.

처음 접속할 때는 운영자가 확인한 host key인지 검증한 뒤 `known_hosts`에 등록한다. 확인되지 않은 fingerprint를 무조건 승인하지 않는다.

원격 명령과 파일 전송 예:

```bash
ssh -p @@SSH_PORT@@ <member>@@@SSH_HOST@@ 'cd /home/<member>/workspace/projects/<project> && pwd'
scp -P @@SSH_PORT@@ ./file <member>@@@SSH_HOST@@:/home/<member>/workspace/projects/<project>/
```

Agent는 `<member>` 자신의 HOME과 프로젝트만 사용한다. 원격에서 `sudo`, `sudo -u`, rootful Docker, `systemctl`, Caddyfile 수정 명령을 실행하지 않는다. SSH 인증 실패·권한 부족·host key 불일치가 나오면 재시도하거나 우회하지 말고 관리자에게 보고한다.

## 작업 경계

- 현재 SSH 계정과 승인된 프로젝트 디렉터리 안에서만 작업한다.
- `sudo`, host Docker socket, rootful Docker, `systemctl`, Caddyfile 직접 수정은 하지 않는다.
- `/etc`, `/opt`, 다른 회원의 HOME, 중앙 서비스 데이터에는 접근하지 않는다.
- secret, API key, password, token, private key는 코드·문서·git·로그·프롬프트에 넣지 않는다. 예외로 멤버 소유 `.env`(`umask 077`·`chmod 600`·`.gitignore`, `.env.example`에는 변수명만)에는 이 프로젝트 전용이고 Agent에게 보여도 되는 값만 둘 수 있다. 다른 회원·중앙 서비스 secret은 `.env`에도 넣지 않고, 운영 서비스로 승격할 때는 관리자가 별도 secret 경로로 옮긴다. DB 비밀번호는 `.env`에도 두지 않는다(아래 PostgreSQL).
- `privileged`, host network/PID/IPC, Docker socket mount, 임의 host bind mount를 사용하지 않는다.

## 먼저 읽을 파일

```text
PROJECT.md
ARCHITECTURE.md
OPERATIONS.md
deploy/service-request.yaml  (서비스 등록이 필요할 때만)
deploy/caddy-request.yaml  (외부 공개가 필요할 때만)
REQUEST/README.md  (관리자에게 부탁할 일이 있을 때만)
DESIGN.md  (화면·스타일을 만들거나 고칠 때만 — https://@@PORTAL_HOST@@/DESIGN.md)
```

파일이 없으면 작업 전에 생성 계획을 먼저 세우고, 추측으로 운영 설정을 만들지 않는다.

화면(HTML·CSS·컴포넌트)을 만들거나 고칠 때는 먼저 `DESIGN.md`를 읽고 그 토큰과 규칙을 따른다. 색·간격·반경은 값을 직접 쓰지 말고 `shared.css`의 토큰을 쓴다. 화면 작업이 아니면 읽지 않는다.

## 제출 패키지

```text
projects/<project>/
├── PROJECT.md                   # 목적·owner·사용자·데이터 분류·공개 범위
├── ARCHITECTURE.md              # API/MCP/RAG/DB·의존성·포트·데이터 흐름
├── OPERATIONS.md                # build/up/status/logs/down·health·백업·복구·중지
├── Dockerfile                   # 이미지 빌드 정의
├── .dockerignore                # 빌드 컨텍스트 제외(.env·.git·node_modules 등)
├── compose.member.yml           # 멤버 실행용 compose; 금지 설정과 자원 요구량 포함
├── deploy/
│   ├── service-request.yaml     # 서비스 등록 때만: 관리자 검토용 서비스·이미지·포트·health 요청
│   └── caddy-request.yaml       # 외부 공개 때만: hostname·path·upstream·인증·만료일
├── REQUEST/                     # 관리자에게 부탁할 일이 있을 때만
│   ├── README.md                # 요청 목록과 상태(대기·전달됨·적용됨·거절) 한 줄씩
│   └── YYYY-MM-DD-<주제>.md     # 요청 1건당 문서 1개
├── mcp/                         # MCP 서버 코드·transport·tool 목록·README
└── rag/                         # 수집·색인 파이프라인·스키마·재색인 방법
```

각 파일은 이름만 만들어 두지 않는다. 문서에는 목적, 소유자, 데이터 분류, API/MCP/DB 흐름, health check, 백업·복구, 중지 방법, 필요한 포트와 CPU/RAM/PID/디스크 요구량을 실제 값 또는 `미정`으로 기록한다. `미정`인 항목은 실행 전에 관리자에게 확인한다.

`deploy/service-request.yaml`은 서비스 등록이 필요할 때만 만든다. 컨테이너만·DB만·RAG만·내부 작업만 하는 프로젝트에는 필요 없다.

## 최소 작성 예시

아래 예시는 형식만 보여 주는 안전한 축약본이다. `<...>`를 실제 값으로 바꾸고, secret은 넣지 않는다.

`PROJECT.md`

```markdown
# <프로젝트명>
- owner: <member>
- 목적: <한 문장>
- 데이터: <public/internal/sensitive>
- 공개: <no / 정적 publish / 서버 앱(@@PFX@@-app) / 관리자 승인 경로>
```

`ARCHITECTURE.md`

```markdown
# 구조
- service: <service-name>
- interface: <REST 또는 MCP>
- database: <member-owned DB 또는 none>
- flow: client -> service -> database
- upstream/외부 의존성: <목록과 이유>
```

`OPERATIONS.md`

```markdown
# 운영
- build: @@PFX@@-project-build <user> <project>
- start/stop: @@PFX@@-project-up/down <user> <project>
- health: <명령 또는 URL>
- logs: @@PFX@@-project-logs <user> <project>
- backup/restore: <방법 또는 미정>
- 자원: CPU <값>, RAM <값>, PID <값>, disk <값>
```

`deploy/service-request.yaml` (서비스 등록이 필요할 때만 · 읽는 helper 없이 관리자가 직접 검토)

```yaml
# 표시가 없는 줄은 모두 필수. CPU/RAM/PID/disk 요구량은 이 파일이 아니라 OPERATIONS.md·compose.member.yml 에 적는다.
version: "1"
request_id: <request-id>
owner: <member>
project: <project>
service: <service-name>
image: <image-and-digest>
container_port: <container-port>
loopback_port: admin-assigned   # 값을 그대로 둔다. host loopback 포트는 관리자가 배정한다
health_path: /health
public: false                   # 외부 공개는 caddy-request.yaml 로 별도 승인
reason: <why>
# expires_at: <YYYY-MM-DD>      # (선택) 임시 서비스일 때만
```

`deploy/caddy-request.yaml` (외부 공개가 필요할 때만)

```yaml
# 필수(helper 검증): version request_id owner project hostname path upstream auth expires_at reason
version: "1"
request_id: <request-id>
owner: <member>
project: <project>
hostname: @@MCP_HOST@@
path: /member/<member>/<project>
upstream: http://127.0.0.1:<admin-assigned-port>
auth: bearer
quota: application-enforced   # (선택) helper 는 읽지 않음 · 관리자 검토용
expires_at: <YYYY-MM-DD>
reason: <canary or production reason>
```

`@@PFX@@-caddy-request validate deploy/caddy-request.yaml`이 실제로 확인하는 규칙(placeholder를 실제 값으로 바꾼 뒤에 통과한다):

- 위 필수 10개 필드가 모두 있고 비어 있지 않다. `quota` 같은 다른 필드는 검사하지 않는다.
- `request_id`·`owner`는 영문·숫자·`_`·`-`만 쓴다.
- `path`는 `/member/<owner>/`로 시작한다. 이 명령은 `/member/<owner>/` 경로 전용이다. 관리자 전용 공개 경로는 이 요청서로 만들 수 없다.
- `upstream`은 `http://127.0.0.1:<숫자 포트>` 또는 `https://127.0.0.1:<숫자 포트>` 형식이다. 경로·`localhost`·다른 주소는 거부된다.
- `expires_at`은 `YYYY-MM-DD`이고 오늘보다 뒤 날짜다.
- 모든 값(`reason` 포함)에 `token`·`secret`·`password`·`private key`(대소문자 무관) 같은 단어를 쓰지 않는다.

MCP라면 `mcp/README.md`에 transport, tool 목록, 인증, 입력·출력 예시, 오류 응답을 적는다. RAG라면 `rag/README.md`에 원천 데이터 위치, ingestion, schema, index/rebuild, freshness와 삭제 정책을 적는다.

## 관리자에게 부탁할 일 (`REQUEST/`)

host loopback 포트 배정, 도메인·경로 공개, DB, 권한처럼 관리자에게 부탁할 일이 있을 때만 프로젝트 루트에 `REQUEST/` 폴더를 둔다. 부탁할 일이 없는 프로젝트(내부 작업만, 컨테이너만 등)에는 필요 없다.

- `REQUEST/README.md`에 요청 목록을 한 줄씩 적고 상태를 표시한다(대기·전달됨·적용됨·거절).
- 요청 1건당 문서 1개 `REQUEST/YYYY-MM-DD-<주제>.md`를 만든다.
- 요청은 관리자에게 별도 메시지로도 전달한다. 메시지에는 `REQUEST/` 문서 경로만 알린다. 폴더가 알림을 대신하지 않는다.
- 요청 문서에는 secret·키·토큰·비밀번호·`.env` 값을 쓰지 않는다(DB 비밀번호도 쓰지 않는다).
- host loopback 포트 배정은 «포트 배정 요청»으로 적는다. 멤버는 container port만 제시하고(`loopback_port: admin-assigned`), 관리자가 배정한 포트는 같은 문서에 기록된다.
- 기계가 읽는 요청서(`deploy/service-request.yaml`·`deploy/caddy-request.yaml`)는 `deploy/`에 그대로 둔다. `@@PFX@@-caddy-request validate|submit`은 그 파일 경로를 직접 받는다.
- 서비스 등록이 필요 없는 공개(Caddy 공개만)는 `deploy/caddy-request.yaml`과 `REQUEST/` 문서를 낸다. `deploy/service-request.yaml`은 서비스 등록이 필요할 때만 만든다.
- 예전처럼 프로젝트 루트에 `REQUEST-*.md`를 쓰던 경우에도 새 요청부터 `REQUEST/`에 쓴다. 기존 문서는 편할 때 옮겨도 되고, 삭제하지 않아도 된다.

`REQUEST/README.md`

```markdown
| 날짜 | 요청 문서 | 요약 | 상태 |
|---|---|---|---|
| <YYYY-MM-DD> | `<YYYY-MM-DD>-<주제>.md` | <한 줄 요약> | 대기 |
```

`REQUEST/YYYY-MM-DD-<주제>.md`

```markdown
# <요청 제목>

- 상태: 대기
- 무엇을 요청하나: <한 문장>
- 왜(목적): <한 문장>
- 필요한 것: <해당하는 항목만 — 포트 배정 요청(container port <값>) · 도메인/경로 · DB · 권한 …>
- 만료 또는 삭제 기준: <날짜 또는 조건>
- 관련 파일: <deploy/service-request.yaml · deploy/caddy-request.yaml 등 경로>

## 관리자 답변

- <YYYY-MM-DD>: <답변 · 배정된 포트>
```

## 실행 명령

승인된 프로젝트 helper만 사용한다.

```bash
@@PFX@@-project-build <user> <project>
@@PFX@@-project-up <user> <project>
@@PFX@@-project-status <user> <project>
@@PFX@@-project-logs <user> <project>
@@PFX@@-project-down <user> <project>
```

실행 전 `compose.member.yml`과 문서의 diff를 확인하고, 실행 결과·이미지·포트·health 상태를 `OPERATIONS.md`에 기록한다.

## PostgreSQL

자기 회원 role과 승인된 자기 DB만 사용한다(`@@PFX@@-app db status|dsn|schema|backup|psql`로 확인·백업, 멤버 DB는 서버 백업에 포함되지 않는다). 새 멤버는 계정 생성 때 DB(`<member>_db`)가 자동 발급된다(기존 멤버는 관리자가 한 번). DB는 멤버당 하나이므로 앱마다 `@@PFX@@-app db schema <app>` 으로 스키마를 나누고 앱 설정에 `DB_SCHEMA=<app>`(또는 `search_path`)를 준다. 중앙 DB나 다른 회원 DB를 조회·변경하지 않는다. DB 비밀번호는 `.env`를 포함해 어떤 파일(compose·코드·문서·git)과 로그에도 저장하지 않고, `~/.pgpass`(`chmod 600`)만 쓴다.

## 웹 공개 (관리자 요청 없음)

- 파일 위치: 정적 공개 파일은 `/workspace/<project>/publish/`, 서버 앱 소스·가상환경은 `/workspace/<project>/app/`(앱이 여럿이면 `app/<앱이름>/`, 가상환경은 `app/.venv`), 비밀·개인정보는 `/workspace/<project>/.private/`(폴더 700·파일 600, git 제외)에 둔다. `publish/` 는 정적 페이지 전용이며 서버 앱은 쓰지 않는다. 공용 프로젝트의 비밀은 `/shared` 에 두지 않고 앱을 공개하는 멤버의 개인 `.private/` 에 둔다. 도구로 새로 만든 프로젝트에는 `.private/` 가 미리 들어 있고 다른 멤버는 접근하지 못한다(직접 만든 폴더에는 없을 수 있다. 관리자의 프로젝트 폴더 접근은 도구를 고치는 0.5.4 전까지 제한될 수 있다).
- 정적 웹페이지: 프로젝트의 `publish/` 폴더에 HTML 등을 두면 `https://<member>.@@DOMAIN@@/<project>/` 로 공개된다(한국 IP 전용, 파일 수정은 즉시 반영·새 프로젝트 폴더나 `publish/` 교체는 최대 1분). 공용 프로젝트는 `/shared/workspaces/<project>/publish/` → `https://@@PORTAL_HOST@@/<project>/` 로 공개된다(자동 규칙·사후 표시: 소문자 이름·예약어 아님·링크 아님·소유자가 현재 멤버·최대 10개). `@@PFX@@-site check <project>` 로 점검하고 `@@PFX@@-site off <project>` 로 중지한다. `publish/` 폴더를 만들거나 안에 쓰기 전에 무엇이 공개되는지 사용자에게 보여 주고 확인을 받는다.
- 서버 앱(Django·Flask·FastAPI·Node 등): 컨테이너 안에서 `0.0.0.0:<내 포트>` 로 실행하고 `@@PFX@@-app publish <app> <port> [--dir <앱 폴더>] [--basic] [--start "<명령>"]` 로 요청하면 1분 안에 `https://<app>.@@DOMAIN@@` 로 공개된다(규칙 자동 검사, 한국 IP 전용). `@@PFX@@-app ports` · `@@PFX@@-app status` · `@@PFX@@-app renew` · `@@PFX@@-app off`(멤버당 앱 최대 5개, 기본 30일·`--days N` 최대 365일, 요청 본문 10MB, 오래 운영할 서비스는 관리자에게 «운영 앱» 지정 요청), 시작 골격은 `@@PFX@@-app template django|fastapi|node [폴더]`(폴더를 생략하면 현재 프로젝트의 `app/`).
- 공개하기 전에 무엇이 공개되는지(로그인 없음 여부 포함)를 사용자에게 알리고 확인을 받는다. 비밀 파일·디버그 모드·로그인 없는 관리자 화면·개인정보는 공개하지 않는다.

## 외부 공개 요청

위 «웹 공개»로 되지 않는 공개(사용자 지정 주소·상시 서비스·API/MCP 등)는 반드시 관리자 요청·검토·승인이 필요하다. 멤버는 `validate`·`submit`까지만 수행하며, `plan`·`--apply`와 Caddy reload는 관리자만 수행한다.

외부 공개가 필요하면 Caddy를 직접 수정하지 않는다. `deploy/caddy-request.yaml`에 request_id, owner, project, hostname, path, 관리자 지정 loopback upstream, 인증 방식, 만료일, 사유를 기록하고(quota 정책은 선택) 관리자에게 제출한다. health 경로는 `deploy/service-request.yaml`의 `health_path`에 적는다. 요청 내용은 `REQUEST/` 문서에도 적고, 관리자에게는 그 문서 경로를 알린다.

REST는 `@@API_HOST@@`, MCP는 `@@MCP_HOST@@` 경계를 사용한다. route가 승인되기 전에는 내부 loopback에서만 검증한다.

## 중단 기준

권한 부족, 허용 범위를 벗어난 secret 발견, 다른 회원 데이터 접근 필요, host 설정 변경 필요, 자원 요구량이 불명확한 경우 작업을 멈추고 누락 사항과 선택지를 문서에 기록한 뒤 관리자에게 요청한다.
