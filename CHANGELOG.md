# 📝 변경 내역

> 데브마루의 버전별 변경 내역입니다. 최신 버전이 위에 있습니다.
>
> 업데이트할 때 `sudo <접두어>-update` 가 **현재 버전 이후의 변경 내역을 먼저 보여 주고**, 확인한 뒤에 적용합니다.
>
> 변경 내역만 보려면 `sudo <접두어>-update --check` 를 쓰세요(아무것도 바꾸지 않습니다).

---

## 1.4.4 — 2026-11-24 — 연결 파일에 공용 폴더(선택) 추가

### ✨ 새로 생긴 것

- `smb-connect.bat` 이 **내 폴더와 함께 공용 폴더(`shared`)도 연결**할 수 있습니다. 두 번째 드라이브 문자를 입력하면 공용 폴더가 연결되고, **그냥 Enter 를 누르면 건너뜁니다.** 같은 문자를 두 번 쓰면 안내하고 중단합니다. 비밀번호는 한 번만 묻습니다. 시험(`kit/tests/smb_bat_test.sh`)에 공용 연결 줄·선택 건너뛰기·두 줄 모두 QUIC 옵션 확인을 추가했습니다. 실제 Windows 에서 공용 연결과 «Enter 로 건너뛰기» 동작은 **확인 중**입니다.
- 1.4.3 의 연결 파일로 만든 드라이브가 **재부팅 뒤에도 보이는 것**을 Windows 11 PC 1대에서 확인했습니다(비밀번호를 다시 묻지 않는지는 별도로 확인하지 않았습니다).

---

## 1.4.3 — 2026-11-24 — Windows «연결 파일»(smb-connect.bat) 자동 생성

### ✨ 새로 생긴 것

- 🗄 **SMB 모듈이 `smb-connect.bat` 을 만들어 포털에 둡니다**(`https://<포털 주소>/smb-connect.bat`). 서버 이름과 QUIC 포트는 설치 설정에서 채우고 **비밀번호는 넣지 않습니다**. 회원은 파일을 내려받아 더블클릭하고 ID · 드라이브 문자 · 비밀번호만 입력하면 됩니다(PowerShell 명령을 입력할 필요 없음). 포털 Guide 의 네트워크 드라이브 절에 «연결 파일 받기» 링크가 생겼습니다.
- 시험: `kit/tests/smb_bat_test.sh`(생성 파일의 치환·CRLF·UTF-8·BOM 없음·QUIC 포트 반영·tcp 만 쓸 때·멱등). 실제 Windows 에서의 동작은 PC 1대에서 확인했습니다(연결·탐색기 표시). 이 파일로 만든 연결이 재부팅 뒤에도 유지되는지는 확인 중입니다.

### 🔧 바뀐 것

- 포털 Guide 의 네트워크 드라이브 절에 `cmdkey` 로 비밀번호를 저장하는 직접 명령 방식(1.4.2)을 반영했습니다(이전 설치의 Guide 는 옛 `-Credential` 예제였습니다).
- [SMB 가이드](docs/SMB.md) 에 «연결 파일 받기» 안내를 추가했습니다.

---

## 1.4.2 — 2026-11-24 — SMB 안내 문서: 재부팅해도 유지되는 Windows 연결

> 코드 변경 없이 [SMB 가이드](docs/SMB.md) 의 Windows 연결 방법만 고쳤습니다.

### 🔧 바뀐 것

- Windows 11 연결 절차를 **`cmdkey` 로 비밀번호를 한 번 저장한 뒤 `New-SmbMapping -Persistent $true`**(`-Credential` 없이)로 바꿨습니다. 이전 예(`-Credential $cred -Persistent $true`)는 연결은 되지만 비밀번호가 저장되지 않아 재부팅 때마다 다시 물었습니다.
- 알려진 오류와 대처를 적었습니다: `-SaveCredentials` 를 `-Persistent` 와 함께 쓰면 «매개 변수가 틀립니다» · 이미 쓰는 드라이브 문자 · 재부팅 직후 «연결 끊김» 표시 · 비밀번호를 바꾼 뒤 `cmdkey` 재등록.
- 확인한 범위를 적었습니다: 외부 Windows 11 PC 1대에서 연결과 재부팅 뒤 자동 재연결, 서버 쪽은 임시 Samba 서버와 Linux 클라이언트로 QUIC 접속·인증·읽기/쓰기. 다른 PC·Windows 빌드는 확인하지 못했습니다.

