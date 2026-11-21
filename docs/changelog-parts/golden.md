### 추가
- `<접두어>-golden check|rc|selftest|canary|promote|progress`: Golden(회원 개발환경) 이미지 운영 도구 6종. `check`(읽기 전용: 현황 + 업스트림 신버전 대조) → `rc`(RC 빌드 + selftest + canary + 회차 검증, 포인터·회원 컨테이너는 건드리지 않음) → `promote`(검증된 RC 를 stable 로 승격, 사람이 직접) → `<접두어>-member-update-all`. 단발 빌드(설치·`<접두어>-update`)는 그대로입니다. 흐름·롤백·에이전트 sudo 제안: `docs/GOLDEN.md`.
- `<접두어>-golden-canary` 는 `CANARY_USER=<회원>` 이 없으면 컨테이너 안에 임시 사용자 `canary` 로 시험합니다(호스트 계정 불필요).

### 변경
- Golden 이미지 버전을 킷 버전과 분리했습니다. 이미지 태그는 `golden/GOLDEN_VERSION`(서버에서는 `/opt/<접두어>/images/dev/GOLDEN_VERSION`)을 따르며, Golden 소스(Dockerfile 등)가 바뀔 때만 올립니다. 파일이 없으면 종전처럼 킷 VERSION 을 씁니다.
- `<접두어>-update` 가 새 Golden 이미지를 빌드하고 나면 `GOLDEN_IMAGE` 포인터가 이전 킷 이미지를 가리킬 때 새 이미지로 옮깁니다(종전에는 포인터가 처음 설치한 버전에 머물렀습니다). `promote` 로 더 높은 버전을 올린 서버는 건드리지 않습니다. 되돌리려면 `/opt/<접두어>/config/dev-container.env` 의 `GOLDEN_IMAGE` 를 이전 값으로 고칩니다.
- 주의: `rc` 가 서버의 Dockerfile 핀을 직접 고치므로, 이후 `<접두어>-update` 가 킷의 Dockerfile 로 덮어씁니다. 한 서버에서는 한 방식(킷 업데이트 또는 운영자 RC)을 기준으로 삼으세요.
