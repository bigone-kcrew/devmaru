# 방화벽 기본 구성 — `<접두어>-firewall`

호스트 방화벽을 **ufw** 로 구성하는 도구입니다. 설치기는 방화벽을 건드리지 않으며, 이 도구도 `plan` 외에는 사람이 실행해야 적용됩니다.

```bash
sudo <접두어>-firewall plan                 # 넣을 규칙·현재 SSH 접속 점검·막힐 포트(기본, 아무것도 바꾸지 않음)
sudo <접두어>-firewall apply [--timeout 120] # 적용. N초 안에 confirm 이 없으면 자동 롤백
sudo <접두어>-firewall confirm              # 새 접속이 되는 것을 확인한 뒤 확정
sudo <접두어>-firewall rollback             # 즉시 되돌림
sudo <접두어>-firewall status
```

## 왜 ufw 인가 (Ubuntu 26.04)
- Ubuntu 의 기본 방화벽 프런트엔드는 ufw 이고 패키지가 기본 이미지에 들어 있습니다(꺼진 상태). 커널 쪽은 nftables 이며 ufw 가 그 위에서 동작합니다. 관리자가 `ufw status` 로 바로 읽을 수 있습니다.
- nftables 를 직접 쓰면 규칙은 더 정밀하지만 도커가 만드는 iptables-nft 규칙과 한 표를 공유해 `flush ruleset` 이 도커 네트워크를 깨뜨릴 위험이 있고, 직접 짠 규칙 파일을 유지해야 합니다. 이 킷의 요구(포트 몇 개·대역 허용)는 ufw 로 충분합니다.
- 설치 서버에 ufw 가 없으면 `sudo apt install ufw` 후 실행하세요(`apply` 가 안내하고 멈춥니다).

## 규칙
| 허용 | 근거 |
|---|---|
| SSH: sshd 가 실제로 듣는 포트(`sshd -T`) ∪ site.env `SSH_PORT`, **어디서나** | 회원이 SSH 로 접속하므로 관리자 대역으로 제한하지 않음 |
| 80/tcp, 443/tcp, 443/udp | 웹(Caddy)·인증서 발급·HTTP/3 |
| `SMB_TRANSPORTS` 포트(smb 모듈일 때) | 기본 `quic:1443` → 1443/udp |
| `ADMIN_CIDRS` 대역(127.0.0.1/32 제외) 전체 | 관리자 대역 유지 |
| 172.16.0.0/12 | 도커 내부망의 컨테이너 → 호스트 |
그 외 들어오는 연결은 차단, 나가는 연결은 허용. 나머지 compose 서비스는 127.0.0.1 에만 열려 있어 규칙이 필요 없습니다.

## 접속이 끊기지 않게
1. `apply` 전에 **현재 SSH 세션**(sshd 소켓 기준)의 로컬 포트가 허용 목록에 있는지 확인하고, 없으면 적용하지 않습니다.
2. 기존 ufw 설정(`/etc/ufw`)을 백업하고, **적용 전에** systemd 타이머(`<접두어>-firewall-rollback`)를 만듭니다. 연결이 끊겨도 타이머가 돌아가 이전 상태를 복원합니다.
3. 적용 뒤 **다른 터미널에서 새 SSH 접속**이 되는지 확인하고 `confirm` 을 실행합니다.
4. 복구 수단: 콘솔(VM 콘솔·`lxc exec` 등)에서 `<접두어>-firewall rollback` 또는 `ufw disable`.

## 한계·주의
- 이미 켜져 있는 ufw 규칙은 `apply` 때 위 규칙으로 **교체**됩니다(롤백하면 복원). `plan` 이 켜짐 여부를 알려 줍니다.
- 롤백 타이머는 임시(transient)라서 `confirm` 전에 서버가 재부팅되면 롤백되지 않고 새 규칙이 남습니다(SSH 는 열려 있음).
- **도커가 0.0.0.0 으로 게시한 포트**(예: Files 의 SFTP 2022)는 도커 규칙이 먼저 적용되어 ufw 규칙만으로는 막히지 않습니다. 그래서 `apply` 는 `/etc/ufw/after.rules` 끝에 `DOCKER-USER` 블록(`# BEGIN <접두어>-firewall docker` ~ `# END`)을 덧붙여, 게시 포트로 들어오는 새 연결(DNAT)에도 위 허용 목록을 적용합니다. 컨테이너 쪽(`docker0`·`br-*`)에서 오는 연결과 이미 맺어진 연결은 건드리지 않습니다. `plan` 의 «docker 가 외부로 게시한 포트» 가 허용/차단을 미리 보여 줍니다.
  - 블록은 ufw 설정(`/etc/ufw`)의 일부라서 `confirm` 이 없으면 자동 롤백 때 함께 원복되고, 재부팅 뒤에도 ufw 와 함께 유지됩니다. 허용 목록을 바꾸면(site.env 수정 등) `apply` 를 다시 실행하세요.
  - 막힌 게시 포트를 쓰려면 접속하는 쪽 대역을 `ADMIN_CIDRS` 에 넣어 다시 `apply` 하거나, 게시를 127.0.0.1 로 바꾸고 리버스 프록시(Caddy)로 여세요. 예) Files 의 SFTP 2022 는 허용 목록에 없으므로 외부에서는 **차단**됩니다.
  - IPv6(`after6.rules`)와, 도커 브리지 이름이 `docker0`·`br-*` 가 아닌 구성은 다루지 않습니다.
- 클라우드·상위 방화벽(공유기·보안 그룹)은 별도입니다.
