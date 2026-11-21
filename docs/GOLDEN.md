# 🧑‍💻 Golden 이미지 운영

Golden 은 회원 개발환경 컨테이너가 쓰는 이미지(`<접두어>-dev:<버전>`)입니다. 두 가지 흐름이 있습니다.

| 흐름 | 누가 | 언제 |
|---|---|---|
| **단발 빌드** (기본) | 설치기 · `sudo <접두어>-update` | 킷이 정한 버전으로 한 번 빌드 — 설치 단계 60 |
| **운영자 흐름** | 서버 관리자(사람) | 업스트림 도구(Claude Code · Codex …)의 새 버전을 검증해 직접 올릴 때 |

운영자 흐름을 쓰지 않아도 서버는 정상 동작합니다.

## 버전과 포인터

- 이미지 버전은 킷 버전과 **따로** 셉니다: `/opt/<접두어>/images/dev/GOLDEN_VERSION`(킷의 `golden/GOLDEN_VERSION`). 킷 개발자는 Golden 소스가 바뀔 때만 올립니다. 파일이 없으면 킷 VERSION 을 씁니다(옛 설치와의 호환).
- 회원 컨테이너가 쓰는 이미지는 **포인터** 한 줄이 정합니다: `/opt/<접두어>/config/dev-container.env` 의 `GOLDEN_IMAGE=<접두어>-dev:<버전>`.
- 단발 빌드가 끝나면 포인터가 이전 킷 이미지를 가리킬 때만 새 이미지로 옮깁니다. 운영자가 `promote` 로 더 높은 버전을 올렸다면 그대로 둡니다.
- 한 서버에서는 한 방식을 기준으로 삼으세요. `rc` 는 서버의 `Dockerfile` 핀을 직접 고치는데, 다음 `<접두어>-update` 는 킷의 Dockerfile 로 덮어씁니다.

## 운영자 흐름

```bash
<접두어>-golden check                 # 1. 현황 + 업스트림 신버전 (읽기 전용, sudo 불필요)
sudo <접두어>-golden rc --plan        # 2. RC 계획만 보기 (아무것도 바꾸지 않음)
sudo <접두어>-golden rc [버전]        # 3. RC 빌드 → selftest → canary → 회차 검증 (수십 분)
<접두어>-golden progress <버전>       #    (다른 터미널에서) 진행 표시, 읽기 전용
sudo <접두어>-golden promote <버전> --plan   # 4. 승격 계획
sudo <접두어>-golden promote <버전>          #    승격: stable 태그 · manifest · 포인터
sudo <접두어>-member-update-all --check      # 5. 회원 컨테이너 갱신(승격과 별개)
sudo <접두어>-member-update-all
```

- `check` 종료 코드: 0 최신 · 10 업데이트 있음 · 1 조회 실패/현황 이상. 업스트림 조회는 공개 레지스트리(npm · GitHub · PyPI · NodeSource)이며 인터넷이 필요합니다. 단발 빌드만 한 서버에는 manifest 가 없으므로, manifest 가 하나도 없으면 경고 없이 넘어갑니다.
- `rc` 는 핀 숫자만 바꾸면 되는 항목(Claude Code · Codex · Paseo · Vercel · pnpm · Playwright · Bun · uv · Antigravity)만 채택합니다. ★major 는 노트를 읽고 `--with <이름>` 으로 명시하고, 서드파티 재료(superpowers · archify · agent-browser · ponytail · 커밋 핀)는 `golden/fetch-upstream.sh` 를 «손으로» 고칩니다. **여기서 멈춥니다** — 포인터·회원 컨테이너는 바뀌지 않습니다. 빌드 전에 `fetch-upstream.sh` 를 실행하고 음성 모델은 기본으로 뺍니다(포함하려면 `sudo GOLDEN_VOICE=1 <접두어>-golden rc …` — `GOLDEN_VOICE=1 sudo …` 는 sudo 가 변수를 지워 전달되지 않습니다).
- `rc` 가 만드는 것: Dockerfile 백업 `Dockerfile.pre-<버전>` · RC 이미지 `<접두어>-dev:<버전>-rc1` · 로그 `/tmp/build-<버전>-rc1.log`.
- `canary` 는 회원 데이터를 쓰지 않는 컨테이너 두 대로 기동·스킬·Paseo·MCP 등록을 봅니다. 기본은 임시 사용자 `canary`(호스트 계정 불필요). 특정 회원의 `~/.paseo/config.json` 보존까지 보려면 `sudo CANARY_USER=<회원> <접두어>-golden canary …`(Ubuntu 26.04 의 sudo 는 `-E` 를 무시합니다 — 변수는 sudo 뒤에 적습니다). 데이터는 `/srv/<접두어>/canary/<버전>` 에 만들어지고, 승격 뒤 `docker rm -f canary-<버전>-a canary-<버전>-b` 로 정리합니다.
- 회차 전용 검증: `releases/<버전>.checks`(실행 권한, 인자로 RC 이미지 태그). 킷이 `releases/1.2.0.checks` 를 기대값 예시로 싣습니다. 다음 회차에는 복사해 «이번에 새로 물어야 할 것» 만 고칩니다.
- `releases/` 는 설치 때 빈 디렉터리로 만들어지고, `promote` 가 `<버전>.manifest` 를 남깁니다. `promote` 는 `releases/<버전>.changes`(이번 회차 변경 내용, 자유 텍스트)를 manifest 에 넣으므로 **`rc` 가 끝난 뒤 사람이 먼저 적어 둡니다** — 없으면 `promote`(`--plan` 제외)가 멈춥니다.

