# 접근 정책 (workspace · 공유 공간)

> 회원별 workspace 와 공유 공간의 **읽기·쓰기 권한을 관리자가 정합니다.**
>
> 처음 설치할 때 정하고, 나중에 `<접두어>-access` 명령으로 바꿀 수 있습니다.
>
> 기본값은 «내 workspace 는 나만, 공유 프로젝트는 회원 전원 읽기·쓰기» 입니다.

---

## 정책 한눈에 보기

| 설정 | 선택지 | 뜻 |
|---|---|---|
| `WORKSPACE_OTHERS` | `none` (기본) | 다른 회원은 내 workspace 를 **읽을 수도, 쓸 수도 없습니다** |
| | `read` | 다른 회원이 내 workspace 를 **읽을 수 있습니다** (쓰기는 항상 불가) |
| `SHARED_DEFAULT` | `rw` (기본) | 공유 프로젝트(`/shared/workspaces/…`)에서 회원 전원이 읽고 씁니다 |
| | `ro` | 회원 전원이 **읽기만** 합니다. 쓰기는 **만든 사람과 관리자**만 |
| 프로젝트별 | `--readers` · `--writers` | 프로젝트를 만들 때 따로 지정 (아래 «프로젝트별 접근») |

> **다른 회원의 workspace 쓰기는 어떤 설정에서도 허용되지 않습니다.**

---

## 어디서 정하나요

| 시점 | 방법 |
|---|---|
| **설치할 때 (터미널)** | 질문에 답합니다 — «다른 회원이 내 workspace 를 읽게 할까요?» ·<br>«공유 프로젝트를 읽기 전용으로 할까요?» (Enter = 기본값) |
| **설치할 때 (웹 화면)** | «고급 설정» 의 두 선택 상자 |
| **설정 파일** | `/etc/<접두어>/site.env` 또는 `--config`<br>파일에 `WORKSPACE_OTHERS=read` · `SHARED_DEFAULT=ro` |
| **설치한 뒤** | `sudo <접두어>-access set …` → `sudo <접두어>-access apply --all` |

---

## `<접두어>-access` 명령 (관리자, root)

| 명령 | 하는 일 |
|---|---|
| `status` | 현재 정책과 실제 권한을 비교해 **어긋난 곳**을 알려 줍니다 |
| `set workspace-others none\|read` | 정책 값을 바꿉니다 (아직 적용하지는 않습니다) |
| `set shared rw\|ro` | 공유 프로젝트 기본 권한을 바꿉니다 |
| `apply [회원\|--all]` | 기존 회원·공유 공간에 정책을 적용합니다. 인자를 생략하면 `--all` |
| `apply … --plan` | **아무것도 바꾸지 않고** 무엇을 바꿀지만 보여 줍니다 |
| `apply … --full` | 폴더 안쪽 전체까지 바꿉니다 (무겁습니다 — 아래 참고) |
| `verify [회원]` | 실제 회원 계정으로 접근 가능 여부를 확인합니다 |

관련 명령: 복구는 `<접두어>-restore`, 서버 이관은 `<접두어>-migrate`, 서비스 개별 갱신은 `<접두어>-service-update`, 방화벽은 `<접두어>-firewall`, AI 에이전트 계정은 `<접두어>-agent-key`·`agent-setup`·`agent-audit` (`sudo <접두어>-help` 에 한 줄씩 있습니다).

- 새 회원을 등록하면(`<접두어>-member-add`) 같은 정책이 **자동으로** 적용됩니다.
- `apply` 는 여러 번 실행해도 결과가 같습니다(멱등). 되돌리려면 값을 되돌리고 다시 `apply` 합니다.
- `<접두어>-doctor` 도 정책이 실제 권한과 맞는지 한 줄로 점검합니다.

### `--full` 이 필요한 경우

기본 `apply` 는 **최상위 폴더와 «앞으로 만들 항목»의 기본 권한**만 바꿉니다. 이미 있는 프로젝트의 안쪽 파일은 그대로입니다.

| 상황 | 필요한 것 |
|---|---|
| 새 프로젝트·새 파일 | 기본 `apply` 로 충분 (기본 권한을 상속) |
| **이미 있는 프로젝트 안쪽**까지 바꾸기 | `apply --full` |

큰 workspace 를 통째로 훑으면 서버 부하가 올라갑니다. 부하가 높으면 `--full` 은 경고를 표시하고, 낮은 우선순위(`nice`·`ionice`)로 실행합니다. **부하가 낮을 때 회원 한 명씩** 실행하는 것을 권합니다.

---

## 예시: 읽기 가능 → 읽기 불가로 바꾸기

과거 AI Club 이 «다른 회원 읽기 가능»에서 «읽기 불가»로 바꿨던 것과 같은 절차입니다.

```bash
sudo <접두어>-access set workspace-others none      # 1) 정책 값 바꾸기
sudo <접두어>-access apply --all --plan             # 2) 무엇이 바뀔지 미리 보기 (아무것도 바뀌지 않음)
sudo <접두어>-access apply --all                    # 3) 최상위·기본 권한 적용
sudo <접두어>-access apply alice --full             # 4) 기존 프로젝트 안쪽까지 (부하가 낮을 때, 회원 한 명씩)
sudo <접두어>-access verify                         # 5) 실제 계정으로 확인
```

반대로 읽기를 열려면 1)번을 `set workspace-others read` 로 바꾸면 됩니다.

> **`.private` 폴더는 어떤 정책에서도 열리지 않습니다.**
>
> 프로젝트 안의 `.private/`(700)는 비밀·개인정보용입니다. `read` 정책과 `--full` 에서도 건너뜁니다.

