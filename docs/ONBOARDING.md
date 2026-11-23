# 회원 안내 전달 가이드

> 회원을 등록하면 **초기 비밀번호 + Paseo 페어링(QR·링크)** 을 회원에게 전달해야 합니다. 이 문서는 «어떤 경로로 전달할지»(**전달 채널**)를 정하는 방법입니다.
>
> 채널은 `site.env` 의 `ONBOARD_CHANNELS` 에 공백으로 나열합니다. **설정이 없으면 예전과 똑같이 동작**합니다(`MAIL_MODE` 에서 유도).
>
> SMTP 메일 상세는 [메일 가이드](MAIL.md), n8n 으로 보내는 방식은 [n8n 가이드](N8N.md)를 보세요.

---

## 채널 비교

| 채널 | 무엇을 | 누가 받나 | 비밀이 지나가는 곳 |
|---|---|---|---|
| `screen` | 회원 등록 화면에 비밀번호 표시 | 관리자(직접 전달) | 관리자 터미널(로그 파일에는 남지 않음) |
| `smtp` | 안내 메일 | 회원 | 메일 서버·메일함 |
| `n8n` | n8n 워크플로로 안내 메일 | 회원 | n8n·메일 서버 |
| `link` | **1회 열람 링크**를 만들어 화면에 표시 | 관리자가 링크를 전달 | 링크를 전달한 경로(링크만) |
| `webhook` | Slack·Discord·Telegram·일반 JSON 알림 | 관리자 채널 | **비밀번호·QR 은 싣지 않음**(기본은 ID·생성 사실만. 링크는 `ONBOARD_WEBHOOK_INCLUDE_LINK=1` 일 때만) |
| `print` | 출력용 한 장 안내문 파일 | 관리자가 인쇄해 전달 | 종이(대면 전달) |

- 채널은 **적은 순서대로** 시도하고, **한 채널이 실패해도 다음을 계속**합니다. 어떤 채널이 실패해도 **회원 등록은 이미 끝나 있습니다.**
- `screen` 은 목록 어디에 쓰든(없어도) **비밀을 전달한 다른 채널이 하나도 성공하지 못했을 때 마지막 보루로** 실행됩니다. `webhook` 은 비밀을 싣지 않으므로 «전달 성공» 으로 치지 않습니다.
- `smtp` 와 `n8n` 은 둘 다 메일 방식이라 같이 쓸 수 없습니다.

## 설정 예

```bash
# /etc/<접두어>/site.env  (설치 설정 파일 --config 와 같은 변수 이름)
ONBOARD_CHANNELS="smtp link webhook"      # 메일 + 1회 열람 링크 + 알림
ONBOARD_LINK_TTL_HOURS=24                 # 링크 유효 시간(1~168, 기본 24)
ONBOARD_LINK_PORT=8431                    # 127.0.0.1 포트(기본 8431)
MAIL_LINK_ONLY=0                          # 1: 메일에 비밀번호·QR 대신 링크만(smtp + link)
ONBOARD_WEBHOOK_FORMAT=slack              # generic | slack | discord | telegram
ONBOARD_WEBHOOK_INCLUDE_LINK=0            # 1: 알림에 1회 열람 링크도 싣기(기본 0 — 아래 webhook 절의 경고 참고)
ONBOARD_WEBHOOK_URL_FILE=/etc/<접두어>/secrets/onboard-webhook-url
```

| 하고 싶은 것 | 설정 |
|---|---|
| 기본(변경 없음) | `ONBOARD_CHANNELS` 없음 또는 `screen` |
| 메일로만 | `smtp` (→ [메일 가이드](MAIL.md)) |
| 메일 + 안전하게 링크로 | `smtp link` + `MAIL_LINK_ONLY=1` |
| 메신저로 «알림»만 | `link webhook`(알림에는 ID·생성 사실만, 링크는 관리자가 따로 전달) |
| 대면 전달 | `print` |

