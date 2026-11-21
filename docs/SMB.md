# 🗄 SMB 네트워크 드라이브 가이드 (SMB over QUIC)

> 회원이 **Windows 탐색기에서 개인 작업공간과 공용 폴더를 드라이브처럼** 쓰게 합니다.
>
> 연결은 **SMB over QUIC**(UDP)로 하며, 기본 설정은 **TCP 445 를 열지 않습니다.**
>
> 선택 모듈 `smb` 입니다. 켜면 `files` 도 같이 설치됩니다.

> ⚠️ **먼저 알아 둘 것**
>
> - 이 모듈은 리눅스 **커널 QUIC 모듈을 설치 서버에서 직접 빌드**(DKMS)합니다.
> - 설치기는 DKMS 빌드와 Samba 서비스 구성까지 시험했습니다. 그러나 **실제 Windows 11 클라이언트로 QUIC 접속하는 시험은 하지 못했습니다.** 연결 명령은 운영 서버에서 확인된 방법을 그대로 적었습니다.
> - **Secure Boot 가 켜진 서버**에서는 DKMS 서명 키를 한 번 등록해야 합니다(아래 «Secure Boot» 절).

---

## 🧭 한눈에

| | |
|---|---|
| 🖥 **서버** | Samba 4.23 + 커널 QUIC 모듈(DKMS) — 서비스 이름 `<접두어>-samba-quic` |
| 🌐 **주소** | `smb.<도메인>` (DNS A 레코드 필요) |
| 📡 **포트** | 기본 **UDP 1443** (QUIC) — 방화벽에서 열어야 합니다 |
| 📁 **공유** | `\\smb.<도메인>\<ID>` 개인 폴더 · `\\smb.<도메인>\shared` 공용 폴더 |
| 🔑 **계정** | 회원 ID · 비밀번호는 SSH 비밀번호와 같고 바꾸면 같이 바뀝니다 |
| 💻 **클라이언트** | **Windows 11 24H2 이상** (Windows 10 에는 SMB over QUIC 클라이언트가 없습니다) |

---

## 🚀 설치

### 1️⃣ 준비