---

## 1.4.1 — 2026-11-23 — `onboarding-seal` 명령이 PATH 에 없던 문제

### 🐛 고친 것

- 문서(INSTALL·OPERATIONS)와 `member-add` 안내가 `sudo <접두어>-onboarding-seal <ID>` 로 쓰라고 하는데, 설치가 이 명령을 `/opt/<접두어>/scripts/` 에만 두어 **«command not found»** 가 났습니다. 이제 설치(20 단계)가 `/usr/local/sbin/<접두어>-onboarding-seal` 링크를 만듭니다. 1.4.0 을 쓰던 서버는 `sudo <접두어>-update` 뒤 링크가 생기고, 급하면 전체 경로(`/opt/<접두어>/scripts/<접두어>-onboarding-seal <ID>`)로 실행해도 됩니다.
- 가상 머신(LXD)에 새로 설치해 확인했습니다: 링크 열람(GET 은 소비하지 않음·POST 1회·재사용 거부), Caddy 로그에 토큰이 남지 않음, `//start/`·대문자·끝 슬래시 404, 링크 서비스는 127.0.0.1 만, 봉인 뒤 재발급 거부.

---

## 1.4.0 — 2026-11-23 — 회원 안내 «전달 채널» · 1회 열람 링크 · webhook · 출력용 안내문

> 회원 등록 때 초기 비밀번호·Paseo QR 을 전달하는 방식을 **채널 목록**(`ONBOARD_CHANNELS`)으로 일반화했습니다. **설정이 없으면 예전과 같이 동작**합니다(`MAIL_MODE` 에서 유도: none→화면 · smtp→메일 · n8n→n8n). 자세한 내용은 [docs/ONBOARDING.md](docs/ONBOARDING.md).

### ✨ 새로 생긴 것

- 🔗 **`link` 채널 — 1회 열람 링크.** 링크를 열면 확인 화면만 나오고(GET 은 소비하지 않음 — 메신저·메일 보안 검사기가 먼저 열어도 안전), «열기»(POST·1회용 폼 토큰)를 눌러야 초기 비밀번호·QR 이 **한 번** 보입니다. 24시간(`ONBOARD_LINK_TTL_HOURS`)·1회 후 폐기, 토큰은 256비트·서버에는 sha256 해시만, IP 별 실패 제한, 엄격한 응답 헤더·CSP. 표준 라이브러리 파이썬 서비스(`<접두어>-link`, 전용 계정·127.0.0.1·systemd 하드닝), Caddy 는 `/start/*` 로 프록시. 관리 명령 `<접두어>-member-link issue|revoke|status|--check`.
- 📣 **`webhook` 채널** — `generic`(JSON) · `slack` · `discord` · `telegram`. 비밀번호·QR·페어링 링크는 **싣지 않고**(회원 ID·생성 사실·링크 채널이 만든 1회 열람 링크만), https 만 허용, 주소·토큰은 `/etc/<접두어>/secrets/` 의 root 전용 파일.
- 🖨 **`print` 채널** — 온보딩 폴더에 한 장짜리 출력용 안내문(`print.html`). `onboarding-seal` 이 지웁니다.
- ✉ **`MAIL_LINK_ONLY=1`** — `smtp` + `link` 일 때 메일에 비밀번호·QR 대신 링크만 보냅니다.
- 🧰 새 명령 `<접두어>-onboard-deliver`(채널 순회·`--check`·`--test-webhook`), 설치 단계 `53`(전달 채널 준비), 웹 설치 화면 «고급 설정» 의 채널 체크박스, `doctor` 의 전달 채널 점검.

