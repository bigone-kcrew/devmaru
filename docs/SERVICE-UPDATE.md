# 서비스 개별 갱신 — `<접두어>-service-update`

킷 전체 갱신(`<접두어>-update`)과 별개로, **compose 서비스 하나(또는 전부)를 안전하게 갱신**하는 도구입니다. 서비스마다 백업 → 이미지 받기·빌드 → 올리기 → 헬스 확인을 하고, 실패하면 이전 이미지·설정으로 되돌립니다.

```bash
sudo <접두어>-service-update                      # 대상 서비스 이름 목록
sudo <접두어>-service-update kordoc               # = --plan: 무엇을 할지만 보여 줌(기본, 아무것도 바꾸지 않음)
sudo <접두어>-service-update --all --check        # 실행 중인 이미지와 compose 가 가리키는 이미지가 다른지·헬스만 점검(읽기 전용)
sudo <접두어>-service-update kordoc --apply       # 실제 갱신
sudo <접두어>-service-update --all --apply        # 모듈 순서대로 하나씩, 첫 실패(롤백 완료)에서 멈춤
```

## 대상
`/etc/<접두어>/site.env` 의 `MODULES` 에 있는 모듈 중 종류가 compose 인 것(필수 모듈 postgres 포함). 호스트 구성요소(caddy·golden·portal 등)는 대상이 아닙니다 — 이쪽은 `<접두어>-update` 가 다룹니다.

## 무엇을 하는가 (`--apply`)
| 단계 | 내용 |
|---|---|
| 1. 백업 | `/var/backups/<접두어>/service-update/<시각>/<서비스>/` 에 compose 디렉터리 tar ·<br>서비스 env · `/srv/<접두어>/services/<서비스>/data`(있으면) tar ·<br>**postgres 는 `pg_dumpall` 덤프** · 현재 이미지에 `<접두어>-rollback/<서비스>:<시각>` 태그 |
| 2. 이미지 | 빌드 서비스는 `build --pull`, 그 외는 `pull`, postgres 는 설치 서버에서 다시 빌드 |
| 3. 올리기 | `docker compose up -d --no-build` |
| 4. 헬스 | 컨테이너가 healthy(헬스체크 없으면 running)가 될 때까지, modules.list 의 대기 시간만큼 |
| 5. 실패 시 | compose 디렉터리 복원 → 이전 이미지 태그를 원래<br>이름으로 되돌림 → `up -d --force-recreate` → 헬스 재확인 |

갱신할 내용(새 이미지 태그)은 보통 `<접두어>-update` 로 새 킷을 받은 뒤 compose.yml 에 반영되어 있거나, 관리자가 compose.yml 의 태그를 직접 고친 것입니다. 같은 태그의 새 빌드(재빌드·`:latest` 류)도 받습니다.

## 한계
- **롤백은 compose 설정과 이미지만 되돌립니다.** 성공(5/5)할 때마다 compose 디렉터리를 `/var/backups/<접두어>/service-update/last-good/<서비스>.tar` 로 저장해 두고, 올린 뒤 헬스가 실패하면 그것으로 compose 를 복원한 다음 실행 중이던 이미지로 다시 올립니다(compose 의 image 줄이 롤백 전 실행 이미지와 다르면 그 줄도 되돌려 씁니다). 그래서 관리자가 compose.yml 의 이미지 태그나 healthcheck 를 바꿔 올린 뒤 헬스가 실패해도 이전 상태로 돌아갑니다. 실패한 변경은 `compose.yml.failed-<시각>` 으로 남겨 두니 원인을 확인하세요.
  - **last-good 이 없는 첫 실행**(이 서비스를 이 도구로 한 번도 성공시키지 않은 경우)에는 compose 의 이미지 줄만 되돌립니다. healthcheck·포트 같은 다른 변경은 되돌리지 못하니 `failed-` 파일과 백업의 `compose-dir.tar` 로 직접 확인하세요.
  - 되돌리는 대상은 서비스의 대표 컨테이너(`modules.list` 의 컨테이너) 이미지 하나입니다. compose 가 변수(`${...}`)로 이미지를 적은 경우 줄을 찾지 못해 안내만 하고 되돌리지 못합니다.
  - env 파일(`config/env/<서비스>.env`)은 되돌리지 않습니다(백업에만 있음).
- **DB 데이터와 서비스 데이터 디렉터리는 자동으로 되돌리지 않습니다**(되돌리면 롤백 사이의 쓰기가 사라질 수 있음). 실패 메시지에 복원 명령이 나옵니다: `zcat <백업>/pg_dumpall.sql.gz | docker exec -i postgres psql -U postgres`.
- uptime-kuma·n8n 의 데이터 tar 는 서비스가 켜진 채로 만들어 SQLite 가 일관되지 않을 수 있습니다. 중요한 시점이면 서비스를 멈추고 따로 백업하세요.
- 헬스는 `modules.list` 의 대표 컨테이너 하나만 봅니다(예: crawl4ai 의 게이트웨이 컨테이너는 따로 확인).
- `--all` 중 앞 서비스가 성공한 뒤 뒤 서비스가 실패하면 앞 서비스는 새 버전으로 남습니다.
- 롤백 태그(`<접두어>-rollback/*`)와 백업은 자동으로 지우지 않습니다. 확인 후 `docker rmi` · 백업 폴더 삭제.

## agent 모듈 sudo 허용 목록 — 제안(코드는 수정하지 않았음)
에이전트 계정은 읽기성 명령만 sudo 로 허용됩니다. 읽기 전용인 형태만 후보로 제안합니다.
```
<접두어>-service-update --plan
<접두어>-service-update --check
<접두어>-service-update * --plan
<접두어>-service-update * --check
```
`--apply` 는 넣지 않습니다. 주의: sudoers 와일드카드 `*` 는 뒤에 인자를 더 붙일 수 있어(`... --check --apply`) 그대로는 안전하지 않습니다. 도입하려면 서비스 이름별로 정확한 줄(`... kordoc --check`)을 나열하거나, 도구가 `--apply` 와 `--plan/--check` 가 함께 오면 거부하도록 먼저 고쳐야 합니다.