---

## 프로젝트별 접근 (공유 프로젝트)

공유 프로젝트를 만들 때 이 프로젝트만 다르게 정할 수 있습니다.

```bash
<접두어>-workspace-create team-notes --shared                                   # 기본(SHARED_DEFAULT 를 따름)
<접두어>-workspace-create budget --shared --readers=all --writers=alice,bob      # 모두 읽기, alice·bob 만 쓰기
<접두어>-workspace-create secret --shared --readers=bob --writers=bob            # bob 만 읽기·쓰기 (만든 사람 포함)
```

| 옵션 | 값 | 기본 |
|---|---|---|
| `--readers` | `all` 또는 `ID,ID` — 읽을 수 있는 회원 | `all` |
| `--writers` | `all` 또는 `ID,ID` — 쓸 수 있는 회원 | `SHARED_DEFAULT` 가 `rw` 면<br>readers 와 같음, `ro` 면 없음 |

- 만든 사람과 관리자는 항상 쓸 수 있습니다.
- 프로젝트별로 정한 프로젝트는 `apply` 가 **건너뜁니다**(`.<접두어>-access` 파일로 표시). 정책을 바꿔도 이 프로젝트는 그대로입니다.
- 회원 이름은 관리자가 `apply` 로 갱신하는 회원 목록에서 찾습니다. 새 회원은 등록하면 자동으로 들어갑니다.

---

## 세 겹이 같이 맞춰집니다

| 층 | 무엇 | 정책이 `ro`·`read` 일 때 |
|---|---|---|
| **폴더 권한(ACL)** | 회원 workspace · 공유 `/shared/workspaces/*` | 그룹 권한과 «앞으로 만들 항목»의 기본 권한을 바꿉니다.<br>공유 루트는 새 항목 생성을 막고, `/shared/workspaces` 는<br>프로젝트를 만들 수 있되 **남의 프로젝트는 지울 수 없습니다**(sticky) |
| **파일 서비스(SFTPGo)** | 회원 사용자 권한 | `ro` 면 `/shared` 는<br>**목록·내려받기만** (업로드는 403).<br>새 회원도 같은 권한으로 만들어집니다 |
| **Windows 공유(Samba)** | `[shared]` | `ro` 면 `read only = yes`<br>+ 관리자만 쓰기.<br>SMB 모듈이 없으면 건너뜁니다 |

---

## 알아 두세요 (한계)

- **컨테이너 안에서도 정책이 적용됩니다.**
  - `WORKSPACE_OTHERS=read` 이면 다른 회원의 workspace 가 컨테이너 안 `/members/<회원>` 에 **읽기 전용(`:ro`)** 으로 보입니다. `none` 이면 `/members` 는 없습니다.
  - 마운트하는 것은 다른 회원의 **workspace 폴더뿐**입니다(agent-config·tmp·홈은 아님). 읽기 전용 마운트라 쓰기 경로는 없고, 읽는 범위는 폴더 ACL 이 한 번 더 정합니다(`.private` 는 닫힘).
  - `SHARED_DEFAULT=ro`·`--readers`·`--writers` 는 별도 마운트 없이 `/shared` 의 폴더 ACL 이 컨테이너 안(같은 uid·그룹)에서 그대로 적용됩니다.
  - **이미 있는 컨테이너는 다시 만들어야 반영됩니다**: `access apply` 뒤 `sudo <접두어>-member-update-all`. 새 회원이 생겨도 기존 회원 컨테이너에는 재생성 전까지 `/members/<새 회원>` 이 없습니다. `access status` 가 어긋난 컨테이너를 알려 줍니다.
- **`SHARED_DEFAULT=ro` 에서 파일 서비스(웹·SFTP)로는 쓸 수 없습니다.** 만든 사람이 쓰는 경로는 자기 개발 컨테이너와 SSH 입니다. 프로젝트별 `--writers` 도 같습니다.
- **이 정책은 보안 경계가 아닙니다.** 폴더 권한 설정일 뿐이므로 비밀·키는 계속 프로젝트의 `.private/`(700)에 두세요.
- **Golden 이미지에 들어 있는 `<접두어>-workspace-create` 는 이미지를 다시 빌드해야 새 동작(정책 따르기, `--readers/--writers`)을 씁니다.** 기존 회원 컨테이너는 `<접두어>-member-update-all` 로 새 이미지를 받습니다.
- Samba 설정 변경은 설정 파일 수정과 `smbcontrol reload-config` 까지입니다. 실제 SMB 접속(QUIC 포함)은 이 문서의 시험 범위 밖입니다.

---

## 문제 해결

| 증상 | 확인 |
|---|---|
| `status` 에 «어긋난 곳» | `sudo <접두어>-access apply --all` 로 다시 맞춥니다 |
| 정책을 바꿨는데 기존 프로젝트 안쪽이 그대로 | 기본 `apply` 는 최상위만입니다 → `apply <회원> --full` |
| 새 프로젝트가 정책과 다르게 만들어짐 | Golden 이미지가 옛 버전일 수 있습니다 → 이미지 재빌드 · `member-update-all` |
| `--readers` 에 «회원을 찾을 수 없습니다» | 이름 오타이거나 회원 목록이 낡았습니다 → 관리자가 `apply --all` |
| 파일 서비스에서만 쓰기가 막힘 | `SHARED_DEFAULT=ro` 이면 정상입니다. `sudo <접두어>-access status` 로 정책 확인 |