### 🔧 바뀐 것

- 회원 등록(`member-add`)이 채널 목록을 순서대로 시도하고, 한 채널이 실패해도 다음을 계속합니다. 비밀을 전달한 채널이 없으면 화면 표시가 마지막 보루입니다. 비밀(초기 비밀번호·링크)은 터미널로만 나가고 **회원 등록 로그 파일에는 남지 않습니다**.
- `onboarding-seal` 이 링크 폐기·초기 비밀번호 파일 삭제·`print.html` 삭제를 같이 하고, `member-remove` 가 링크를 폐기합니다.
- 웹 설치 화면의 메일 항목은 «SMTP» 만 두었습니다(n8n 으로 보내기는 «고급 설정»).
- Caddy 접근 로그가 `/start/` 뒤 경로(토큰)를 지웁니다.
- 문서: [ONBOARDING.md](docs/ONBOARDING.md) 신설, [MAIL.md](docs/MAIL.md) 에 Gmail 등 외부 SMTP 안내, [N8N.md](docs/N8N.md) 에 «SMTP 자격증명» 안내.

### 🔒 보안 보강 (독립 검토 반영)

- 온보딩 폴더를 `0750 root:<접두어>`(그룹 쓰기 없음)로 만들고, 페어링 파일은 기본 `0600 root:root`(n8n 채널만 그룹 읽기). 읽기·쓰기는 `lstat`/`O_NOFOLLOW`/`fstat`(일반 파일·root 소유)로 확인하고 `print.html` 은 `O_EXCL` 로 만든 뒤 `fchown`/`fchmod`.
- 메일 링크를 명령줄이 아니라 0600 임시 파일(`--link-file`)로 전달. 비밀을 명령줄·환경변수로 넘기는 호출이 없는지 전수 점검.
- 링크 서비스: 요청 총 시간 15초·동시 연결 64 상한(초과 503)·비ASCII 입력도 400(바이트 비교)·정확히 `/start/<토큰>` 만 허용·`X-Forwarded-For` 대신 Caddy 가 덮어쓰는 `X-Onboard-Client-IP` 만 신뢰·안내 문구 구분(이미 열림/기간 지남/다시 열어 주세요)·systemd `IPAddressDeny=any`.
- Caddy: `/start/*` 접근 로그 생략(`log_skip`)·로그 필터를 `(?i)(/+start/)[^?]*|\?.*` 로(기본 오류 로그에도 적용)·헤더 읽기 10초 제한.
- webhook 에 링크를 싣는 것은 `ONBOARD_WEBHOOK_INCLUDE_LINK=1`(기본 0)일 때만. `--secret-fd` 가 열려 있지 않으면 표준 출력으로 돌리지 않고 실패. 이메일·ID 검증은 `fullmatch` 와 ASCII 문자 집합.
- print.html 그룹 읽기는 관리자의 «개인 그룹»일 때만. link 를 끄면 남은 기록 삭제, 재발급 때 옛 봉인 예약 취소·새 예약.
- **초기 비밀번호 6자 → 12자**(회원 등록 패치). 첫 로그인 전까지 SSH 비밀번호 인증이 열려 있어 6자(약 35비트)는 짧다는 검토 결과입니다.

### ⚠ 알아 둘 것

- 기존 설치를 업데이트한 뒤 `link` 를 켜려면 Caddy 설정을 다시 만들어야 합니다: `sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/<접두어>/site.env --yes --only 50,53`.
- 이 버전의 새 채널은 실제 메일·메신저 발송, 실서버 설치, 공인 도메인 접근으로는 시험하지 못했습니다(자동 시험은 가짜 서버·가짜 root 기준).

---

## 1.3.0 — 2026-11-22 — 원격 관리(fleet) · 라이브 서버 이관 · GitHub 배포

