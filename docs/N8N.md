# n8n 사용 가이드

> n8n 은 **선택 서비스**입니다. 쓰지 않아도 데브마루의 회원 등록 · 개발환경 · 웹 공개는 모두 동작합니다.
>
> 쓰기로 했다면 «빈 n8n»만 설치되고, 자주 쓰는 워크플로는 **템플릿으로 골라서** 가져올 수 있습니다.
>
> 가져온 워크플로는 항상 **비활성**입니다. 자격증명(메일·텔레그램 등)을 직접 고른 뒤 켭니다.

---

## 사용 / 비사용 선택

| 선택 | 설정 | 결과 |
|---|---|---|
| **n8n 을 쓰지 않음** | 설치할 때 `n8n` 서비스를 선택하지 않음 | n8n 컨테이너·`n8n.<도메인>` 이 만들어지지 않습니다.<br>회원 등록 안내 메일은 SMTP 직접<br>발송을 쓰거나 화면 전달로 대신합니다 |
| **n8n 만 설치** (기본) | `n8n` 선택 + `N8N_WORKFLOWS=none` | 빈 n8n 이 올라옵니다.<br>워크플로·자격증명은 관리자가 직접 만듭니다 |
| **n8n + 범용 템플릿** | `n8n` 선택 + `N8N_WORKFLOWS=generic` | 설치 때 범용 템플릿 2종을<br>**비활성**으로 가져옵니다 |

- 터미널 설치에서는 설정 파일에 `N8N_WORKFLOWS=generic` 을 쓰고, 웹 화면에서는 **고급 설정 → n8n 워크플로 템플릿**에서 고릅니다.
- 설치 뒤에도 언제든 가져올 수 있습니다: `sudo <접두어>-n8n-workflows install --all`

---

## 제공하는 템플릿

| 이름 | 용도 | 웹훅 | 필요한 것 |
|---|---|---|---|
| `member-onboarding` | 회원을 등록하면 **안내 메일**(초기 비밀번호 ·<br>Paseo 링크와 QR)을 보냅니다.<br>선택으로 n8n 초대 링크도 넣습니다 | `/webhook/<접두어>-member-onboarding` | SMTP 자격증명 · (선택) n8n API 키 |
| `ops-notify` | 앱 만료 · 공개 종료 같은 **운영<br>알림**을 텔레그램으로 보냅니다 | `/webhook/<접두어>-ops-notify` | Telegram API 자격증명 · 채팅 ID |

> **메일만 필요하다면 n8n 이 필요 없습니다.** `member-onboarding` 은 «메일을 n8n 으로 보내고 싶을 때(`MAIL_MODE=n8n`)»의 선택지입니다. 기본은 서버가 SMTP 로 직접 보냅니다. 자세한 내용은 [메일 가이드](MAIL.md)를 보세요.
>
> **메일 노드는 Gmail 노드(OAuth)가 아니라 «SMTP 자격증명»(Send Email 노드)을 쓰세요.** 템플릿 `member-onboarding` 은 SMTP 자격증명을 고르도록 되어 있습니다. Gmail 로 보내려면 Gmail 의 SMTP 주소와 앱 비밀번호를 SMTP 자격증명에 넣는 방식입니다(조건·한도는 [메일 가이드](MAIL.md)의 Gmail 항목). 전달 채널 전체는 [회원 안내 전달 가이드](ONBOARDING.md).

---

## 가져오기와 켜기

### 1. 목록 확인 · 가져오기

```bash
sudo <접두어>-n8n-workflows list                      # 템플릿과 가져옴 여부
sudo <접두어>-n8n-workflows install --all             # 전부 가져오기 (비활성)
sudo <접두어>-n8n-workflows install ops-notify        # 하나만
sudo <접두어>-n8n-workflows install ops-notify --force    # 이미 있어도 덮어쓰기(화면에서 고친 내용이 사라집니다)
```

- 이미 가져온 것은 **건너뜁니다**(여러 번 실행해도 안전).
- 웹훅 토큰은 가져올 때 서버의 토큰 파일 값으로 채워집니다. 저장소의 템플릿에는 토큰이 없습니다.
  - 메일: `/etc/<접두어>/secrets/onboarding-notify-token`
  - 운영 알림: `/etc/<접두어>/apps/notify.token` (가져오면 `app-sync` 의 알림 설정이 자동으로 연결됩니다)
- n8n 이 꺼져 있으면 안내하고 끝납니다.

### 2. n8n 첫 접속 — 소유자 계정 만들기

`https://n8n.<도메인>/` 을 **관리자가 먼저** 열어 소유자(owner) 계정을 만드세요. 처음 여는 사람이 소유자가 됩니다.

