# 메일 자동 발송 가이드

> 회원을 등록하면 **초기 비밀번호 · 첫 로그인 안내 · Paseo QR** 을 회원 메일로 보냅니다.
>
> 기본은 서버가 **SMTP 로 직접** 보내며 **n8n 이 필요 없습니다.**
>
> 메일을 쓰지 않으면 회원 등록 화면에 초기 비밀번호가 표시되고 관리자가 직접 전달합니다.
>
> n8n 워크플로로 보내는 방식(`MAIL_MODE=n8n`)도 지원합니다.
>
> 메일 말고 **1회 열람 링크 · webhook · 출력용 안내문** 으로 전달하려면 [회원 안내 전달 가이드](ONBOARDING.md)를 보세요(이 문서는 SMTP 상세).

---

## 세 가지 방식

| 방식 | 설정 | 동작 |
|---|---|---|
| **none** (기본) | `MAIL_MODE=none` 또는 mail 모듈을 고르지 않음 | 메일을 보내지 않습니다. 회원 등록 화면에 초기 비밀번호와 온보딩 파일 위치가 표시됩니다 |
| **smtp** (권장) | mail 모듈 선택 (`MAIL_MODE=smtp`) | 서버의 `<접두어>-notify-mail` 이 SMTP 서버로 직접 보냅니다. **n8n 이 없어도 됩니다** |
| **n8n** | `MAIL_MODE=n8n` | n8n 이 같이 설치되고 `member-onboarding` 워크플로 템플릿을 가져옵니다. SMTP 자격증명은 설치 뒤 n8n 화면에서 고릅니다 → [n8n 가이드](N8N.md) |

> 어떤 방식이든 **발송에 실패하면 회원 등록은 그대로 완료**되고, 화면에 초기 비밀번호가 표시되어 관리자가 직접 전달할 수 있습니다.

---

## 설정

### 1. 터미널 설치에서

설치 질문 중 «메일 발송 방식»에서 `smtp` 를 고르면 SMTP 서버 · 포트 · 암호화 · 계정 · 보내는 주소를 묻고, 비밀번호는 **화면에 표시되지 않게** 입력받습니다.

### 2. 웹 설치 화면에서

«설치할 서비스»에서 **mail** 을 체크하면 «메일 자동 발송 설정» 카드가 나타납니다. 비밀번호 칸은 `password` 입력이며 설정 파일에는 쓰이지 않습니다.

### 3. 설정 파일(`--config`)에서

```bash
MODULES="postgres caddy golden portal files mail"
MAIL_MODE=smtp
MAIL_SMTP_HOST=smtp.example.org
MAIL_SMTP_PORT=587
MAIL_SMTP_SECURITY=starttls
MAIL_SMTP_USER=noreply@example.org
MAIL_FROM=noreply@example.org
# 비밀번호는 설정 파일에 쓰지 말고 파일이나 환경변수로 전달합니다
#   MAIL_SMTP_PASSWORD_FILE=/root/smtp-password.txt      (파일 내용 = 비밀번호 한 줄)
#   MAIL_SMTP_PASSWORD='…'  sudo -E devmaru-install …    (환경변수)
```

| 키 | 뜻 | 기본 |
|---|---|---|
| `MAIL_MODE` | `none` · `smtp` · `n8n` | mail 모듈을 고르면 `smtp` |
| `MAIL_SMTP_HOST` | SMTP 서버 주소 | (필수) |
| `MAIL_SMTP_PORT` | 포트 | `587` |
| `MAIL_SMTP_SECURITY` | `starttls` · `ssl`(465) · `none`(내부 릴레이) | `starttls` |
| `MAIL_SMTP_USER` | 로그인 계정 (인증이 없으면 비움) | 비움 |
| `MAIL_FROM` | 보내는 사람 주소 | (필수) |
| `MAIL_SMTP_VERIFY` | `0` 이면 서버 인증서를 검증하지 않음(사설 인증서 릴레이용) | `1` |
| `MAIL_TEST_SEND` | `0` 이면 설치 때 관리자에게 시험 메일을 보내지 않음 | `1` |

> 이 설정은 `/etc/<접두어>/site.env` 에 기록되지만 **비밀번호는 기록되지 않습니다.** 비밀번호는 `/etc/<접두어>/secrets/smtp.env`(root 만 읽음, 권한 600)에만 있습니다.

---

## SMTP 설정 예

| 상황 | 설정 |
|---|---|
| **사내 메일 릴레이**(인증 없음) | `HOST=relay.example.org` `PORT=25` `SECURITY=none` — 같은 내부망에서만 쓰세요 |
| **STARTTLS** (가장 흔함) | `PORT=587` `SECURITY=starttls` + 계정·비밀번호 |
| **SSL/TLS** | `PORT=465` `SECURITY=ssl` + 계정·비밀번호 |
| **외부 메일 서비스** | 서비스가 알려 준 SMTP 주소·포트·«앱 비밀번호»(또는 API 키)를 씁니다. 보내는 주소는 서비스에서 인증한 주소여야 합니다 |

### Gmail · Google Workspace 로 보내기

Google 공식 문서(확인일 2026-11-23)에서 확인한 내용입니다. **서비스 조건은 바뀔 수 있으니 설정 전에 아래 공식 문서를 다시 확인하세요.**

