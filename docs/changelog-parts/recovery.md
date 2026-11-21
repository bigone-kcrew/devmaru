### 복구·이관 도구 (1.2.0)

- 새 명령 `<접두어>-restore` — restic 스냅샷 목록(`list`), 계획만 보기(`plan`, 기본), 실제 복원(`apply db|config|members|all`, 승인 문구 또는 `--yes`). 복원 전 현재 상태를 `.bak.<날짜>`·DB 덤프로 보관하고, 서비스 정지 → 복원 → 기동 → `<접두어>-doctor` 순서로 진행합니다. 비밀·env 는 내용을 보이지 않고 «같음/다름/새로 만듦» 만 비교해 보여 줍니다.
- 새 명령 `<접두어>-migrate export|import` — 설정·비밀·DB 덤프·회원 메타·SFTPGo·n8n 데이터를 gpg 대칭 암호(AES256) 묶음 하나로 만들어 다른 서버로 옮깁니다. `import` 는 `--plan` 이 기본이고 접두어·킷·Golden 버전이 다르면 중단합니다. 회원 workspace 는 묶음에 넣지 않고 rsync 명령을 안내합니다.
- 두 명령 모두 파괴적이므로 AI 에이전트 sudo 허용 목록에 넣지 않았습니다.
- 문서: [복구·이관](docs/RECOVERY.md) (한계와 미검증 항목 포함).
