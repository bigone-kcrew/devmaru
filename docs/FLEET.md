# 🛰 원격 점검·설치 — `devmaru-fleet` (읽기 전용 점검 · 원격 설치 · 갱신)

> 관리자 PC 한 대에서 **여러 devmaru 서버**를 SSH 로 점검합니다. 서버에는 새 프로그램을 설치하지 않고, **아무것도 바꾸지 않습니다**(읽기 전용 명령만 실행).
>
> 설계 배경: `DESIGN-fleet.md`(저장소 외부 문서). **1단계**는 점검(`status`·`check`·`watch`)·호스트 키 신뢰(`trust`)·관리자 PC 점검(`doctor`), **2단계**는 릴리스 검증(`verify-release`)과 원격 설치(`install`)입니다. 갱신·보안 패치는 이후 단계입니다.

## 준비

1. **관리자 PC**: Python 3.8+ 와 OpenSSH 클라이언트(`ssh` · `ssh-keyscan` · `ssh-keygen`). Linux·macOS·WSL 에서 씁니다(네이티브 Windows 는 시험 전입니다).
2. **서버**: `agent` 모듈을 켜고(`MODULES` 에 `agent`) 에이전트 계정에 점검용 SSH 공개키를 등록합니다.
   ```
   sudo <접두어>-agent-setup install
   sudo <접두어>-agent-key add <공개키 파일>
   ```
   에이전트 계정의 제한 sudo 는 **정확한 읽기 전용 명령줄**만 비밀번호 없이 허용합니다(`doctor --json` · `member-update-all --check|--json` · `service-update --all --plan|--check` · `golden check` · `maintenance status [--json]` · `update --check`). 이 단계의 서버 쪽 요구는 **킷 1.3.0 이상**(`member-update-all --json`·`maintenance`)입니다.
3. **인벤토리**(서버 이름·주소·포트·계정·접두어만, **비밀 없음**): `~/.config/devmaru-fleet/hosts.toml` (`DEVMARU_FLEET_INVENTORY` 로 위치 변경, Python 3.11 미만이면 같은 내용을 `hosts.ini` 로)
   ```toml
   [defaults]
   user   = "devmaru-agent"
   prefix = "devmaru"
   # ssh_config = "~/.ssh/fleet_config"   # 이 도구 전용 ssh 설정(키 분리 등). 선택

   [hosts.main]
   address = "server1.example.org"
   group   = "prod"
   domain  = "main.example.org"     # 선택: 접속한 서버의 도메인이 다르면 «불일치»로 막는다(서버 오인 방지)

   [hosts.lab]
   address = "192.168.0.55"
   port    = 2222                    # 예: WSL2 (Windows OpenSSH 가 22 를 쓰는 경우)
   canary  = true                    # 갱신 단계에서 먼저 적용할 서버
   ```

## 사용

```
devmaru-fleet doctor                  관리자 PC 쪽 점검(ssh·호스트 키·ssh-agent·키 권한·인벤토리)
devmaru-fleet trust <서버>            SSH 호스트 키 지문을 보여 주고, 서버 이름을 직접 입력하면 등록
devmaru-fleet status [--hosts a,b] [--json]    상태·회원 READY/BUSY 집계·정비 락·킷 버전
devmaru-fleet check  [--hosts a,b] [--json]    갱신 가능 여부(킷·Golden 업스트림)
devmaru-fleet watch --once            status 를 모아 직전 결과와 비교, 달라진 것만 출력
devmaru-fleet log [--tail N]          이 도구의 감사 로그
```

- **호스트 키**: 처음에는 `trust` 로 지문을 확인하세요. 서버 콘솔이나 관리자가 알려 준 지문과 맞을 때만 이름을 입력합니다. 이미 등록된 키가 있으면 덮어쓰지 않고 경고합니다. 키가 바뀐 서버는 `status` 가 «신뢰» 로 표시하고 접속하지 않습니다.
- **종료 코드**: 0 정상(watch: 변화 없음) · 1 경고·변화·실패 · 2 서버에 닿지 못함(호스트 키 미등록·변경 포함) · 64 사용법·인벤토리 오류.
- **정기 점검**: `watch --once` 를 cron · systemd 타이머 · Windows 작업 스케줄러에서 부르세요(예: `*/30 * * * * devmaru-fleet watch --once || mail …`). 이 도구는 상주하지 않고, 알림 본문(표준 출력)에는 서버 이름·항목·건수만 담깁니다.
- **회원 정보**: 회원 ID·대화·세션 이름은 가져오지 않습니다(집계만).
- **감사 로그**: `~/.local/state/devmaru-fleet/audit.log` — 시각·서버·명령 종류·결과만(원격 출력·비밀 없음).

## 2단계 — 릴리스 검증과 원격 설치

```
devmaru-fleet verify-release <tarball> [--allow-unsigned]
devmaru-fleet install plan   <서버> --config <설정 파일> --kit <tarball> [--skip-dns] [--allow-unsigned]
devmaru-fleet install apply  <서버> --config <설정 파일> --kit <tarball> [--skip-dns] [--allow-unsigned]
devmaru-fleet install status <서버> [--follow]
devmaru-fleet install resume <서버>
```

