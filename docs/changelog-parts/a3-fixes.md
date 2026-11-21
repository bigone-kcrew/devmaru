### 변경
- `<접두어>-golden rc`: 끝날 때 «승격 전에 `releases/<버전>.changes` 를 적어 둔다» 안내를 냅니다. 파일로 돌릴 때 출력 순서가 뒤섞이던 것(버퍼링)을 줄 단위 출력으로 바로잡았습니다.
- `<접두어>-golden promote`: 변경 내용 파일이 없을 때 오류 문구에 할 일을 적었습니다.
- `<접두어>-golden check`: 승격(manifest 생성) 뒤 단발 빌드 이미지로 롤백하면 «manifest 설치 안 됨» 경고와 종료 1 이 나던 것을 정상으로 처리합니다(있는 manifest 가 모두 더 높은 버전일 때).
- 문서(`docs/GOLDEN.md`): `.changes` 파일 절차 추가, Ubuntu 26.04 sudo 가 `-E` 를 무시하므로 `sudo CANARY_USER=… ` · `sudo GOLDEN_VOICE=1 …` 형태로 정정, VM 시험 범위 반영.