설치 뒤 바꾸려면 `site.env` 를 고치고 `sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/<접두어>/site.env --yes --only 50,52,53` 을 실행합니다(`link` 를 처음 켜면 Caddy 연결 때문에 50 이 필요). 웹 설치 화면에서는 «고급 설정» 의 체크박스로 고르고, 메일은 «SMTP» 만 있습니다.
점검: `sudo <접두어>-onboard-deliver --check` · `sudo <접두어>-doctor`.

---

## 1회 열람 링크 (`link`)

회원 등록 때 링크가 화면에 한 번 출력됩니다. 관리자가 이 링크를 회원에게 전달합니다. 형식: `https://<도메인>/start/<토큰>`.

1. 회원이 링크를 열면 **확인 화면**(«한 번만 보입니다. 열기»)만 나옵니다. **이 단계에서는 링크가 소비되지 않습니다** — 메신저·메일 보안 검사기가 링크를 먼저 열어도 링크가 죽지 않습니다.
2. «열기»(POST, 1회용 폼 토큰 포함)를 누르면 초기 비밀번호·접속 방법·Paseo QR·링크가 **한 번** 나오고 링크는 폐기됩니다. 새로 고침하면 다시 볼 수 없습니다.
3. 24시간(`ONBOARD_LINK_TTL_HOURS`)이 지나면 열리지 않습니다. 안내 문구는 «이미 열린 링크» · «기간이 지난 링크» · «다시 열어 주세요»(확인 화면이 오래된 경우 — 링크는 아직 사용되지 않음)로 구분됩니다(서비스를 재시작하면 «이미 열림/기간 지남» 구분은 일반 문구로 돌아갑니다).
4. 첫 로그인에서 비밀번호를 바꾸게 하는 동작은 그대로입니다. 웹 서비스는 **계정을 바꾸지 않고 읽기만** 합니다.

관리자 명령:

| 명령 | 동작 |
|---|---|
| `sudo <접두어>-member-link issue <ID> [--ttl-hours N]` | 재발급(이전 링크는 폐기). 토큰 원문은 **이때 한 번만** 출력됩니다 |
| `sudo <접두어>-member-link revoke <ID>` | 폐기 |
| `sudo <접두어>-member-link status [<ID>]` | 남은 링크·남은 시간(토큰은 보여 주지 않음) |
| `sudo <접두어>-member-link --check` | 서비스 기동·응답 헤더 점검 |

**재발급 정책:** 초기 비밀번호 파일(`/run/<접두어>/member-secrets/<ID>.password`)이 있고 비밀번호가 아직 첫 로그인 변경 전일 때만 만듭니다. 봉인(`onboarding-seal`)했거나 서버를 재부팅했거나 회원이 이미 비밀번호를 바꿨으면 **재발급을 거부**하고 이유를 안내합니다(옛 비밀번호 링크를 만들지 않기 위해). 이 경우 새 비밀번호는 관리자가 초기화해 직접 전달해야 합니다.

**자동 정리:** `link` 만 성공했으면 링크 유효 시간 + 1분 뒤 봉인이 자동 실행됩니다(재발급하면 옛 예약은 멈추고 새 예약이 고유 이름으로 잡힙니다). `link` 를 끄고 53 단계를 다시 실행하면 서비스를 멈추고 남은 링크 기록도 지웁니다. 봉인하면 링크도 폐기되고 초기 비밀번호 파일·`print.html` 도 지워집니다. `screen`·`print` 를 쓴 경우에는 관리자가 전달 뒤 `sudo <접두어>-onboarding-seal <ID>` 를 실행합니다. 회원을 삭제하면 링크도 폐기됩니다.

### 구조

