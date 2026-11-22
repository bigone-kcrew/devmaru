# 🚚 라이브 서버 이관 — `tools/devmaru-migrate-live`

> 데이터가 수백 GB 인 서버를 **두 서버가 동시에 살아 있는 채로** rsync 로 옮기고, 짧은 정지 시간 안에 전환하는 플레이북입니다.
>
> 독자: 서버 관리자와 그를 돕는 AI 에이전트. 명령은 모두 **사람이 직접** 실행합니다(데이터를 덮어쓰고 네트워크를 바꾸는 명령이라 에이전트 계정의 제한 sudo 목록에 넣지 않습니다).
>
> 아래 `<접두어>` 는 설치 때 정한 접두어(기본 `devmaru`)입니다. 주소·이름은 예시입니다(`192.0.2.0/24`, `example.org`, 회원 `alice`).

- [언제 무엇을 쓰나](#-언제-무엇을-쓰나)
- [도구](#-도구)
- [준비](#-준비-d-7--d-1)
- [전환 순서](#-전환-순서-t0)
- [IP 교체](#-ip-교체)
- [검증 체크리스트](#-검증-체크리스트)
- [롤백](#-롤백)
- [구 서버 보관·폐기](#-구-서버-보관폐기-기준)
- [이관 후 정리](#-이관-후-정리)
- [함정 목록](#-함정-목록)
- [한계와 미검증](#-한계와-미검증)

---

## 🧭 언제 무엇을 쓰나

| | `<접두어>-migrate` ([RECOVERY](RECOVERY.md#-이관)) | `devmaru-migrate-live` (이 문서) |
|---|---|---|
| 방식 | 설정·DB 덤프를 **암호화 묶음 1개**로 export → import | 디렉터리를 **rsync 로 그대로** 복사(DB 는 PGDATA 째로) |
| 데이터 크기 | 작음~중간(회원 workspace 는 묶음에 없음) | 수백 GB 이상 |
| 정지 시간 | 덤프·복원 시간만큼 | 시드 복사(가동 중) 뒤 **증분만** 최종 동기화 |
| 두 서버 | 새 서버에 같은 킷 버전 설치 후 import | 두 서버가 같은 LAN·SSH 로 닿고 동시에 켜져 있음 |
| 결과 | 새 서버 값 위에 설정·DB 를 복원 | 구 서버 **실물**(설정·비밀·인증서·호스트 키 포함)을 그대로 |
| 네트워크 | 바뀌지 않음 | 필요하면 구 서버 IP 를 신 서버가 승계(IP 교체) |

- 회원·데이터가 적고 새 서버의 도메인·IP 가 달라도 되면 → **`<접두어>-migrate`**.
- 큰 데이터, 짧은 정지, 같은 IP·같은 호스트 키·같은 인증서를 그대로 이어야 하면 → **이 문서**.
- 둘을 섞지 마세요. 예: PGDATA 를 rsync 로 옮겼다면 덤프 복원(`restore apply db`)은 건너뜁니다.

---

## 🧰 도구

관리자 셸에서 쓰는 bash 스크립트 묶음입니다. **구·신 서버 양쪽**에 같은 폴더를 복사해 둡니다(예: `/root/migrate-live/`).

```bash
cp migrate.conf.example migrate.conf                 # 신 서버 주소·hostname·받는 계정·키
cp migrate-groups.conf.example migrate-groups.conf   # 옮길 디렉터리 그룹(devmaru 기본 레이아웃 예시)
```

| 도구 | 어디서 · 권한 | 하는 일 |
|---|---|---|
| `mig-inventory.sh` | 양쪽 · root 권장 | 파일·유닛 목록 `snapshot` → `diff`. 키트가 놓친 헬퍼·드롭인·링크·런타임 디렉터리, 없는 NIC 를 쓰는 방화벽 규칙 |
| `mig-rsync.sh` | 구 · root | 그룹 하나 전송(push). 기본 시험 실행, `--apply` · `--seed` · `--final --stopped` · `--checksum` · `--subdir` · `--bwlimit` · `--usermap/--groupmap` |
| `mig-status.sh` | 구 · 로그 읽기(sudo) | 그룹별 마지막 전송 상태·요약 |
| `mig-stopcheck.sh` | 구 · root | «다 멈췄다» 확인: 루트·루트리스 도커, 호스트 프로세스, `postmaster.pid`, SQLite WAL, 타이머 |
| `mig-final.sh` | 구 · root(tmux) | `apply`: 정지 확인 → 확인 문구 → 전 그룹 최종 동기화 / `verify`: 전송 0·삭제 0 이면 «일치» 표 |
| `mig-accounts.sh` | 구 export · 신 import · root | 회원 UID/GID/추가 그룹·subuid 범위·비밀번호 해시(화면에는 지문 12자만) |
| `mig-images.sh` | 구 plan/send · 신 load | `docker save \| zstd \| ssh` 전송, sha256 대조, 적재 후 이미지 ID 대조(+저장 tar 의 Config 해시) |
| `mig-containers.sh` | 구 · docker 그룹 | compose 가 아닌 `docker run` 컨테이너 설정을 재생성 스크립트로(비밀 env 는 별도 `.env` 600) |
| `mig-ipswap.sh` | 각 서버 · root | netplan 고정 IP 교체: 콘솔 `netplan try` / 원격 «적용 + 자동 원복 타이머» |

공통 원칙: 기본은 **계획·시험 실행만**, 바꾸는 것은 `--apply`. 되돌리기 어려운 것(최종 동기화·IP 교체)은 **확인 문구**를 입력해야 합니다(`--yes` 로 생략 가능). 비밀(해시·env 값·키)은 출력하지 않습니다. 스크립트 본문은 함수로 감싸 실행 중에 파일을 고쳐도 영향이 없습니다. 시험: `bash tests/migrate_live_test.sh`(가짜 ssh·rsync·docker).

### 그룹 파일 — `migrate-groups.conf`

```
# 이름 | 종류 | 원본 경로(공백 구분) | 옵션 | 설명
users        | live | /srv/{PFX}/users          | exclude=/*/tmp/*                 | 회원 workspace
db-postgres  | stop | /srv/{PFX}/nvme/postgres  |                                  | PGDATA
etc          | conf | /etc/{PFX}                | exclude=*.bak.* groupmap=caddy   | site.env·secrets
caddy-data   | conf | /var/lib/caddy/.local/share/caddy | usermap=caddy groupmap=caddy | 인증서
ssh-hostkeys | conf | /etc/ssh                  | include=ssh_host_*               | 호스트 키만
```

| 종류 | 가동 중 | 최종(`--final --stopped`) |
|---|---|---|
| `live` | `--apply` 로 언제든(시드 복사) | `--delete-after` 로 삭제까지 반영 |
| `stop` (DB·SQLite·tdb·루트리스 도커 data-root) | `--seed` 로 «밑그림»만(최종본 아님, 이것으로 서비스를 띄우지 않는다) | 정지 후에만. `--delete-after` + `--checksum` |
| `conf` (설정·비밀·인증서·호스트 키) | `--apply` | 덮어쓰기만, **삭제하지 않음**(신 서버 설치기가 만든 파일 보존) |

rsync 옵션은 항상 `-aHAXx --numeric-ids --partial --mkpath`(양쪽 rsync 3.2.3 이상). 신 서버는 받는 계정(`RUSER`)의 `sudo -n /usr/bin/rsync` 로 받아 소유자·ACL·xattr 를 보존합니다. `mig-final.sh` 는 이 파일의 **순서대로** 처리하므로 큰 데이터를 위에 둡니다.

`usermap=`/`groupmap=` 에 **이름**을 쓰면 도구가 양쪽 서버에서 번호를 찾아 `구번호:신번호` 로 바꿉니다(같으면 생략, 한쪽에 없으면 중단). `982:981` 처럼 번호를 직접 써도 됩니다.

---

## 🧱 준비 (D-7 ~ D-1)

### 1. 신 서버 설치와 계획
1. 신 서버에 **같은 접두어·같은 킷 버전**으로 설치합니다(`MODULES` 도 같게). hostname 은 구 서버와 **다르게** 둡니다(도구의 방향 확인이 hostname 으로 구분합니다).
2. 신 서버의 Caddy 와 타이머는 **꺼 둡니다**(`systemctl disable --now caddy`, `<접두어>-*.timer`). 전환 전에는 공개 트래픽을 받지 않고, 동기화 도구가 빈 입력으로 무언가를 덮어쓰지 않게 합니다.
3. 회원 개발 컨테이너는 신 서버에 **아직 만들지 않습니다**([함정 3](#3-두-서버를-동시에-살리지-않는다)).
4. 일정·정지 허용 시간·롤백 기준·구 서버 처리(보관/폐기)를 미리 정해 회원에게 공지합니다. 외부 수집·알림처럼 부작용이 있는 작업의 담당자와 «정지 → 재개 승인» 절차를 맞춥니다.

### 2. 디스크·네트워크
```bash
df -h /srv /var/lib/docker                         # 양쪽. 신 서버 여유 ≥ 구 서버 사용량 + 20%
sudo du -sh --apparent-size /srv/<접두어>/users     # 하드링크가 많으면 rsync 통계가 실제보다 크게 나온다
iperf3 -s   # 신 서버 / iperf3 -c <신 서버>  # 구 서버: 링크 속도
iostat -x 5 # 구 서버: 디스크 %util 이 이미 80~90% 면 전송 속도는 링크가 아니라 구 서버 디스크가 정한다
```
- 1 Gbps 링크라도 구 서버 HDD 가 운영 부하로 포화돼 있으면 수 MB/s 까지 떨어집니다. 한가한 시간대에 돌리고, 그룹을 동시에 여러 개 돌리지 마세요(병렬은 HDD 를 더 느리게 합니다). `ionice -c3` 는 `mq-deadline`·`none` 스케줄러에서 효과가 없습니다 — `--bwlimit` 로 조절합니다.

### 3. 이관 전용 SSH 경로
```bash
# 구 서버(root)
ssh-keygen -t ed25519 -N '' -f /root/.ssh/migrate_ed25519
ssh-keyscan -p 22 192.0.2.20 > /root/.ssh/known_hosts_migrate   # 지문은 신 서버 콘솔의 값과 대조
# 신 서버: 받는 계정(예: migrate)
#   ~migrate/.ssh/authorized_keys 에  from="192.0.2.10" ssh-ed25519 AAAA… migrate-live
#   /etc/sudoers.d/migrate-live (0440):  migrate ALL=(root) NOPASSWD: /usr/bin/rsync
```
이관이 끝나면 키·sudoers 줄을 지웁니다([이관 후 정리](#-이관-후-정리)).

### 4. 구/신 서버 «목록 비교» — 필수
설치 키트가 «복제본» 을 만들어도 놓치는 것이 있습니다. 시드 복사 전에 한 번, 전환 직전에 한 번 비교합니다.
```bash
sudo bash mig-inventory.sh snapshot > /tmp/old.inv         # 구 서버
sudo bash mig-inventory.sh snapshot > /tmp/new.inv         # 신 서버 (NIC 경고가 나오면 함정 9)
scp 구서버:/tmp/old.inv . && bash mig-inventory.sh diff old.inv new.inv
```
추가로 직접 비교할 것:
```bash
systemctl list-unit-files --state=enabled --no-legend | sort        # 양쪽 → diff
systemctl list-timers --all --no-legend | awk '{print $(NF-1)}' | sort
find /etc/systemd/system -name '*.d' -type d | sort                # 드롭인(*.service.d)
sudo crontab -l; for u in $(ls /var/spool/cron/crontabs); do echo "== $u"; done
find /usr/local -maxdepth 3 -type l -printf '%p -> %l\n' | sort    # 링크 목록(신 서버에서 복사본이면 함정 1)
sudo nft list ruleset | grep -oE 'i(if|of)name [^ ]+' | sort -u ; ip -br link
```
«구에만» 있는 항목은 하나씩 «옮긴다 / 의도적으로 뺀다» 를 정해 기록합니다. 대표 누락은 [함정 1](#1-설치-키트가-놓치는-것).

### 5. 시드 복사(가동 중) — 정지 시간 줄이기
```bash
tmux new -s mig
sudo bash mig-rsync.sh list
sudo bash mig-rsync.sh users                      # 시험 실행: 양·시간 가늠
sudo bash mig-rsync.sh users --apply --bwlimit 60000
sudo bash mig-rsync.sh users --subdir alice --apply   # 큰 회원만 따로
sudo bash mig-rsync.sh db-postgres --seed --apply     # stop 그룹: 밑그림만
sudo bash mig-status.sh
```
- 시드는 전환 전날까지 여러 번 반복해도 됩니다(바뀐 것만 갑니다). 마지막 시드가 최종 동기화에 가까울수록 정지 시간이 짧습니다.
- 종료 코드 24(«전송 중 사라진 파일»)는 가동 중 복사에서 정상입니다.
- 구 서버에서 파일을 정리(삭제)하면 최종 동기화의 `--delete-after` 가 신 서버에도 반영합니다. 신 서버 쪽에서 따로 지우지 마세요.

### 6. 이미지·수동 컨테이너·계정 사전 점검
```bash
sudo bash mig-images.sh plan                            # 컨테이너가 쓰는 이미지·제외된 태그
DOCKER_HOST=unix:///run/user/1002/docker.sock bash mig-images.sh plan   # 회원 루트리스 도커 이미지
bash mig-containers.sh export memory-db kordoc-bridge    # docker run 으로 만든 것만(예시 이름)
sudo bash mig-accounts.sh export --users alice,bob       # 계획 확인용(전환 때 다시)
```
이미지는 미리 `send --apply` 해 두고 전환 때 바뀐 것만 다시 보내면 정지 시간이 줄어듭니다.

---

## ⏱ 전환 순서 (T0)

원칙: **구 서버는 끝까지 읽기만 합니다.** 어느 단계에서든 구 서버를 다시 켜면 되돌아갑니다.

### T0 — 정지 (구 서버)
1. 부작용 있는 작업을 먼저 막습니다: 외부 수집·알림(웹훅)·백업 업로드 등은 **정지 표식(marker 파일)** 이나 크론 줄 주석으로 막고, 정지 표식은 데이터와 함께 신 서버로 복사되므로 **신 서버에서도 재개 승인 전까지 막혀 있게** 둡니다. crontab 은 지우기 전에 사본을 남깁니다(`crontab -l > /root/crontab.pre-cutover`).
2. 회원 활동을 확인하고 타이머를 멈춥니다: `sudo systemctl stop $(systemctl list-units '<접두어>-*.timer' --plain --no-legend | awk '{print $1}')`
3. 컨테이너를 **쓰기 주체 → DB** 순서로 멈춥니다:
   ```bash
   docker stop -t 60 $(docker ps --format '{{.Names}}' | grep '^dev-')    # 회원 개발 컨테이너
   docker stop -t 60 n8n sftpgo <그 밖의 앱 컨테이너>
   docker stop -t 120 postgres                                           # DB 는 마지막(충분한 -t)
   # 회원 루트리스 도커: 회원마다
   sudo -u alice XDG_RUNTIME_DIR=/run/user/$(id -u alice) docker ps -q | xargs -r sudo -u alice XDG_RUNTIME_DIR=/run/user/$(id -u alice) docker stop
   sudo systemctl stop smbd nmbd 2>/dev/null
   ```
4. DB 정상 종료 확인:
   ```bash
   docker logs postgres --tail 5            # «database system is shut down» · 종료 시각을 적어 둔다
   docker inspect -f '{{.State.ExitCode}}' postgres    # 0
   sudo test ! -e /srv/<접두어>/nvme/postgres/main/postmaster.pid && echo OK
   ```
5. 정지 확인: `sudo bash mig-stopcheck.sh` — 루트 `docker ps` 에 안 보이는 루트리스 컨테이너·호스트 상주 스크립트(재시작 가드 등)까지 봅니다. 상주 스크립트 이름은 `migrate.conf` 의 `EXTRA_PROC_PATTERNS` 에 넣어 둡니다. **FAIL 이 하나라도 있으면 진행하지 않습니다.**
6. 마지막 자산: `sudo bash mig-accounts.sh export` · `bash mig-containers.sh export …`(바뀌었으면).

### T0+α — 최종 동기화 (구 서버, tmux)
```bash
sudo bash mig-final.sh apply           # 정지 확인 → «최종 동기화 <신 hostname>» 입력 → 전 그룹
sudo bash mig-final.sh verify          # 표: 전부 «일치»(전송 0·삭제 0) 여야 다음으로
sudo bash mig-images.sh send --apply   # 이미지(바뀐 것이 있으면)
```
- 실패·불일치 그룹이 있으면 원인을 확인한 뒤 **같은 명령을 다시** 실행합니다(바뀐 것만 다시 보냅니다). 한 그룹만: `sudo bash mig-rsync.sh <그룹> --final --stopped --apply`.
- `verify` 의 stop 그룹은 체크섬 비교라 오래 걸립니다(양쪽 전부 읽음). `--fast` 는 체크섬을 생략합니다(크기·시각 비교만).
- conf 그룹은 삭제를 하지 않으므로 `verify` 의 «일치» 는 «구 서버 파일이 모두 신 서버에 같은 내용으로 있다» 는 뜻입니다(신 서버에만 있는 파일은 셈하지 않음).

### 신 서버 준비
1. 계정: `sudo bash mig-accounts.sh import` → 계획 확인 → `--apply`. UID/GID·subuid 가 다르면 도구가 멈춥니다([함정 6](#6-uidgid-는-번호로-옮겨진다)).
2. 소유자 보정 확인: `stat -c '%U:%G %a' /etc/<접두어>/secrets /var/lib/caddy/.local/share/caddy` — 비밀 폴더가 `docker` 같은 엉뚱한 그룹이면 `chgrp` 로 바로잡습니다.
3. 이미지: `bash mig-images.sh load ~migrate/<접두어>-images-stage/images-<시각>.tar.zst --apply` — 전부 «일치» 또는 «일치(config)».
4. SSH 호스트 키를 옮겼다면 권한 확인(`chmod 600 /etc/ssh/ssh_host_*_key`) 후 **열린 세션을 유지한 채** `sudo systemctl restart ssh`, 새 창에서 접속 시험([함정 7](#7-ssh-호스트-키와-접속-경로)).
5. 방화벽: 규칙의 NIC 이름을 신 서버에 맞게 고치고 **자동 해제되는 시한 시험**부터([함정 9](#9-방화벽-규칙의-nic-이름)).
6. `sudo bash mig-inventory.sh snapshot` 을 다시 떠서 구 서버 목록과 비교 — 준비 4단계에서 «옮긴다» 로 정한 항목이 다 들어왔는지.

### 서비스 기동 + 내부 시험 (신 서버 · 아직 이관용 IP · 공개 트래픽 없음)
1. DB 먼저: `docker compose -f /opt/<접두어>/compose/postgres/compose.yml up -d` → 로그의 «database system was shut down at …» 시각이 **구 서버 정지 시각과 같은지**, «database system is ready» 인지 확인. 복구(recovery) 로그가 나오면 정상 종료본이 아닙니다 — 멈추고 원인을 봅니다.
2. 나머지 서비스(`compose up -d`)와 수동 컨테이너(`bash ~/<접두어>-mig-containers/<이름>.sh` → 끝나면 `.env` 삭제).
3. 회원 개발 컨테이너: 구 서버가 **완전히 정지된 것을 확인한 뒤** 만들고 **시작**합니다. 생성 스크립트가 `docker create` 만 하면 «Created» 로 남으니 `docker start dev-<ID>` 까지 하고, `docker exec -u <ID> dev-<ID> …` 로 로그인 상태·원격 접속 프로세스를 회원별로 확인합니다(`docker exec` 기본 사용자는 root 라 `-u` 필요).
4. Caddy: 인증서 저장소(`caddy-data`)를 옮겼으므로 재발급 없이 켭니다 → `sudo systemctl enable --now caddy` → `journalctl -u caddy -n 50` 에 인증서 오류가 없어야 합니다.
5. **IP 교체 전 종단 시험** — DNS 를 바꾸지 않고 신 서버로 요청을 보냅니다:
   ```bash
   for h in example.org portal.example.org n8n.example.org alice.example.org; do
     printf '%-28s ' "$h"; curl -sk -o /dev/null -w '%{http_code}\n' --resolve "$h:443:192.0.2.20" "https://$h/"
   done
   ```
6. 의존 파일 확인 후 타이머는 **마지막에** 켭니다([함정 2](#2-입력이-없으면-빈-상태로-덮어쓰는-도구)): 각 타이머의 서비스를 한 번 수동 실행(`systemctl start <접두어>-app-sync.service`)해 결과를 확인한 뒤 `enable --now <타이머>`.

### IP 교체 → 외부 확인 → 재개
1. [IP 교체](#-ip-교체) 절차.
2. 외부(휴대폰 LTE 등 다른 망)에서 도메인·SSH·파일 서비스 도달 확인. 공유기 포트 포워딩은 «대상 IP» 에 붙어 있으므로 IP 를 승계하면 그대로 신 서버로 갑니다.
3. [검증 체크리스트](#-검증-체크리스트).
4. **재개 승인**: 담당자 확인 후 crontab 사본 설치 → 정지 표식 해제 → 첫 실행(수집·알림)이 정상 종료했는지 확인. 공백 기간 동안 놓친 작업의 따라잡기 허용 범위(예: «최근 N일만 받는 API» 의 공백 한도)를 미리 확인합니다.

---

## 🔀 IP 교체

두 서버가 같은 IP 를 동시에 가지면 안 됩니다. 맞교환은 순환이라 **임시 주소**가 필요합니다(예: 구 `192.0.2.10`, 신 `192.0.2.20`, 임시 `192.0.2.30`).

| 단계 | 서버 | 명령 | 확정 |
|:---:|---|---|---|
| 1 | 구 | `mig-ipswap.sh 192.0.2.10 192.0.2.30 --apply …` | 구 서버가 `.30` 으로 닿는지 |
| 2 | 신 | `mig-ipswap.sh 192.0.2.20 192.0.2.10 --apply …` | 신 서버가 `.10` 으로 닿고 외부 도달 확인 |
| 3 | 구 | `mig-ipswap.sh 192.0.2.30 192.0.2.20 --apply …`(선택) | 구 서버를 보관 주소로(또는 전원 끔) |

**한 단계가 확정된 뒤에만 다음 단계로** 갑니다. 도구는 바꿀 IP 가 이미 응답하면(`arping -D`, 없으면 `ping`) 적용을 거부합니다. 구 서버에 `iputils-arping` 을 설치해 두세요(ping 은 방화벽에 막힐 수 있음).

**콘솔(모니터·키보드)이 있으면** — `sudo bash mig-ipswap.sh <지금> <바꿀> --apply` → `netplan try`: 제한 시간(기본 120초) 안에 Enter 로 확정하지 않으면 자동 원복.

**원격(SSH)뿐이면** — `--apply --remote [--timeout 300]`: 파일을 바꾸고 `systemd-run` 으로 «N초 뒤 원래 파일로 되돌리고 `netplan apply`» 타이머(`<접두어>-ipswap-revert`)를 건 뒤 적용합니다. 세션이 끊기면 **바뀐 IP 로 다시 접속**해 `sudo systemctl stop <접두어>-ipswap-revert.timer` 로 확정합니다. 못 하면 저절로 돌아갑니다.
- 단계 1 뒤 구 서버에는 신 서버를 **점프 호스트**로 접속합니다: `ssh -J admin@<신 서버> admin@192.0.2.30`.
- 단계 2 뒤에는 공유기 포워딩(대상 `.10`)이 신 서버로 가므로 외부 주소로 접속해 `hostname` 이 신 서버인지 확인하고 타이머를 멈춥니다.
- 확정 전 3분 안에 외부에서 서비스·SSH 도달을 확인합니다. 안 되면 공유기의 **IP-MAC 바인딩·ARP 캐시**를 의심하고 확정하지 않습니다(타이머가 되돌립니다). 확정 뒤 `sudo arping -U -c 3 -I <NIC> <새 IP>` 로 이웃 장비에 알립니다.
- 원격 교체는 콘솔보다 위험합니다(타이머·점프 접속이 모두 정상일 때만 안전). 현장 접근이 가능한 시간이 있으면 콘솔 방식을 권합니다.

---

## ✅ 검증 체크리스트

| 항목 | 확인 방법 |
|---|---|
| 데이터 | `mig-final.sh verify` 전부 «일치» |
| DB | 첫 기동 로그의 «shut down at» = 구 서버 정지 시각, recovery 없음, 주요 테이블 건수 = 구 서버에서 정지 직전에 적어 둔 기준값 |
| 컨테이너 | `docker ps` 전부 Up/healthy, «Created» 로 남은 것 없음(`docker ps -a --filter status=created`) |
| 이미지 | `mig-images.sh load --apply` 전부 «일치» |
| 웹 | 도메인별 응답 코드가 구 서버 기준과 같다(`curl --resolve`, 교체 뒤에는 외부 망에서), Caddy 인증서 오류 없음 |
| 자동화 | n8n 활성 워크플로 수가 같고 자격증명 복호화 오류 없음(UI 의 credential 테스트·로그 — **값은 출력하지 않는다**) |
| 카탈로그·건수 | 수집 데이터·카탈로그 문서 수가 전환 전에 기록한 기준값 이상 |
| 회원 | SSH 로그인(해시 이관), 개발환경 로그인 유지, 원격 접속(페어링) 확인 — 한 명씩 |
| 파일 서비스 | SFTP/WebDAV/SMB 접속, 업로드·다운로드 |
| 점검 | `sudo <접두어>-doctor` 통과, 타이머 목록이 구 서버와 같다 |
| 백업 | 첫 `sudo <접두어>-backup-run` 성공(저장소 연속성) |

---

## ↩️ 롤백

- **IP 교체 전**: 신 서버의 Caddy·서비스를 멈추고, 구 서버에서 정지했던 컨테이너·타이머를 다시 켜고 정지 표식을 풉니다. 신 서버에는 데이터만 남습니다.
- **IP 교체 후**: 신 서버를 먼저 다른 주소로(또는 서비스 정지), 구 서버를 원래 IP 로 되돌린 뒤 구 서버 서비스를 켭니다. 신 서버에서 생긴 쓰기는 구 서버에 반영되지 않습니다.
- 어느 쪽이든 **전환 뒤에는 구 → 신 rsync 를 다시 실행하지 않습니다**(`--final` 이 신 서버의 새 데이터를 지웁니다). 전환 뒤의 진짜 데이터는 신 서버입니다.
- 두 서버를 동시에 켜지 않습니다([함정 3](#3-두-서버를-동시에-살리지-않는다)).

---

## 🗄 구 서버 보관·폐기 기준

- 전환 뒤 구 서버는 **서비스·컨테이너·크론·타이머를 정지한 채** 보관 주소에 둡니다(롤백 기준점). 데이터를 바꾸지 않습니다.
- 폐기 조건(모두): [검증 체크리스트](#-검증-체크리스트) 통과 · 주기 작업(수집·백업·알림)이 신 서버에서 **여러 주기** 정상 종료 · 최소 1~2일(주간 작업이 있으면 1주) 운영 · 첫 백업 성공.
- 폐기 전: 구 서버에만 있는 데이터(정리하면서 옮긴 휴지통 폴더 등)가 없는지 확인, 비밀 파일(`/etc/<접두어>/secrets`, `/root`, `~/.ssh`, 인증서) 처리 방침, 디스크 완전 삭제 또는 오프라인 보관.

---

## 🧹 이관 후 정리

- 구 서버: `/root/.ssh/migrate_ed25519*`·`known_hosts_migrate` 삭제.
- 신 서버: `authorized_keys` 의 이관 키 줄, `/etc/sudoers.d/migrate-live` 삭제. 비밀번호 로그인을 임시로 켰다면 끄기.
- 양쪽: `sudo bash mig-accounts.sh cleanup`, `~/<접두어>-mig-containers/*.env`, 신 서버 `~migrate/<접두어>-images-stage/`.
- 임시로 끈 것 복원: 무인 업데이트(`unattended-upgrades`), 임시 포트 포워딩 제거, 이관용 임시 IP 반납.
- 클라이언트: 사용자 PC·자동화의 `known_hosts` 정리(`ssh-keygen -R`), 운영 계정의 `known_hosts` 를 이관 전 상태로.
- `mig-inventory.sh diff` 에서 «의도적으로 뺐다» 고 정한 항목을 문서에 남기고, 키트에서 고칠 것(누락 파일·유닛)은 이슈로.

---

## ⚠️ 함정 목록

실제 이관(데이터 수백 GB, 회원 수 명, 서비스 20여 개)에서 겪은 것을 일반화했습니다.

### 1. 설치 키트가 놓치는 것
같은 킷으로 설치한 «복제본» 이어도 운영 중에 손으로 더한 것은 없습니다. `mig-inventory.sh diff` 와 [준비 4](#4-구신-서버-목록-비교--필수) 의 명령으로 찾습니다.
- 호스트 헬퍼 디렉터리(`/usr/local/libexec/…`) — 없으면 그것을 부르는 동기화 도구가 오동작합니다(함정 2).
- systemd **드롭인**(`*.service.d/*.conf`) — 예: Caddy 에 환경변수를 주는 드롭인. 환경변수는 `EnvironmentFile=`(600)로 두고 드롭인에 값을 직접 쓰거나 `--environ` 같은 덤프 옵션을 켜지 마세요(로그에 비밀이 남습니다).
- 보조 유닛(상태 동기화·감시 타이머 등)과 그 타이머.
- Caddy 가 `import` 하는 스니펫·`apps.d` 같은 하위 폴더, 런타임에 생기는 상태 디렉터리(`/var/lib/<접두어>/…`) — Caddyfile 하나만 있으면 `caddy validate` 가 실패합니다.
- 앱 의존성(`node_modules`) — 호스트에 npm 이 없으면 설치기가 만들지 못합니다. 디렉터리째 옮기거나 컨테이너로 `npm ci`.
- `/usr/local/bin` 의 **심볼릭 링크가 복사본**으로 바뀌는 문제 — 링크를 따라가는 복사(`cp -L`, `rsync -L`)를 쓰면 원본을 고쳐도 반영되지 않습니다. 비교에서 «구에만 l / 신에만 f» 로 보입니다.

### 2. 입력이 없으면 빈 상태로 덮어쓰는 도구
공개 동기화 도구가 헬퍼를 찾지 못하자 «앱 0개» 로 판단해 앱 설정을 **비웠습니다**. 설치 직후 타이머가 먼저 돌면 이런 일이 생깁니다.
- 타이머는 **마지막에** 켭니다. 켜기 전에 서비스를 한 번 수동 실행하고 결과(앱 수·설정 파일 크기)를 구 서버와 비교합니다.
- 동기화 대상 설정은 conf 그룹으로 옮겨 두었다가, 덮어써졌으면 다시 `mig-rsync.sh <그룹> --apply`.

### 3. 두 서버를 동시에 살리지 않는다
회원 컨테이너의 로그인 토큰·원격 접속(페어링) 신원·봇 토큰·수집 작업이 두 서버에서 **같습니다**. 동시에 돌면 세션이 서로 끊기고, 알림이 두 번 가고, 수집이 겹칩니다.
- 구 서버를 **완전히 정지**(정지 확인 통과)한 뒤에 신 서버에서 회원 컨테이너를 **만들고 시작**합니다. 생성과 시작은 별개입니다(`docker create` 만 하면 «Created»).
- 구 서버를 보관하는 동안 서비스를 다시 켜지 않습니다. 롤백할 때도 신 서버를 먼저 내립니다.

### 4. 숨은 가동 중 프로세스
루트 `docker ps` 가 비어도 끝이 아닙니다.
- **회원별 루트리스 도커** 컨테이너는 루트 도커에서 보이지 않습니다(`/run/user/<uid>/docker.sock`).
- 호스트에 상주하는 스크립트(재시작 가드·감시 루프)가 멈춘 컨테이너를 **다시 띄웁니다**. 먼저 그 스크립트를 멈추고(크론·유닛), 이름을 `EXTRA_PROC_PATTERNS` 에 넣습니다.
- `mig-stopcheck.sh` 가 `containerd-shim`(어느 도커든 떠 있는 컨테이너)·postgres·추가 패턴을 `ps` 로 봅니다.
- SQLite(WAL 모드) DB 는 쓰는 프로세스를 멈춘 뒤 `.db`·`-wal`·`-shm` 세 파일을 **함께** 옮깁니다(stop 그룹).

### 5. DB 디렉터리는 정상 종료 뒤에만
- 정지 후 `postmaster.pid` 없음, 로그의 «database system is shut down» 확인 → 최종 동기화(`--checksum`) → `verify` 일치.
- 신 서버 첫 기동 로그의 «database system was shut down at <시각>» 이 구 서버 정지 시각과 같아야 합니다. «was interrupted»·recovery 가 나오면 정상 종료본이 아닙니다.
- 밑그림(`--seed`)으로 옮긴 PGDATA 로는 절대 서비스를 띄우지 않습니다. PGDATA 를 옮겼다면 덤프 복원과 섞지 않습니다.
- 정지 `-t` 를 넉넉히(큰 DB 는 수 분) — 기본 10초면 강제 종료돼 정상 종료가 아닙니다.

### 6. uid/gid 는 번호로 옮겨진다
rsync `--numeric-ids` 는 숫자를 그대로 보존합니다.
- `caddy`·`docker` 같은 시스템 그룹은 설치 순서에 따라 **서버마다 번호가 다릅니다**. 구 서버의 caddy 그룹 번호가 신 서버에서는 docker 그룹이면, 비밀 폴더가 docker 그룹에 열립니다. 그룹 파일에 `groupmap=caddy`(이름) 를 두면 도구가 번호를 맞춥니다. 옮긴 뒤 `stat` 으로 확인.
- 회원 UID/GID 는 두 서버에서 **같게** 만듭니다(`mig-accounts.sh` 가 같은 번호로 생성, 다르면 멈춤). 루트리스 도커를 쓰면 `/etc/subuid`·`/etc/subgid` 범위도 같아야 data-root 의 파일 소유가 맞습니다.
- 회원 루트리스 운영 서비스를 관리자 compose 로 옮겨 통일할 때는, 컨테이너 안 프로세스가 쓰던 **매핑된 uid**(예: subuid 시작 + 컨테이너 uid)를 compose `user:` 로 명시해야 데이터 소유권이 유지됩니다. 이미지는 그 회원의 도커에서 `DOCKER_HOST=… mig-images.sh` 로 옮깁니다.

### 7. SSH 호스트 키와 접속 경로
- 신 서버가 구 서버의 호스트 키(`ssh-hostkeys` 그룹)를 승계하면 IP 교체 뒤 회원·자동화의 «호스트 키 변경» 경고가 없습니다.
- 대신 **이관 중** 신 서버의 기존 키를 기억한 경로(이관용 포트 포워딩, 점프 호스트)는 sshd 재시작 직후부터 «키 변경» 으로 접속이 막힙니다. 재시작 전에 열린 세션을 유지하고, 사용자 PC·자동화 쪽 `ssh-keygen -R "[호스트]:포트"` 계획을 세워 두세요.
- 운영 계정의 `known_hosts`·`authorized_keys`, root 소유 600 인 rclone 설정 같은 것은 별도 그룹(또는 병합)으로 옮깁니다. `authorized_keys` 를 통째로 덮어쓰면 신 서버의 이관 키가 지워져 전송이 끊깁니다.

### 8. 원격 IP 교체의 안전망
- 콘솔이 없으면 자동 원복 타이머가 유일한 안전망입니다. 각 단계 5분 안에 확정합니다.
- 공유기 포트 포워딩은 장비가 아니라 «대상 IP» 에 붙습니다 — IP 를 승계한 순간부터 포워딩이 신 서버를 가리킵니다(이관용 임시 포워딩은 반대로 구 서버를 가리키게 됩니다).
- 공유기의 IP-MAC 바인딩·DHCP 예약을 미리 확인합니다. 바인딩이 있으면 새 MAC 이 그 IP 를 못 씁니다.

### 9. 방화벽 규칙의 NIC 이름
nftables 규칙이 `iifname "enp5s0"` 처럼 NIC 이름에 고정돼 있으면, 신 서버 NIC 이름이 다를 때 규칙이 **오류 없이 아무것도 막지 못합니다**(국가 허용 목록이 열린 채가 됨). `mig-inventory.sh snapshot` 이 경고합니다.
- 이름을 고친 뒤 먼저 **시한 시험**: 적용 후 일정 시간(예: 90초) 뒤 자동으로 해제되게 걸고(`systemd-run --on-active=90s nft flush ruleset` 같은 원복 타이머), 그 사이 외부·관리자 접속을 확인한 다음 정식 적용합니다.

### 10. 인증서 저장소를 옮긴다
Caddy 데이터(`caddy-data`)를 옮기면 신 서버 첫 기동에서 ACME 재발급을 하지 않습니다(발급 한도·DNS 전파 문제를 피함). 소유자는 `usermap/groupmap=caddy` 로 맞추고, 필요하면 `chown -R caddy:caddy /var/lib/caddy/.local`.

### 11. 이미지 ID 가 다르게 보인다
도커 엔진·저장소 종류(루트 vs 루트리스, 기존 저장소 vs containerd 저장소)에 따라 `docker image inspect .Id` 가 config 해시일 수도, OCI 매니페스트(인덱스) 해시일 수도 있습니다. 같은 이미지인데 «불일치» 로 보일 수 있어, `mig-images.sh load` 는 저장 tar 의 `manifest.json` 에 적힌 Config 해시와도 비교합니다(«일치(config)»). 그래도 «확인 필요» 면 양쪽에서 `docker image inspect --format '{{json .RootFS.Layers}}'` 를 비교합니다.

### 12. 정지 시간 줄이기와 디스크 병목
- 시드 복사(가동 중) → 정지 → 최종 동기화(증분) 두 단계로 정지 시간이 «바뀐 양» 에 비례합니다. 다만 파일 수가 많으면 증분이어도 **목록 비교 시간**이 듭니다(백만 개 단위면 수십 분).
- 수백 GB 에서는 구 서버 디스크(HDD)가 병목입니다. 운영 부하로 이미 포화된 시간대를 피하고, 병렬 전송은 오히려 느려질 수 있습니다. `ionice` 는 `bfq` 스케줄러에서만 의미가 있습니다.
- 하드링크가 많은 폴더(백업 스냅샷 등)는 `du`·rsync 통계가 실제보다 크게 나옵니다. `-H` 로 하드링크는 보존됩니다.

### 13. 크론·타이머와 부작용 있는 작업
- 신 서버의 크론·타이머는 **승인 후** 복원합니다. 외부 수집·웹훅 알림·외부 업로드처럼 부작용이 있는 작업은 «재개 승인» 단계로 분리하고, 정지 표식으로 막아 둔 채 옮깁니다.
- 공개 서비스는 IP 교체 전에 `curl --resolve` 로 내부 시험합니다.

### 14. 실행 중인 스크립트를 덮어쓰지 않는다
bash 는 스크립트를 실행하면서 읽어 들이므로, 오래 걸리는 전송 중에 같은 파일을 고치면 끝에서 문법 오류가 납니다. 이 도구들은 본문을 함수로 감싸 처음에 다 읽습니다. 직접 만든 보조 스크립트도 같은 방식으로 쓰세요.

---

## 📝 한계와 미검증

- **가짜 ssh·rsync·docker 로 분기 시험만 했습니다**(`tests/migrate_live_test.sh`). 이 도구 묶음 자체를 실제 두 서버 사이에서 실행해 보지는 않았습니다. 바탕이 된 이관 도구(조직 내부용)는 실제 이관에 썼지만, 이 판은 설정 파일 기반으로 새로 쓴 것입니다. 첫 사용 전에 작은 그룹으로 시험 실행 → `--apply` → `verify` 를 확인하세요.
- rsync 3.2.3 미만(`--mkpath` 없음)은 지원하지 않습니다. 원격 수신 계정에 비밀번호 없는 `sudo rsync` 가 필요합니다.
- 그룹 옵션의 패턴에는 공백을 쓸 수 없습니다.
- `conf` 그룹의 `verify` 는 신 서버에만 있는 파일을 세지 않습니다.
- `mig-images.sh` 의 «일치(config)» 판정은 저장 tar 의 manifest.json 형식(기존 docker save · OCI 레이아웃)에 기대며, 두 엔진이 모두 매니페스트 해시로 ID 를 보이는 경우는 수동 확인이 필요합니다.
- `mig-containers.sh` 는 흔한 설정(이미지·재시작·user·네트워크·바인드/이름 있는 볼륨·포트·env·entrypoint/cmd)만 옮깁니다. capabilities·devices·GPU·로그 드라이버·헬스체크·라벨은 옮기지 않습니다 — 생성된 스크립트를 검토하세요.
- IP 교체는 netplan(Ubuntu) 고정 IP 만 지원합니다. DHCP·NetworkManager 는 대상이 아닙니다.
- 계정 이관은 회원 계정(passwd/shadow/group·subuid)만 다룹니다. 회원 컨테이너·DB 역할·SFTPGo 계정은 데이터 복사와 신 서버 도구로 되살립니다.