- `smb.<도메인>` 의 DNS A 레코드가 서버를 가리켜야 합니다(와일드카드 `*.<도메인>` 이면 이미 됩니다).
- 방화벽/공유기에서 **UDP 1443** 을 서버로 열어 줍니다. (기본 설정은 TCP 445 를 쓰지 않습니다)
- 인증서를 공인으로 받으려면 **80 포트**도 열려 있어야 합니다(Let's Encrypt 확인용).

### 2️⃣ 모듈 선택

- 터미널/웹 설치에서 **smb** 를 선택합니다(`files` 는 자동으로 같이 켜집니다).
- 설정 파일이라면 `MODULES="… files smb"`.

| 설정 키 | 뜻 | 기본 |
|---|---|---|
| `SMB_TRANSPORTS` | 서버가 열 전송 방식. 예: `quic:1443` · `tcp:445,quic:1443` | `quic:1443` |
| `TLS_MODE` | `internal` 이면 자체 서명 인증서, 아니면 Let's Encrypt | `acme` |

> 🔓 `tcp:445` 를 추가하면 같은 내부망의 PC 가 일반 SMB 로도 붙을 수 있지만, **445 를 인터넷에 열지 마세요.** QUIC 만 쓰는 것이 안전합니다.

### 3️⃣ 설치 단계가 하는 일 (56단계)

1. Samba · DKMS · 커널 헤더 설치, 배포판 기본 smbd/nmbd 는 끔
2. QUIC 커널 모듈 빌드·적재 (상류 `lxin/quic` 소스를 **커밋 고정**으로 받아 호환 패치 적용)
3. `/srv/<접두어>/samba/smb.conf` 생성 — SMB 3.1.1 · 서명 필수 · 게스트 금지
4. 인증서 준비 — 공인: certbot(Caddy 의 80 포트 챌린지) · 내부: 자체 서명
5. `<접두어>-samba-quic` 서비스 시작과 포트 확인

회원을 등록하면 Samba 계정이 **같이 만들어집니다**(`<접두어>-member-add`).

---

## 🪟 Windows 11 에서 연결하기

PowerShell 에서 계정 정보를 준비합니다. 비밀번호는 **SSH 비밀번호와 같습니다.**

```powershell
$cred = Get-Credential -UserName '<ID>'
```

내 개인 폴더를 `X:` 로 연결합니다.

```powershell
New-SmbMapping `
  -LocalPath 'X:' `
  -RemotePath '\\smb.<도메인>\<ID>' `
  -TransportType QUIC `
  -QuicPort 1443 `
  -Credential $cred `
  -Persistent $true
```

공용 폴더를 `Y:` 로 연결합니다.

```powershell
New-SmbMapping `
  -LocalPath 'Y:' `
  -RemotePath '\\smb.<도메인>\shared' `
  -TransportType QUIC `
  -QuicPort 1443 `
  -Credential $cred `
  -Persistent $true
```

연결 끊기: `Remove-SmbMapping -LocalPath 'X:' -Force`

> 💡 명령은 성공했는데 탐색기 «내 PC» 에 안 보이면 탐색기를 다시 시작하세요: `taskkill /f /im explorer.exe` → `start explorer.exe`

### 🔐 자체 서명 인증서를 쓰는 경우 (`TLS_MODE=internal`)

Windows 가 인증서를 신뢰하지 않으면 연결이 거부됩니다. 서버의 `/srv/<접두어>/samba/tls/cert.pem` 을 PC 로 가져와 **«신뢰할 수 있는 루트 인증 기관»** 에 등록하세요. 공인 도메인을 쓰는 설치(Let's Encrypt)에서는 필요 없습니다.

---

## 🔒 Secure Boot 가 켜져 있다면

Secure Boot 서버는 **서명되지 않은 커널 모듈을 적재하지 않습니다.** 설치 중 «Secure Boot 가 켜져 있어 … 적재하지 못했습니다» 경고가 나오면 DKMS 가 만든 서명 키를 한 번 등록합니다.

1. `sudo mokutil --import /var/lib/dkms/mok.pub` — 비밀번호를 정합니다.
2. 서버를 **재부팅**합니다. 부팅 중 파란 «MOK management» 화면이 나오면 **Enroll MOK → Continue → Yes** 를 고르고 방금 정한 비밀번호를 입력한 뒤 재부팅합니다(서버 콘솔/IPMI 접근이 필요합니다).
3. 다시 56단계를 실행합니다.
   ```bash
   sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/<접두어>/site.env --yes --only 56
   ```

> 🧪 가상 머신(LXD 등)에서 시험할 때 Secure Boot 를 끌 수 없으면 `SMB_TRANSPORTS=tcp:445` 로 Samba 서비스·계정 부분만 점검할 수 있습니다.

커널을 업데이트하면 DKMS 가 새 커널용 모듈을 **자동으로 다시 빌드**합니다(`AUTOINSTALL`). 커널 헤더 패키지(`linux-headers-generic`)가 설치되어 있어야 합니다.

---

## 🩺 문제 해결

| 증상 | 확인 |
|---|---|
| 설치에서 `QUIC 모듈 빌드 실패` | 로그 `/tmp/<접두어>-quic-build.log`. 매우 새 커널이면 상류 소스와 맞지 않을 수 있습니다 — 커널 버전과 함께 알려 주세요 |
| `modprobe quic 실패` + Secure Boot | 위 «Secure Boot» 절 |
| 서비스가 시작되지 않음 | `journalctl -u <접두어>-samba-quic -n 30`, `testparm -s /srv/<접두어>/samba/smb.conf` |
| 인증서 발급 경고 | `smb.<도메인>` DNS 와 80 포트 확인 후 56단계 재실행. 그동안 서비스는 시작되지 않습니다 |
| 포트 확인 | `ss -lun | grep 1443` (QUIC) · `ss -ltn | grep 445` (tcp 를 켠 경우) |
| Windows 에서 접속 거부 | UDP 1443 방화벽, DNS, 자체 서명이면 인증서 신뢰 등록, Windows 11 **24H2 이상**인지 |
| 회사망에서 막힘 | UDP 1443 이 차단된 망일 수 있습니다. 브라우저용 **Files**(SFTPGo)를 쓰세요 |

서버 쪽 확인 명령:

```bash
sudo <접두어>-doctor                      # SMB 서비스·quic 모듈 점검 포함
sudo pdbedit -L -s /srv/<접두어>/samba/smb.conf      # Samba 계정 목록
```

---

## 🛡 보안 메모

- 기본은 **QUIC 만** 엽니다(TCP 445 비개방). SMB 서명 필수, 최소 프로토콜 SMB 3.1.1, 게스트 접근 금지.
- 개인 공유는 본인만, 공용(`shared`)은 `<접두어>` 그룹 회원만 접근합니다.
- 인증서·키는 `/srv/<접두어>/samba/tls`(root 만 읽음)에 있고, 공인 인증서는 갱신될 때마다 자동 배포·서비스 재시작됩니다.
- 이 기능이 쓰는 QUIC 커널 모듈은 **GPL-2.0-or-later**(상류 `lxin/quic`)이며 저장소에 포함하지 않고 설치할 때 받습니다. 호환 패치 파일(`ubuntu-abi38.patch`)만 이 저장소에 있습니다.
