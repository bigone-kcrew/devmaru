# SMB 네트워크 드라이브 가이드 (SMB over QUIC)

> 회원이 **Windows 탐색기에서 개인 작업공간과 공용 폴더를 드라이브처럼** 쓰게 합니다.
>
> 연결은 **SMB over QUIC**(UDP)로 하며, 기본 설정은 **TCP 445 를 열지 않습니다.**
>
> 선택 모듈 `smb` 입니다. 켜면 `files` 도 같이 설치됩니다.

> **먼저 알아 둘 것**
>
> - 이 모듈은 리눅스 **커널 QUIC 모듈을 설치 서버에서 직접 빌드**(DKMS)합니다.
> - 설치기는 DKMS 빌드와 Samba 서비스 구성까지 시험했습니다. 서버 쪽은 임시 Samba 서버와 Linux 클라이언트로 QUIC 접속·인증·읽기/쓰기까지 시험했고, **Windows 11 PC 1대에서 연결과 재부팅 뒤 자동 재연결을 확인했습니다.** 다른 PC·Windows 빌드는 확인하지 못했습니다.
> - **Secure Boot 가 켜진 서버**에서는 DKMS 서명 키를 한 번 등록해야 합니다(아래 «Secure Boot» 절).

---

## 한눈에

| | |
|---|---|
| **서버** | Samba 4.23 + 커널 QUIC 모듈(DKMS) — 서비스 이름 `<접두어>-samba-quic` |
| **주소** | `smb.<도메인>` (DNS A 레코드 필요) |
| **포트** | 기본 **UDP 1443** (QUIC) — 방화벽에서 열어야 합니다 |
| **공유** | `\\smb.<도메인>\<ID>` 개인 폴더 · `\\smb.<도메인>\shared` 공용 폴더 |
| **계정** | 회원 ID · 비밀번호는 SSH 비밀번호와 같고 바꾸면 같이 바뀝니다 |
| **클라이언트** | **Windows 11 24H2 이상** (Windows 10 에는 SMB over QUIC 클라이언트가 없습니다) |

---

## 설치

### 1. 준비