| 항목 | 내용 |
|---|---|
| 서버·포트 | `smtp.gmail.com` · `465`(SSL) 또는 `587`(TLS) → `SECURITY=ssl` · `starttls` |
| 인증 | 필요 — 전체 이메일 주소 + **앱 비밀번호**(Workspace 안내 기준) |
| 앱 비밀번호 | 계정에 **2단계 인증이 켜져 있어야** 만들 수 있고(`myaccount.google.com/apppasswords`, 16자리), 보안 키만 쓰는 2단계 인증 · 직장·학교 등 조직 계정 · 고급 보호 사용 계정에서는 옵션이 안 보일 수 있습니다 |
| 일일 한도 | Workspace 유료 계정 사용자당 2,000통/일(24시간 롤링), 체험 계정 500통. 한도는 예고 없이 바뀔 수 있음 |
| 일반(무료) Gmail 한도 | **확인 못 함**(확인한 공식 문서가 Workspace 만 다룸) |
| SMTP 릴레이 | Workspace 는 `smtp-relay.gmail.com`(IP 인증)도 있음 — 이 킷은 계정 인증 방식만 시험했고 릴레이는 **확인 못 함** |

주의: 같은 공식 문서에 «**2025-05-01 부터 Google Workspace 계정은 아이디·비밀번호로 로그인하라는 기기를 더 이상 지원하지 않고 OAuth 를 써야 한다**» 는 안내가 있어 앱 비밀번호 방식과 충돌해 보입니다. 이 킷의 직접 발송(`<접두어>-notify-mail`)은 **아이디·비밀번호(앱 비밀번호) 방식만** 지원하며 OAuth 는 지원하지 않습니다. Workspace 계정에서 인증이 거부되면 관리자 정책을 확인하거나 SMTP 릴레이·다른 메일 서비스를 쓰세요(실제 Gmail 발송은 이 킷에서 **시험하지 못했습니다**).

공식 문서: [앱 비밀번호](https://support.google.com/mail/answer/185833) · [Workspace SMTP 설정 안내](https://support.google.com/a/answer/176600) · [Workspace 발송 한도](https://support.google.com/a/answer/166852)

> `SECURITY=none` 은 메일 서버로 가는 구간이 **암호화되지 않습니다.** 초기 비밀번호가 평문으로 지나가므로 같은 서버·내부망 릴레이가 아니면 쓰지 마세요.

---

## 회원이 받는 메일

| 항목 | 내용 |
|---|---|
| 제목 | `[<서비스 이름>] 개발환경 계정이 만들어졌습니다` |
| 본문 | 회원 ID · **초기 비밀번호**(첫 로그인 때 바꿔야 함) ·<br>첫 로그인 방법(SSH 주소) · 안내 페이지 링크 · Paseo 연결 설명 |
| 첨부 | `pairing.png` — Paseo 앱에서 스캔하는 QR |

발송에 성공하면 기존처럼 **15분 뒤 온보딩 임시 파일이 자동 삭제**됩니다(`<접두어>-onboarding-seal`).

---

## 시험 · 관리

```bash
sudo <접두어>-notify-mail --check               # SMTP 연결·인증만 확인(메일은 보내지 않음)
sudo <접두어>-notify-mail --test me@example.org  # 시험 메일 1통
sudo <접두어>-doctor                             # 메일 설정 점검 포함
```

설정을 바꿀 때는 `/etc/<접두어>/site.env` 의 `MAIL_*` 값을 고치고 **메일 단계만** 다시 실행합니다.

```bash
sudo MAIL_SMTP_PASSWORD='새 비밀번호' python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/<접두어>/site.env --yes --only 52
```

비밀번호를 바꾸지 않으면 `MAIL_SMTP_PASSWORD` 없이 실행해도 기존 값이 유지됩니다.

---

## 보안 메모

- 비밀번호는 `/etc/<접두어>/secrets/smtp.env`(0600)에만 저장합니다. 설정 파일 · 명령줄 · 로그에는 남지 않습니다.
- 회원의 초기 비밀번호는 **파일로만** 발송 도구에 전달되고, 오류 메시지에서도 가려집니다.
- 메일 본문에 초기 비밀번호가 들어갑니다. 회원은 첫 로그인 때 바로 바꿔야 하며, 메일은 지우는 것이 좋습니다.
- 첨부된 Paseo QR 은 **영구 자격증명**처럼 다뤄야 합니다. 다른 사람에게 전달하지 마세요.
- 메일에 비밀번호를 싣기 싫으면 `link` 채널과 `MAIL_LINK_ONLY=1` 로 «비밀번호 대신 1회 열람 링크» 를 보낼 수 있습니다 → [ONBOARDING.md](ONBOARDING.md). 이 경우 QR 도 첨부하지 않습니다.

---

## 문제 해결

| 증상 | 확인 |
|---|---|
| 설치 때 «SMTP 연결 시험 실패» | 주소·포트·암호화·계정을 확인한 뒤 위의 «메일 단계만 다시 실행». 그동안 회원 등록은 화면 전달 안내로 동작합니다 |
| 인증 실패(535 등) | 계정·비밀번호(앱 비밀번호 필요 여부)를 확인하세요. 비밀번호에 특수문자가 있어도 파일/환경변수로 전달하면 안전합니다 |
| 인증서 오류 | 사설 인증서 릴레이면 `MAIL_SMTP_VERIFY=0` (같은 내부망에서만) |
| 메일이 안 옴 | `sudo <접두어>-notify-mail --test <주소>` 로 시험하고, 보내는 주소(`MAIL_FROM`)가 서비스에서 허용된 주소인지 · 스팸함을 확인하세요 |
| 어디서 로그를 보나요 | 회원 등록 로그 `/srv/<접두어>/logs/member-add/<ID>-*.log` (비밀번호는 없습니다) |
