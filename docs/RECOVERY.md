# 복구 · 이관

> 백업(restic)에서 되돌리는 `<접두어>-restore` 와, 다른 서버로 옮기는 `<접두어>-migrate` 를 설명합니다.
>
> 둘 다 **데이터를 덮어쓰는 명령**이라 AI 에이전트 계정의 비밀번호 없는 sudo 목록에 들어 있지 않습니다. 사람이 직접 실행합니다.

- [복구 — `<접두어>-restore`](#복구)
- [이관 — `<접두어>-migrate`](#이관)
- [한계와 아직 확인하지 못한 것](#한계와-미검증)

---

## 복구

백업은 `sudo <접두어>-backup-run`([운영 가이드](OPERATIONS.md#6-백업))이 만든 restic 스냅샷을 씁니다.

```bash
sudo <접두어>-restore list                       # 스냅샷 목록(종류 DR 인 것이 복원 대상)
sudo <접두어>-restore plan all                   # 무엇이 바뀌는지만 표시(아무것도 바꾸지 않음) — 기본 동작
sudo <접두어>-restore apply db                   # 실제 복원: 승인 문구를 입력해야 시작
sudo <접두어>-restore apply config --snapshot <ID> --yes     # 문구 입력 없이(자동화)
```

| 범위 | 되돌리는 것 |
|---|---|
| `db` | 서비스 DB 덤프(n8n · 회원 DB — `pg_restore --clean`) · SFTPGo DB · n8n 데이터 폴더. 기본 `postgres` DB 와 DB 역할(globals)은 건드리지 않습니다. |
| `config` | `/etc/<접두어>`(site.env 포함) · 비밀 · `/opt/<접두어>/config/env/*.env` · 설정 폴더(mcp-tokens 등) |
| `members` | 회원 메타(`/opt/<접두어>/config/members`). 회원 목록은 표시만 합니다(계정·컨테이너는 되살리지 않음). |
| `all` | 위 전부 |

진행 순서는 항상 **서비스 정지 → 복원 → 서비스 기동 → `<접두어>-doctor`** 입니다(실행 중이던 서비스만 다시 올립니다. PostgreSQL 은 복원에 필요하므로 켜 둡니다).

- **복원 전 보관:** 바뀌는 파일은 같은 자리에 `<이름>.bak.<날짜>` 로 남고, DB 는 `/srv/<접두어>/backups/pre-restore.<날짜>/postgres/` 에 덤프로 남습니다. 복원이 마음에 안 들면 그것으로 되돌립니다.
- **비밀·env 비교:** 내용은 화면에 내지 않고 파일마다 «동일 / 다름 / 새로 만듦» 만 보여 줍니다. 비밀이 없는 `site.env` · `dev-container.env` · `platform.env` 만 줄 단위 차이를 보여 줍니다.
- **무결성:** 스냅샷에 들어 있는 `STAGE-SHA256SUMS` 로 꺼낸 파일을 검사하고, 맞지 않으면 복원하지 않습니다.
- **DB 역할 암호:** 설정(`postgres.env`)을 복원하면 DB 역할(postgres · n8n)의 암호를 복원된 env 값에 맞춥니다(값은 출력하지 않음).
- 승인 문구는 `복원 <접두어> <범위>` 입니다(`--yes` 로 생략 가능, 비대화형이면 `--yes` 필수).

> 복원 전에 **지금 상태의 백업을 한 번 더** 만들어 두면 안전합니다(`sudo <접두어>-backup-run`).

---

## 이관

옛 서버의 설정과 데이터를 새 서버로 옮깁니다. **새 서버에는 같은 접두어 · 같은 킷 버전으로 먼저 설치**해 두세요(Golden 이미지·네트워크·서비스가 준비되어 있어야 합니다).

```bash
# 옛 서버
sudo <접두어>-migrate export --passfile /root/migrate.pass       # 암호 파일이 없으면 새로 만들어 0600 으로 저장
#   → /srv/<접두어>/backups/migrate-<접두어>-<호스트>-<날짜>.mig (암호화 묶음 1개)

# 묶음과 암호 파일을 새 서버로 옮긴다(서로 다른 경로로) 
# 새 서버
sudo <접두어>-migrate import 묶음.mig --passfile /root/migrate.pass            # 기본: --plan (점검 + 계획만)
sudo <접두어>-migrate import 묶음.mig --passfile /root/migrate.pass --apply    # 승인 문구 입력 후 적용
```

- **묶음 내용:** `site.env` · 비밀 · env · 모든 PostgreSQL DB 덤프 · 회원 메타 · SFTPGo DB · n8n 데이터 · compose `.env` · 회원 uid/gid 목록. tar 로 묶어 **gpg 대칭 암호(AES256)** 로 암호화합니다(우분투 기본 포함). 암호는 `--passfile` 이나 입력 프롬프트로만 받고 화면에 출력하지 않습니다.
- **import 점검:** 접두어 · 킷 버전 · Golden 이미지 태그가 하나라도 다르면 **중단**합니다. 도메인·모듈이 다르면 경고합니다.
- **site.env 는 기본으로 새 서버 값을 유지**합니다(도메인·IP·포트가 다를 수 있으므로). 묶음 값으로 덮으려면 `--with-site-env`. 차이는 계획에 표시됩니다.
- **적용 순서:** 서비스 정지 → 복원 → 기동 → doctor (`<접두어>-restore apply all --from-dir` 이 수행).
- **회원 workspace 같은 대용량은 묶음에 없습니다.** export 가 크기와 함께 안내하는 명령으로 따로 옮깁니다.

  ```bash
  sudo rsync -aHAX --numeric-ids --info=progress2 <옛서버>:/srv/<접두어>/users/  /srv/<접두어>/users/
  sudo rsync -aHAX --numeric-ids --info=progress2 <옛서버>:/srv/<접두어>/shared/ /srv/<접두어>/shared/
  ```

  먼저 서비스를 켠 채 한 번 옮겨 두고, 이관 당일 서비스를 멈춘 뒤 같은 명령을 다시 실행하면 바뀐 것만 옮겨집니다.
- **회원 계정:** 리눅스 계정·컨테이너는 묶음으로 되살리지 않습니다. 새 서버에서 `sudo <접두어>-member-add <ID>` 로 만든 뒤 `import --apply` 를 다시 실행하면 그 회원 DB 가 복원됩니다. 회원 uid/gid 가 옛 서버와 같아야 rsync 한 파일의 소유권이 맞으므로, 묶음 안 `accounts/passwd.txt` 와 비교하세요.
- 최종 이관 때는 export 전에 쓰기가 많은 서비스(n8n·SFTPGo)를 멈추면 덤프가 한 시점으로 맞습니다.

---

## 한계와 미검증

**한계(설계상 하지 않는 것)**

- 복구는 **DR 스냅샷**(`<접두어>-backup-run` 이 만든 것)만 대상입니다. 이미지 보관본(`--images`)은 복원하지 않습니다.
- 리눅스 계정·회원 컨테이너·Caddy 인증서·Golden 이미지는 되살리지 않습니다(새 서버에서 설치기·member-add 가 만듭니다).
- 기본 `postgres` DB 와 DB 역할 정의(globals)는 복원하지 않습니다. 회원 DB 가 새 서버에 없으면 건너뜁니다.
- 회원 workspace·대용량 DB(별도 DB 컨테이너 등 킷 밖 데이터)는 묶음에 없습니다. rsync 안내만 합니다.
- PostgreSQL 주 버전이 다른 서버로는 덤프 복원이 되지만 시험하지 않았습니다.
- 복원 중에는 서비스가 잠시 멈춥니다. 회원이 적은 시간대에 하세요.

**미검증**

- **`<접두어>-restore` · `<접두어>-migrate` 는 아직 실제 설치된 서버에서 실행해 보지 않았습니다**(문법 검사·킷 렌더링 점검만 통과). 첫 사용 전 시험 서버에서 백업 → 변조 → 복원 리허설을 하세요. 이 문서의 시험 결과 문구는 리허설 뒤 갱신해야 합니다.
- 실제 두 서버 사이의 이관(도메인·IP 가 다른 경우, 회원이 많은 경우, 대용량 rsync)은 시험하지 않았습니다. 
- `members` 범위의 «회원 계정 재생성» 은 자동화하지 않았습니다(안내만).
- 도메인이 다른 서버로 옮길 때 복원된 env 속 호스트 값(n8n.env 의 `N8N_HOST` 등)을 자동으로 고치지 않습니다.
- smb · mail 등 선택 모듈의 상태(Samba 암호 DB 등)는 이관 대상이 아닙니다.
