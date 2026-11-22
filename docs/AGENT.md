# AI 에이전트 전용 계정 (`agent` 모듈, 1.2.0 초안)

> Claude Code · Codex 같은 에이전트가 서버를 **점검·계획 수준**으로 다루게 하는 선택 모듈입니다. **기본은 꺼짐**이며 설치할 때 `agent` 를 고른 경우에만 만들어집니다.

## 만들어지는 것

| | 내용 |
|---|---|
| 계정 | `<접두어>-agent` — SSH **공개키 전용**, 비밀번호 잠금, 만료일 설정 가능 |
| 키 | 관리자가 등록(`<접두어>-agent-key`). 키 파일은 root 소유(`/etc/<접두어>/agent-authorized_keys`)라 에이전트가 스스로 고칠 수 없음. 포트 포워딩 불가 |
| sudo | 아래 «허용 명령» 만 비밀번호 없이. 그 밖의 명령은 비밀번호를 물어 **사람 승인** 이 필요(에이전트는 비밀번호가 없음) |
| 감사 로그 | `/var/log/<접두어>/agent-audit.log` — sudo 저널 기록 중 에이전트 것만 모음(실행된 명령), 주 1회 회전(26주 보관) |

## 설치와 키 등록

```bash
# 설치할 때 agent 모듈 선택(터미널 질문·웹 화면의 체크박스·설정 파일의 MODULES). 만료일은 site.env 의 AGENT_EXPIRES=YYYY-MM-DD (선택)
sudo <접두어>-agent-key add ~/agent.pub          # 에이전트의 공개키(.pub 한 줄) 등록
sudo <접두어>-agent-key status                   # 등록된 키 지문 · 만료일
sudo <접두어>-agent-key expire 2026-12-31        # 만료일 바꾸기(never 는 만료 없음)
sudo <접두어>-agent-key remove <지문|주석>        # 키 해제
sudo <접두어>-agent-setup status                 # 계정 · sudoers · 로그 상태
sudo <접두어>-agent-setup remove                 # 계정 삭제(감사 로그는 남김)
```

이미 설치된 서버에 나중에 켜려면 `sudo <접두어>-agent-setup install [--expires YYYY-MM-DD]`.

## 허용 명령(비밀번호 없이)

정확한 명령줄만 허용합니다. 인자를 덧붙이면 허용되지 않습니다.

- `sudo <접두어>-doctor` · `sudo <접두어>-doctor --json`
- `sudo <접두어>-update --check` (확인만)
- `sudo <접두어>-access status` · `verify` · `apply --all --plan`
- `sudo <접두어>-backup-run` (인자 없이 — 백업 실행)
- **읽기 전용 점검(원격 관리·콘솔용, 1.3.0 선행)**: `sudo <접두어>-golden check` · `sudo <접두어>-member-update-all --check` · `sudo <접두어>-member-update-all --json`(회원 ID 없는 집계) · `sudo <접두어>-service-update --all --plan` · `--all --check` · `sudo <접두어>-maintenance status`(`--json`)

`member-remove` · `update`(적용) · `member-update-all`(인자 없음 = 전체 회원 컨테이너 재생성, `--json --members` = 회원 ID 출력) · `golden rc|promote` · `service-update --apply` · `rm` 등 파괴적·변경 명령은 목록에 없으므로 에이전트가 직접 실행할 수 없습니다. 에이전트에게 «이 명령을 승인해 주세요» 라고 말하게 하고 **관리자가 직접** `! sudo …` 로 실행하세요.

## 감사 로그

```bash
sudo <접두어>-agent-audit              # 최근 50줄
sudo <접두어>-agent-audit --tail 200
```

sudo 가 저널에 남기는 줄을 서비스(`<접두어>-agent-audit.service`)가 파일로 모은 것입니다(시각 · 계정 · 명령 · 허용 여부). **허용되어 실행된 명령**이 기록됩니다. 거부된 시도는 Ubuntu 26.04 의 sudo-rs 에서 sudo 가 기록하지 않아(실측) 이 로그에 나타나지 않습니다. 이 점을 염두에 두세요.

## 한계

- 에이전트는 SSH 로그인 뒤 일반 사용자 권한으로는 무엇이든 할 수 있습니다(허용 목록은 **sudo** 만 제한). 서버의 다른 일반 계정 권한에 주의하세요.
- 감사 로그는 sudo 로 **실행된** 명령 기록이며, 에이전트가 일반 사용자로 한 일은 기록하지 않습니다.
- 허용 목록을 바꾸려면 `<접두어>-agent-setup` 의 `ALLOW` 를 고치고 `install` 을 다시 실행합니다(sudoers 는 검증 실패 시 되돌립니다).