- 서비스 `<접두어>-link.service`: 표준 라이브러리만 쓰는 파이썬 서비스. 전용 시스템 사용자 `<접두어>-link`, `127.0.0.1` 에서만 listen, systemd 하드닝(`NoNewPrivileges`·`ProtectSystem=strict`·시스템콜 필터 등).
- 저장소 `/run/<접두어>-link/`(메모리, 0700): 파일 하나 = 링크 하나, 이름은 **토큰의 sha256**, 내용은 만료 시각과 안내 내용(초기 비밀번호·접속 정보·QR). 재부팅하면 사라지고 백업에 들어가지 않습니다.
- Caddy: 메인 도메인 사이트 블록이 `/etc/caddy/<접두어>-link.caddy` 를 import 하고, 설치기(53 단계)가 이 조각에 `/start/*` → `127.0.0.1:<포트>` 프록시를 씁니다. 요청 본문은 2KB 로 제한되고, `/start/*` 는 접근 로그를 남기지 않으며(`log_skip`), 접근 로그·기본(오류) 로그 모두 `/start/` 뒤 경로를 지우는 필터(`(?i)(/+start/)[^?]*|\?.*`)가 걸려 있어 업스트림 오류 때 토큰이 Caddy 로그에 남는 것도 막습니다. 전역 `servers { timeouts { read_header 10s } }` 로 헤더 읽기를 제한합니다(`read_body` 는 SFTPGo 같은 큰 업로드를 끊으므로 두지 않았습니다. 느린 본문은 링크 서비스의 총 시간 제한이 끊습니다).
- 클라이언트 IP: Caddy 가 전용 헤더 `X-Onboard-Client-IP` 에 접속자 IP 를 덮어쓰고(`X-Forwarded-For` 는 지움), 서비스는 127.0.0.1 에서 온 요청의 이 헤더만 읽습니다(없거나 형식이 틀리면 연결 상대 주소). 접속자가 `X-Forwarded-For`·전용 헤더를 위조해도 IP 제한을 피할 수 없습니다.

### 보안 모델

| 방어 | 내용 |
|---|---|
| 토큰 | 256비트 urlsafe. 서버에는 sha256 해시만 저장(원문은 발급 화면 한 번뿐) |
| 소비 | POST 로만. GET 은 읽기 전용 확인 화면. 폼 토큰은 1회용·10분·링크당 최대 8개(미리보기 봇이 먼저 열어도 사람의 폼이 살아 있음) |
| 원자성 | 소비는 파일 이름 바꾸기(rename)로 해 동시 요청 중 하나만 내용을 받음 |
| 실패 제한 | IP 별 15분에 10번 실패하면 차단(429). IP 는 Caddy 가 덮어쓰는 전용 헤더 `X-Onboard-Client-IP`(서비스는 127.0.0.1 에서 온 요청의 이 헤더만 신뢰) |
| 일치 | 해시·폼 토큰은 상수 시간 비교. 실패 응답은 «없음·사용함·만료» 를 구분하지 않음 |
| 로그 | 서비스·Caddy 모두 토큰 원문을 기록하지 않음(서비스는 해시 앞 8자만) |
| 응답 | `Cache-Control: no-store` · `Referrer-Policy: no-referrer` · `X-Robots-Tag: noindex` · CSP(`default-src 'none'`, 이미지는 `data:` 만, 스타일은 nonce) · `X-Frame-Options: DENY` · JS 없음 |
| 입력 | 경로는 정확히 `/start/<토큰>` 만(`//start/…`·끝 슬래시·대문자 변형·절대형 요청줄은 404)·GET/POST 만·본문 1KB 이하·모든 비교는 바이트 단위(비ASCII 입력도 400) |
| 자원 | 요청 하나는 총 15초 안에 끝나지 않으면 연결을 끊음(slowloris)·동시 연결 64개 초과는 즉시 503·예외는 트레이스백 없이 형식만 로그 |
| 프로세스 | 전용 계정·`IPAddressDeny=any`+`IPAddressAllow=localhost`(루프백 외 통신 차단)·`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`·시스템콜 필터·메모리 128MB 상한 |
| 파일 | 온보딩 폴더 `0750 root:<접두어>`(그룹 쓰기 없음), 페어링 파일 기본 `0600 root:root`. 도구는 폴더를 `lstat`(심볼릭 링크 아님·root 소유·쓰기 권한 없음), 파일을 `O_NOFOLLOW` 로 열어 `fstat`(일반 파일·root 소유)으로 확인하고, 아니면 거부합니다 |
| 비밀의 명령줄·환경변수 | 비밀번호·링크·토큰·webhook 주소는 명령줄과 환경변수에 넣지 않습니다. 모두 파일(0600)·표준 입출력·프로세스 내부로만 다룹니다(메일 링크는 `--link-file` 임시 파일) |