> **암호화 키를 백업하세요.** n8n 에 저장한 자격증명은 `/opt/<접두어>/config/env/n8n.env` 의 `N8N_ENCRYPTION_KEY` 로 암호화됩니다. 잃으면 자격증명을 복원할 수 없습니다.

### 3. 자격증명 고르기

n8n 화면에서 가져온 워크플로를 열고, 아래 표의 노드에서 자격증명을 고릅니다. 각 워크플로 맨 위의 **노란 메모(설명)** 에도 같은 내용이 적혀 있습니다.

| 워크플로 | 노드 | 해야 할 일 |
|---|---|---|
| member-onboarding | `메일 보내기` | **SMTP 자격증명**을 만들어 선택 (Credentials → New → SMTP) |
| member-onboarding | `n8n 초대 만들기` | (선택) n8n API 키(Header Auth, `X-N8N-API-KEY`).<br>쓰지 않으면 이 노드를 비활성화. **실패해도 메일은 나갑니다** |
| ops-notify | `텔레그램 보내기` | **Telegram API 자격증명**(BotFather 봇 토큰)<br>선택 + **Chat ID** 를 받을 채팅 ID 로 바꾸기 |

> 텔레그램 대신 Slack · 메일 등을 쓰려면 `텔레그램 보내기` 노드를 해당 노드로 바꾸면 됩니다. 앞의 `토큰 확인` 노드는 그대로 두세요.

### 4. 활성화

화면 오른쪽 위의 **Publish(활성화)** 를 누르거나, 서버에서:

```bash
sudo <접두어>-n8n-workflows activate member-onboarding
sudo <접두어>-n8n-workflows deactivate member-onboarding
```

- 활성 상태를 바꾸면 **n8n 이 한 번 다시 시작**됩니다(약 15초).
- `activate` 는 웹훅이 실제로 등록된 것까지 확인한 뒤 끝납니다.
- 자격증명을 고르지 않고 켜면 알림이 와도 마지막 노드에서 «자격증명이 없다»는 오류로 실행이 실패합니다.

### 5. 내 수정 내용 보관

화면에서 고친 워크플로를 파일로 저장해 두려면:

```bash
sudo <접두어>-n8n-workflows export ops-notify ./ops-notify.backup.json     # 파일 권한 600
```

자격증명 값은 들어 있지 않지만 **웹훅 토큰이 들어 있을 수 있으니** 공개하지 마세요.

---

## 보안 메모

- **웹훅 경로는 외부에서 막혀 있습니다.** `n8n.<도메인>` 이 공개되어 있어도 Caddy 가 `/webhook/<접두어>-member-onboarding*` 와 `/webhook/<접두어>-ops-notify*` 를 404 로 돌려보냅니다. 호출은 서버 안(`127.0.0.1:5678`)에서만 됩니다.
- **토큰도 한 번 더 확인합니다.** 헤더(`X-Onboarding-Token` · `X-Token`)가 맞을 때만 동작하고, 틀리면 아무 일도 하지 않습니다(호출한 쪽에는 200 이 돌아가도 메일·알림은 나가지 않습니다).
- **실행 기록에 비밀번호를 남기지 않도록** 템플릿은 성공한 실행 데이터를 저장하지 않게 설정되어 있습니다. 화면에서 이 설정을 바꾸면 초기 비밀번호가 기록에 남을 수 있습니다.
- 템플릿에서 **파일을 읽는 경로**는 `/srv/<접두어>/onboarding` 뿐이며, n8n 컨테이너는 이 폴더를 **읽기 전용**으로만 봅니다.

---

## 문제 해결

| 증상 | 확인 |
|---|---|
| `install` 이 «n8n 컨테이너가 실행 중이 아닙니다» | `docker ps \| grep n8n` — n8n 서비스를 선택해 설치했는지, 떠 있는지 확인 |
| 활성화했는데 웹훅이 404 | n8n 을 다시 시작한 직후(약 10초)에는 등록 전일 수 있습니다. `activate` 명령은 등록을 기다려 줍니다 |
| 메일이 안 감 | `메일 보내기` 노드의 SMTP 자격증명, 서버의 SMTP 접근(방화벽·포트 25/465/587), n8n 로그 `docker logs n8n --tail 50` |
| 운영 알림이 안 옴 | `텔레그램 보내기` 의 자격증명 · Chat ID, `/etc/<접두어>/apps/config.json` 의 `notify_url` · `notify_token_file` |
| `doctor` 가 «템플릿이 일부 없음» | `sudo <접두어>-n8n-workflows install --all` |

> 설치는 [설치 가이드](INSTALL.md), 일상 운영은 [운영 가이드](OPERATIONS.md), 메일 설정은 [메일 가이드](MAIL.md)를 보세요.
