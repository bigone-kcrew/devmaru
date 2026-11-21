### 추가
- `<접두어>-service-update <서비스>|--all [--plan|--check|--apply]`: compose 서비스를 하나씩 백업(DB 는 pg_dumpall)·이미지 받기/빌드·올리기·헬스 확인하고, 실패하면 이전 이미지·설정으로 롤백합니다. 기본은 `--plan`(변경 없음). 절차·한계: `docs/SERVICE-UPDATE.md`.
- `<접두어>-firewall plan|apply|status|confirm|rollback`: ufw 기본 구성(SSH·80/443·SMB·관리자 대역). 기본은 plan 만 보여 주며, apply 는 현재 SSH 접속 점검 후 적용하고 N초 안에 `confirm` 이 없으면 자동 롤백합니다. 설치기는 방화벽을 적용하지 않습니다. 설명: `docs/FIREWALL.md`.

### 제거
- 킷에 memory 서비스가 없어 호출 대상 MCP 가 없는 Golden 스킬 `memory-save` · `memory-forget` · `memory-status` 를 제거했습니다(Dockerfile 의 해시 인자·검증 단계 포함). 이미 설치된 서버는 `sudo <접두어>-update` 로 새 킷을 받으면 배포 단계(20-deploy)가 Golden 소스(`/opt/<접두어>/images/dev/skills`)의 세 스킬 폴더를 지우고(rsync 는 삭제를 하지 않으므로 명시적으로 지웁니다), Golden 이미지를 다시 빌드한 뒤(`<접두어>-member-update-all` 로 회원 컨테이너에 적용) 이미지에서 빠집니다. 재빌드 전의 이미지·실행 중인 회원 컨테이너에는 남아 있습니다.