> 이 버전부터 **GitHub 릴리스**에서 배포합니다(GitLab 저장소는 점검 중). 1.2.2 는 별도 릴리스 없이 이 버전에 포함됩니다.

### ✨ 새로 생긴 것

- 🟢 **`<접두어>-member-update-all --json`** — `--check` 결과를 JSON 으로(`result` READY/BLOCKED/REVIEW · `image` · `summary` 집계). **회원 ID 는 넣지 않으며**, `--json --members` 일 때만 회원별 행(ID 포함)을 냅니다. 종료 코드: 0 READY · 2 BLOCKED(작업 중인 회원이 있음) · 3 REVIEW(개발 컨테이너가 없는 회원) · 1 오류. 기존 `--check` 의 출력·종료 코드는 그대로입니다(BUSY 여도 0).
- 🔒 **공통 정비 락 `/run/<접두어>-maintenance.lock`** — 서버 전체에서 **상태를 바꾸는 정비 작업이 한 번에 하나만** 돌게 합니다: `update` 적용 · `service-update --apply` · `restore apply` · `member-update-all`(적용) · `golden-rc` · `backup-run`. 다른 정비가 실행 중이면 안내를 내고 **종료 코드 75** 로 끝납니다. `--check`·`--plan` 같은 읽기 전용 명령은 락 때문에 막히지 않습니다. 하위 명령은 재진입을 허용합니다(`<접두어>-maint-lib.sh`). 상태는 `sudo <접두어>-maintenance status [--json]`(idle/busy, 읽기 전용).
- 🙈 **마스킹 규칙 공유** — `support-bundle` 의 비밀 마스킹을 `<접두어>-mask-lib.sh` 로 옮겼고, 같은 규칙을 파이프로 쓰는 `<접두어>-mask` 명령을 추가했습니다(`--selftest` 포함). 규칙은 한 곳에서만 고칩니다.
- 🛡 **`agent` 모듈 허용 목록에 읽기 전용 점검 추가** — `golden check` · `member-update-all --check|--json` · `service-update --all --plan|--check` · `maintenance status [--json]`. 인자가 한 칸이라도 다르면 허용되지 않습니다(`member-update-all` 인자 없음, `--json --members`, `--apply`, `golden rc|promote` 등은 거부).

- 🛰 **`devmaru-fleet` 1단계(읽기 전용 원격 점검)** — 관리자 PC 에서 여러 서버를 SSH 로 점검하는 단일 파일 도구(`tools/devmaru-fleet`, Python 표준 라이브러리만): `status`(상태·회원 READY/BUSY 집계·정비 락·킷 버전) · `check`(갱신 가능 여부) · `watch --once`(직전과 비교해 달라진 것만) · `trust`(호스트 키 지문 확인 후 등록) · `doctor`(관리자 PC 점검) · `list` · `log`. 서버에는 아무것도 설치하지 않고 **읽기 전용 명령만** 실행하며(`agent` 모듈의 제한 sudo), 회원 ID·비밀·개인키는 다루지 않습니다. 사용법은 `docs/FLEET.md`.