- `smb.<도메인>` 의 DNS A 레코드가 서버를 가리켜야 합니다(와일드카드 `*.<도메인>` 이면 이미 됩니다).
- 방화벽/공유기에서 **UDP 1443** 을 서버로 열어 줍니다. (기본 설정은 TCP 445 를 쓰지 않습니다)
- 인증서를 공인으로 받으려면 **80 포트**도 열려 있어야 합니다(Let's Encrypt 확인용).

### 2. 모듈 선택

- 터미널/웹 설치에서 **smb** 를 선택합니다(`files` 는 자동으로 같이 켜집니다).
- 설정 파일이라면 `MODULES="… files smb"`.

| 설정 키 | 뜻 | 기본 |
|---|---|---|
| `SMB_TRANSPORTS` | 서버가 열 전송 방식. 예: `quic:1443` · `tcp:445,quic:1443` | `quic:1443` |
| `TLS_MODE` | `internal` 이면 자체 서명 인증서, 아니면 Let's Encrypt | `acme` |

> `tcp:445` 를 추가하면 같은 내부망의 PC 가 일반 SMB 로도 붙을 수 있지만, **445 를 인터넷에 열지 마세요.** QUIC 만 쓰는 것이 안전합니다.

### 3. 설치 단계가 하는 일 (56단계)

1. Samba · DKMS · 커널 헤더 설치, 배포판 기본 smbd/nmbd 는 끔
2. QUIC 커널 모듈 빌드·적재 (상류 `lxin/quic` 소스를 **커밋 고정**으로 받아 호환 패치 적용)
3. `/srv/<접두어>/samba/smb.conf` 생성 — SMB 3.1.1 · 서명 필수 · 게스트 금지
4. 인증서 준비 — 공인: certbot(Caddy 의 80 포트 챌린지) · 내부: 자체 서명
5. `<접두어>-samba-quic` 서비스 시작과 포트 확인

회원을 등록하면 Samba 계정이 **같이 만들어집니다**(`<접두어>-member-add`).

---

## Windows 11 에서 연결하기

### 가장 쉬운 방법 — 연결 파일(배치 파일) 받기

SMB 모듈을 설치하면 설치기가 `smb-connect.bat` 을 만들어 포털에 둡니다(서버 이름·포트가 이미 채워져 있고 **비밀번호는 들어 있지 않습니다**). 회원은 포털 Guide 의 «Windows 네트워크 드라이브» 절에서 **«연결 파일 받기»** 를 눌러 내려받아 더블클릭합니다.

1. 회원 ID 를 입력합니다.
2. 쓰지 않는 드라이브 문자(예: `L`)를 입력합니다.
3. 비밀번호(SSH 비밀번호) 입력창에 비밀번호를 입력합니다 — Windows 자격 증명 관리자에 저장되어 재부팅 뒤에도 다시 묻지 않도록 합니다.

파일 위치는 서버의 `/srv/<접두어>/public/portal/smb-connect.bat`(주소 `https://<포털 주소>/smb-connect.bat`)이고, 56 단계를 다시 실행하면 다시 만들어집니다. 내려받은 `.bat` 에는 Windows 가 경고를 띄울 수 있고, 내용은 메모장으로 열어 확인할 수 있습니다. 이 파일은 메일 첨부로 보내지 마세요 — Gmail 등은 `.bat` 첨부를 막습니다.

> **확인한 범위:** 이 파일이 만드는 `net use` 연결이 탐색기에 바로 보이는 것은 Windows 11 PC 1대에서 확인했습니다. 재부팅 뒤 자동 재연결은 아래 «직접 명령» 방식(`New-SmbMapping`)으로 확인한 것이고, 이 파일로 만든 연결의 재부팅 뒤 동작은 **확인 중**입니다.

### 직접 명령으로 하려면

일반(비관리자) PowerShell 에서 합니다. 비밀번호는 **SSH 비밀번호와 같습니다.**

**1. 비밀번호를 한 번 저장합니다.** 입력창이 뜨고, 저장해 두면 **재부팅해도 다시 묻지 않습니다.**

```powershell
cmdkey /add:smb.<도메인> /user:<ID> /pass
```

**2. 내 개인 폴더를 연결합니다.** 이미 쓰는 드라이브 문자라면 다른 문자(예: `L:`)로 바꾸세요.

```powershell
New-SmbMapping `
  -LocalPath 'X:' `
  -RemotePath '\\smb.<도메인>\<ID>' `
  -TransportType QUIC `
  -QuicPort 1443 `
  -Persistent $true
```

**3. (선택) 공용 폴더를 연결합니다.**

```powershell
New-SmbMapping `
  -LocalPath 'Y:' `
  -RemotePath '\\smb.<도메인>\shared' `
  -TransportType QUIC `
  -QuicPort 1443 `
  -Persistent $true
```

연결 끊기: `Remove-SmbMapping -LocalPath 'X:' -Force`

> **확인한 범위:** 외부 Windows 11 PC 1대에서 위 순서로 연결하고, 재부팅한 뒤 비밀번호 입력 없이 다시 연결되는 것까지 확인했습니다. 다른 PC 에서 문제가 있으면 오류 문구와 함께 알려 주세요.

- **재부팅 직후 «연결 끊김»(탐색기 빨간 X)** 으로 보일 수 있습니다. 드라이브를 한 번 열면 다시 연결됩니다(`Get-SmbMapping` 으로 상태 확인).
- **비밀번호를 바꾼 뒤**에는 PC 에 저장된 값이 낡아 연결이 실패합니다. 1번 `cmdkey` 명령을 다시 실행하세요.
- **명령에 `-SaveCredentials` 를 넣지 마세요.** `-Persistent $true` 와 함께 쓰면 «매개 변수가 틀립니다» 가 납니다. 비밀번호 저장은 1번의 `cmdkey` 로 합니다. `-Credential` 을 직접 넘기는 방식은 연결은 되지만 비밀번호가 저장되지 않아 재부팅 뒤 다시 묻습니다.
- **«로컬 장치 이름에 저장된 다른 네트워크 리소스에 대한 연결이 있습니다»** — 이미 쓰는 드라이브 문자입니다. 다른 문자로 바꾸세요.
- **«네트워크 경로를 찾지 못했습니다»** — 한 번 나왔다가 다시 하면 되는 경우가 있었습니다(원인 미확인). 계속 나오면 UDP 1443 이 막힌 망인지 확인하세요.
- 명령은 성공했는데 탐색기 «내 PC» 에 안 보이면 탐색기를 다시 시작하세요: `taskkill /f /im explorer.exe` → `start explorer.exe`

### 자체 서명 인증서를 쓰는 경우 (`TLS_MODE=internal`)

Windows 가 인증서를 신뢰하지 않으면 연결이 거부됩니다. 서버의 `/srv/<접두어>/samba/tls/cert.pem` 을 PC 로 가져와 **«신뢰할 수 있는 루트 인증 기관»** 에 등록하세요. 공인 도메인을 쓰는 설치(Let's Encrypt)에서는 필요 없습니다.

---

## Secure Boot 가 켜져 있다면

Secure Boot 서버는 **서명되지 않은 커널 모듈을 적재하지 않습니다.** 설치 중 «Secure Boot 가 켜져 있어 … 적재하지 못했습니다» 경고가 나오면 DKMS 가 만든 서명 키를 한 번 등록합니다.

1. `sudo mokutil --import /var/lib/dkms/mok.pub` — 비밀번호를 정합니다.
2. 서버를 **재부팅**합니다. 부팅 중 파란 «MOK management» 화면이 나오면 **Enroll MOK → Continue → Yes** 를 고르고 방금 정한 비밀번호를 입력한 뒤 재부팅합니다(서버 콘솔/IPMI 접근이 필요합니다).
3. 다시 56단계를 실행합니다.
   ```bash
   sudo python3 /opt/devmaru-kit/bin/devmaru-install --config /etc/<접두어>/site.env --yes --only 56
   ```

> 가상 머신(LXD 등)에서 시험할 때 Secure Boot 를 끌 수 없으면 `SMB_TRANSPORTS=tcp:445` 로 Samba 서비스·계정 부분만 점검할 수 있습니다.

커널을 업데이트하면 DKMS 가 새 커널용 모듈을 **자동으로 다시 빌드**합니다(`AUTOINSTALL`). 커널 헤더 패키지(`linux-headers-generic`)가 설치되어 있어야 합니다.

---

## 문제 해결

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

## 보안 메모

- 기본은 **QUIC 만** 엽니다(TCP 445 비개방). SMB 서명 필수, 최소 프로토콜 SMB 3.1.1, 게스트 접근 금지.
- 개인 공유는 본인만, 공용(`shared`)은 `<접두어>` 그룹 회원만 접근합니다.
- 인증서·키는 `/srv/<접두어>/samba/tls`(root 만 읽음)에 있고, 공인 인증서는 갱신될 때마다 자동 배포·서비스 재시작됩니다.
- 이 기능이 쓰는 QUIC 커널 모듈은 **GPL-2.0-or-later**(상류 `lxin/quic`)이며 저장소에 포함하지 않고 설치할 때 받습니다. 호환 패치 파일(`ubuntu-abi38.patch`)만 이 저장소에 있습니다.