**릴리스 검증**: `<tarball>.sha256`(필수)과 서명 `<tarball>.sig`를 확인합니다. 서명은 신뢰하는 서명자 목록(`~/.config/devmaru-fleet/release-allowed-signers`, `DEVMARU_FLEET_SIGNERS` 로 변경)의 한 줄 `devmaru-release <공개키>` 로 `ssh-keygen -Y verify` 합니다. 서명이 없거나 목록이 없으면 **중단**하고, 서명 없는 릴리스를 쓰려면 `--allow-unsigned`(경고가 남습니다). 발행자는 `sign-release.sh <tarball> <개인키>` 로 서명합니다.

**설치 계획(`install plan`)** — 서버에는 업로드한 파일 외에 **아무것도 설치되지 않습니다**:
1. 로컬: 설치 설정 파일 검증(`KEY=값`, **비밀 키(비밀번호·토큰 등)는 거부**, 알 수 없는 키 거부, `PFX` 가 인벤토리 접두어와 같아야 함), 릴리스 검증.
2. 서버(읽기): OS·아키텍처·메모리·`/srv` 여유·80/443·이미 설치된 흔적·`sudo` 가능 여부·Python.
3. 킷·설정을 `/tmp/devmaru-fleet-<계정>/`(권한 0600)에 올리고 sha256 이 로컬과 같은지 확인.
4. 서버에서 `devmaru-install --plan` 을 sudo 로 실행해 단계 목록만 보여 줍니다.

**설치 적용(`install apply`)**: 계획과 같은 점검을 다시 하고, 실패 항목이 있으면 중단합니다. 통과하면 **서버 이름을 직접 입력**해야 하며(`--yes` 로 건너뛸 수 없음), 서버에서 `systemd-run`(유닛 `devmaru-fleet-install`, 로그 `/var/log/devmaru-fleet-install.log`)으로 **분리 실행**합니다. 이 도구(또는 SSH)가 끊겨도 서버에서는 설치가 계속됩니다.
- 진행: `install status <서버>`(한 번 보기) · `--follow`(끝까지 따라가기). 끝나면 `doctor` 결과를 보여 줍니다(sudo 권한이 있을 때).
- **중단·실패 후 이어서**: `install resume <서버>` — 서버 재부팅·강제 중지(종료 기록 없음)나 실패(`설치 중단`) 뒤 `--resume` 으로 실패한 단계부터 이어서 실행합니다(서버 이름 직접 입력).
- sudo: 서버 계정에 비밀번호 없는 sudo 가 있으면 그대로, 비밀번호가 필요하면 **터미널에서** 실행해야 합니다(`ssh -t` — 비밀번호는 사람이 서버에 직접 입력하며 이 도구는 다루지 않습니다). 터미널이 없으면 안내만 하고 멈춥니다.
- 이미 devmaru 가 설치된 서버(`/opt/devmaru-kit` 존재)에는 설치하지 않습니다(갱신은 `update`).
- 현재는 **로컬에 받아 둔 tarball** 만 지원합니다(`--kit`). 릴리스 주소에서 직접 받기는 후속입니다.

## 3단계 — 킷 갱신과 회원 컨테이너 갱신

```
devmaru-fleet update plan  --kit <릴리스.tar.gz> [--hosts a,b]      # 읽기 전용: 서버별 가드 결과만
devmaru-fleet update apply --kit <릴리스.tar.gz> [--hosts a,b] [--rolling N] [--force] [--allow-unsigned]
devmaru-fleet update status <서버> [--follow]
devmaru-fleet members plan|apply|status <서버>
```

- **순서**: canary 로 표시한 서버가 먼저, 그 뒤 나머지가 한 대씩(`--rolling N` 이면 N대씩). 앞 단계가 실패하면 뒤 서버는 **진행하지 않습니다**.
- **확인**: 서버마다 서버 이름을 그대로 입력합니다. 여러 대를 묶을 때는 그룹 이름(없으면 `all`)을 입력합니다. 서명 검증(`verify-release`)을 먼저 통과해야 합니다.
- **가드(하나라도 실패하면 적용 안 함)**: 설치된 킷이 있고 새 킷이 더 높은 버전일 것(다운그레이드 거부, 같은 버전은 `--force`) · 다른 정비 작업이 없을 것(정비 락) · 비밀번호 없는 sudo(또는 `agent` 모듈의 제한 sudo) · Golden 이 바뀌면 `/srv` 여유 30GB 이상. 작업 중인 회원이 있으면 경고합니다.
- **실행**: tarball 과 sha256 을 올려 서버 값과 대조한 뒤 `systemd-run` 으로 분리 실행합니다(연결이 끊겨도 계속). 끝나면 킷 버전과 `doctor --json` 이 `pass` 인지 확인합니다.
- **되돌리기**: 공식 롤백 도구는 없습니다. 실패하면 원인을 보고 `update` 를 다시 하거나 이전 킷으로 다시 적용합니다.
- **`members apply`**: `member-update-all` 을 분리 실행해 회원 컨테이너를 새 Golden 으로 다시 만듭니다. 작업 중인 회원이 있거나(BLOCKED) 개발 컨테이너가 없는 회원이 있으면(REVIEW) **묻지 않고 거부**하며, 할 일이 없으면 아무것도 하지 않습니다.

## 하지 않는 것
갱신·보안 패치·회원 추가/삭제·방화벽 변경(이후 단계). 1단계 명령(`status`·`check`·`watch` 등)은 서버를 바꾸지 않습니다. 비밀번호·SSH 개인키·sudo 비밀번호를 읽거나 저장하지 않습니다(ssh-agent 와 시스템 `ssh` 를 씁니다).