### 위협 모델과 알려진 한계

- **링크는 전달받은 사람이 곧 열람자입니다.** 링크가 새면(메신저 기록·메일 전달 등) 먼저 연 사람이 비밀번호를 봅니다. 회원이 열었는데 «이미 사용됨» 이면 **누군가 먼저 연 것**이니 관리자에게 알리고, 관리자는 비밀번호를 초기화하세요.
- `webhook` 에 링크를 싣는 것(`ONBOARD_WEBHOOK_INCLUDE_LINK=1`)은 초기 비밀번호와 같은 가치의 자격증명을 그 채널 구성원 전원(과 채널 기록·외부 서비스)에게 주는 일입니다. 그래서 기본은 꺼져 있고, 켜면 `--check`·`--test-webhook` 이 경고합니다.
- **초기 비밀번호는 12자**(헷갈리는 문자 제외 영문 대소문자·숫자, 약 70비트)입니다. 첫 로그인 전까지 SSH 비밀번호 인증이 열려 있어 6자(약 35비트)는 짧다는 검토 결과로 올렸습니다. 복사·붙여넣기로 전달하는 것이 기본이라 입력 부담은 작습니다.
- 안내 내용(초기 비밀번호·QR)은 링크 유효 시간 동안 `/run`(메모리 파일시스템) 에 평문으로 있습니다. 서버 root 는 읽을 수 있습니다. 토큰으로 암호화하는 방식은 넣지 않았습니다.
- 실패 제한은 서비스 메모리에 있어 서비스를 재시작하면 초기화되고, 접속 IP 를 바꿔 가며 시도하는 공격은 막지 못합니다(256비트 토큰이라 추측은 현실적이지 않음). 접속 IP 수가 1만을 넘으면 오래된 기록부터 버립니다.
- HTTPS 종단은 Caddy 입니다. `TLS_MODE=internal` 이면 회원 브라우저에 인증서 경고가 뜹니다.
- Caddy 설정(전역 옵션·`log_skip`·로그 필터·`/start/*` 프록시)은 Caddy 2.11.9 의 `caddy adapt --validate` 로 **문법만** 확인했습니다. 실제 요청을 통과시켜 본 동작(로그에 토큰이 안 남는지, `//start/` 처리, 헤더 덮어쓰기)과 `IPAddressDeny` 의 실행 중 효과는 **확인 못 함**입니다. 설치 뒤 `sudo <접두어>-doctor` 와 `sudo grep -c /start/ /var/log/caddy/access.log`(0 이어야 함), `journalctl -u caddy | grep -c /start/` 로 확인하세요.

---

## webhook

비밀번호·페어링 링크·QR 은 **절대 싣지 않습니다.** 기본으로 보내는 것은 회원 ID · «계정이 만들어졌다» · «관리자에게 안내를 받으세요» 뿐입니다(회원 이메일도 싣지 않음). `ONBOARD_WEBHOOK_INCLUDE_LINK=1`(+`link` 채널)이면 1회 열람 링크도 싣습니다 — 위험은 위 «위협 모델» 을 읽고 비공개·소수 채널에서만 켜세요.

| 형식 | `ONBOARD_WEBHOOK_FORMAT` | 주소·비밀 | 본문 |
|---|---|---|---|
| 일반 JSON | `generic` | `ONBOARD_WEBHOOK_URL_FILE` | `{"event":"member.created","member":…,"brand":…,"message":…,"time":…}` (+ `link_url`: INCLUDE_LINK=1 일 때만) |
| Slack | `slack` | Incoming Webhook 주소 | `{"text": …}` |
| Discord | `discord` | 채널 웹훅 주소 | `{"content": …}` |
| Telegram | `telegram` | `ONBOARD_WEBHOOK_TELEGRAM_FILE`(두 줄: `TELEGRAM_BOT_TOKEN=…` · `TELEGRAM_CHAT_ID=…`) | `sendMessage`(`chat_id`·`text`) |