## 롤백

포인터만 되돌리면 됩니다(이전 이미지는 지우지 않은 상태여야 합니다).

```bash
sudo sed -i 's|^GOLDEN_IMAGE=.*|GOLDEN_IMAGE=<접두어>-dev:<이전 버전>|' /opt/<접두어>/config/dev-container.env
sudo <접두어>-member-update-all
```

`promote` 는 포인터 백업 `dev-container.env.bak.<시각>` 도 남깁니다. 오래된 이미지 정리는 롤백이 필요 없다고 판단한 뒤에 합니다.

## AI 에이전트 sudo 허용 목록 (제안 — 코드는 바꾸지 않았습니다)

- 후보: **`<접두어>-golden check`** 하나뿐입니다(읽기 전용 · 아무것도 쓰지 않음). 사실 sudo 도 필요 없어 에이전트 계정이 그냥 실행할 수 있습니다(docker 접근이 있어야 로컬 이미지·컨테이너 현황이 보입니다).
- 넣지 않을 것: `rc`(Dockerfile 수정 · 수십 분 빌드 · 디스크 사용) · `promote`(포인터 이동) · `canary`/`selftest`(컨테이너를 만듦 — 필요하면 사람이 `rc` 로 실행) · `member-update-all`. `progress` 는 읽기 전용이지만 쓸 일이 드물어 제안하지 않습니다.
- `check` 를 허용한다면 인자 없는 정확한 명령줄과 `--json` 두 가지만 등록하세요.

## 한계

- RC 이미지·canary 는 디스크를 많이 씁니다(이미지 수 GB~수십 GB). 여유 60GB 이상을 권장합니다.
- canary 의 MCP 등록 확인은 `kordoc` · `markitdown` · `crawl4ai` 를 봅니다(해당 모듈을 설치하지 않았다면 FAIL 이 날 수 있습니다).
- 이 흐름은 VM 에서 `rc`(실빌드) → `promote` → 롤백 → `member-update-all` 까지 한 바퀴 시험했습니다. 실서버에서는 아직 시험하지 않았습니다.

## 사무 문서 도구(LibreOffice·한글 글꼴)

- 기본으로 이미지에 들어갑니다(Dockerfile 의 `INSTALL_OFFICE=1`, 설정 `GOLDEN_OFFICE`). 제외하려면 설정 파일에 `GOLDEN_OFFICE=0` 을 쓰고 이미지를 다시 빌드하세요.
- 버전은 고정하지 않습니다(Ubuntu 26.04 저장소 최신). 빌드 때마다 마이너 버전이 달라질 수 있습니다.
- 동시에 여러 변환을 돌릴 때는 작업마다 `-env:UserInstallation=file:///tmp/lo-<작업별 이름>` 을 따로 주세요(같은 프로필을 동시에 쓰면 둘째가 실패합니다 — 서버 시험 결과).