- 🚀 **`devmaru-fleet` 2단계(원격 설치)** — `verify-release`(sha256 + 서명 `ssh-keygen -Y verify`, 서명 없으면 `--allow-unsigned` 필요) · `install plan`(서버에는 업로드한 파일 외 아무것도 설치하지 않고, 읽기 점검과 원격 `devmaru-install --plan` 만) · `install apply`(서버 이름 직접 입력, `systemd-run` 분리 실행 — 연결이 끊겨도 서버에서 계속) · `install status [--follow]` · `install resume`(재부팅·강제 중지·실패 뒤 이어서). 설치 설정에 비밀 키가 있으면 거부합니다. 발행자용 `sign-release.sh` 추가.
- 🔄 **`devmaru-fleet` 3단계(갱신)** — `update plan|apply|status`(서명 검증 → 서버별 가드 → canary 먼저 → 서버 이름 확인 → 분리 실행 → 킷 버전·doctor 확인, 실패하면 이후 서버 중단, `--rolling N`) · `members plan|apply|status`(작업 중인 회원·컨테이너 없는 회원이 있으면 거부). 다운그레이드·정비 중·Golden 재빌드 디스크 부족은 거부합니다.
- 🌐 **배포처 선택 `DEVMARU_SOURCE=github|gitlab`(기본 github)** — 설치 스크립트(`install.sh`)와 `<접두어>-update` 가 최신 릴리스를 GitHub 에서 찾습니다. 예전 방식(`DEVMARU_BASE` · `DEVMARU_API` · 인자로 준 주소)은 그대로 동작하고, 조회에 실패하면 설치 때 쓴 주소로 되돌아갑니다. ⚠️ GitLab 에서 설치한 서버도 이 버전부터 기본 조회처가 GitHub 로 바뀝니다(되돌리려면 `DEVMARU_SOURCE=gitlab`).
- 🚚 **라이브 서버 이관 애드온 `tools/devmaru-migrate-live`** — 수백 GB 서버를 두 서버가 켜진 채 옮기는 관리자 셸 도구 묶음과 플레이북(`docs/MIGRATE-LIVE.md`). 설정 파일 기반 rsync 그룹 전송(시험 실행 기본·`--seed`·`--final --stopped`·이름 기준 uid/gid 보정) · 정지 확인(루트리스 도커·상주 프로세스·`postmaster.pid`) · 최종 동기화와 «일치» 표 · 회원 계정·해시(지문만 표시) · 도커 이미지 전송과 ID 대조(config 해시 보조) · `docker run` 컨테이너 export · 구/신 서버 목록 비교(누락 헬퍼·드롭인·링크·NIC 고정 방화벽) · netplan IP 교체(콘솔 `netplan try` / 원격 자동 원복 타이머). 기존 `<접두어>-migrate`(암호화 묶음)와는 용도가 다릅니다. 가짜 ssh·rsync·docker 로 분기 시험만 했고 이 판 자체는 실서버에서 실행하지 않았습니다.

### ✅ 확인한 것 (Ubuntu 26.04 VM)
`--json` 의 READY/BLOCKED/오류 종료 코드와 기존 `--check` 호환 · 락 점유 중 `member-update-all`·`service-update`·`golden-rc`·`update --force` 가 75 로 막히고 읽기 전용 명령은 통과 · 재진입 · 락 해제 뒤 정상 동작 · `support-bundle` 번들에 강한 비밀 패턴 0건 · 에이전트 계정으로 허용 7개 통과·거부 8개 거부.
`devmaru-fleet`: 단위 시험 47개(가짜 ssh·실제 `ssh-keygen` 서명) + 별도 리허설 서버에서 실제 VM 으로 — 서명 릴리스 검증 · `trust` · `install plan`(서버에 업로드한 파일 외 변화 없음) · `install apply`(클라이언트를 강제 종료해도 서버 설치 계속, `status --follow` 로 다시 붙어 완료, doctor pass) · 서버 설치 유닛 강제 중지 뒤 `install resume`(5단계부터 이어서 완료) · 이미 설치된 서버는 거부. 3단계(update·members)는 실제 VM 에서 서명한 새 킷으로 — `update plan`(서버 무변화) · `update apply`(canary, 단계 진행 표시, 킷 버전·doctor pass 확인) · 다운그레이드·같은 버전(--force 없이)·정비 락 중 거부(묻기 전에 막음) · `--force` 재적용. 확인하지 못한 것: 서버 여러 대 `--rolling`(단위 시험만), Golden 재빌드가 필요한 갱신의 원격 실행, `members apply` 실서버 실행.
⚠️ `restore apply`·`backup-run` 의 락은 이 VM 에 backup 모듈이 없어 동작까지는 못 보고 문법·훅 위치만 확인했습니다.

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