- 주소·토큰은 설정 파일이 아니라 **`/etc/<접두어>/secrets/` 의 root 전용(0600) 파일**에만 둡니다. 도구는 이 폴더 밖의 파일이나 권한이 넓은 파일을 거부합니다. 설치 때 `ONBOARD_WEBHOOK_URL`(값) 또는 `ONBOARD_WEBHOOK_URL_FILE`(원본 파일)로 주면 설치기가 옮겨 둡니다.
- **https 만 허용**합니다. 내부 시험용 http 는 `ONBOARD_WEBHOOK_ALLOW_HTTP=1` 로 명시해야 합니다(권장하지 않음). 리다이렉트는 따라가지 않습니다. 오류 메시지·로그에는 주소·토큰을 남기지 않습니다(HTTP 상태만).
- 시험: `sudo <접두어>-onboard-deliver --test-webhook`(회원 ID `test-member`, 비밀 없음).
- 각 서비스의 웹훅 발급 방법·조건은 해당 서비스 문서를 확인하세요(이 문서에서는 확인하지 않았습니다).

## print

`/srv/<접두어>/onboarding/<ID>/print.html` 에 **한 장짜리 안내문**(회원 ID · 초기 비밀번호 · 접속 방법 · Paseo QR)을 만듭니다. 대면 전달용입니다.

- 파일은 `O_EXCL|O_NOFOLLOW` 로 새로 만들고 기본 `0600 root:root` 입니다. 관리자 계정의 «개인 그룹»(그룹 이름 = 사용자 이름이고 구성원이 그 사용자뿐이며 다른 사용자의 기본 그룹도 아닌 경우)일 때만 그 그룹에 읽기(0640)를 열어 줍니다 — 아니면 `sudo` 로 열어 인쇄합니다. 인쇄 설정은 A4 기준입니다.
- 전달한 뒤 `sudo <접두어>-onboarding-seal <ID>` 로 지웁니다(`print.html` 포함). 자동으로 지워지지 않습니다.

## 온보딩 폴더 권한과 n8n

- 설치기(20 단계)는 `/srv/<접두어>/onboarding` 을 `0750 root:<접두어>` 로 만듭니다(그룹 쓰기·setgid 없음). 회원이 같은 그룹이라 쓰기 권한이 있으면 심볼릭 링크 등을 심어 root 도구가 엉뚱한 파일을 읽거나 쓰게 할 수 있기 때문입니다. 다른 디렉터리의 2775 는 그대로입니다.
- 전달 도구는 회원별 페어링 파일(`pairing-url.txt`·`pairing.json`·`pairing.png`)을 시작할 때 `0600 root:root` 로 조입니다. **예외: `n8n` 채널을 쓸 때만** `0640 root:<접두어>` 를 유지합니다. 근거: n8n 컨테이너가 `/srv/<접두어>/onboarding` 을 읽기 전용으로 마운트하고(`compose/n8n/compose.yml`), `group_add` 로 `<접두어>` 그룹 gid 를 받아 워크플로 `member-onboarding` 의 «파일 읽기» 노드가 `…/onboarding/<ID>/pairing-url.txt`·`pairing.png` 를 그룹 권한으로 읽기 때문입니다.

## 점검과 문제 해결

| 증상 | 확인 |
|---|---|
| 링크가 «열 수 없는 링크» | 이미 열렸거나 24시간이 지났거나 서버가 재부팅됨 → `member-link issue`(조건은 위 재발급 정책) |
| 링크 서비스가 안 뜸 | `journalctl -u <접두어>-link` · `sudo <접두어>-member-link --check` · 포트 충돌이면 `ONBOARD_LINK_PORT` 변경 |
| 공개 주소에서 404/연결 안 됨 | `sudo <접두어>-doctor` 의 `/start/*` 항목 · Caddyfile 에 `<접두어>-link.caddy` import 가 없으면 50 단계 다시 실행(첫 설치 후 업데이트한 서버) |
| webhook 이 안 감 | `--check`(주소 형식·파일 권한) → `--test-webhook`. 회원 등록 로그에 상태 코드만 남습니다 |
| 메일이 비밀번호 대신 링크로 안 감 | `MAIL_LINK_ONLY=1` 은 `smtp` 와 `link` 가 둘 다 필요. 링크 발급이 실패하면 메일은 보내지 않고 화면 표시로 대신합니다 |
