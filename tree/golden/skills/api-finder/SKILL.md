---
name: api-finder
description: 한국에서 활용 가능한 공공·민간 API를 폭넓게 탐색하고 비교할 때 사용한다. @@BRAND@@ 중앙 API Catalog를 검색해 사용자 의도에 맞는 후보를 찾고, 여러 검색어로 질의를 확장한 뒤 의미적으로 재정렬하며, 인증 방식과 최근 관측 상태를 구분해 설명한다. Use when the user asks to find, discover, compare, recommend, or identify APIs for a Korean service, integration, automation, AI feature, finance/payment, messaging, map, business, public-sector, or data use case. For authoritative deep searches limited specifically to data.go.kr, prefer public-data-finder.
---

# API Finder

한국에서 사용할 수 있는 공공·민간 API 후보를 @@BRAND@@ 중앙 API Catalog에서 탐색한다.

## Runtime

반드시 사전 설치된 중앙 검색기를 사용한다.

```bash
api-catalog-search <query> --json
```

검색 데이터는 다음 중앙 Catalog에서 읽는다.

```text
/opt/@@PFX@@/api-catalog/data/catalog.json
```

Skill 내부에 API 목록을 복제하거나 고정하지 않는다. 항상 현재 중앙 Catalog를 조회한다.

## Core workflow

1. 사용자 요청에서 실제 기능 의도를 파악한다.
2. 핵심 개념과 동의어를 2~6개의 짧은 검색어로 확장한다.
3. 각 검색어를 `api-catalog-search ... --json`으로 조회한다.
4. 결과를 `id` 기준으로 병합·중복 제거한다.
5. 문자열 일치 점수만 따르지 말고 사용자 의도에 맞게 의미적으로 재정렬한다.
6. 필요하면 `--mode all`, `--category`, `--auth`를 사용해 좁힌다.
7. 최종 후보를 3~7개 정도로 정리한다.
8. 실제 도입·호출·추천 판단이 필요하면 공식 제공기관 문서를 다시 확인한다.

## Query expansion

사용자의 긴 자연어 문장을 그대로 한 번만 검색하지 않는다.

예:

```text
사용자: 사업자 정보 조회 API 찾아줘

검색 후보:
- 사업자
- 사업자등록
- 사업자등록번호
- 기업정보
- 기업 조회
```

```text
사용자: 문자나 카카오 알림톡 발송 API

검색 후보:
- 문자
- SMS
- 알림톡
- 카카오
- 메시지
```

```text
사용자: 한국어 음성을 텍스트로 바꾸는 API

검색 후보:
- STT
- 음성인식
- 음성 텍스트
- speech
- 한국어 음성
```

짧은 검색어를 우선 사용하고, 너무 넓으면 `--mode all`이나 카테고리 필터로 좁힌다.

## Semantic reranking

Catalog 검색 점수는 후보 회수를 위한 lexical score다. 최종 적합성 점수로 취급하지 않는다.

예를 들어 "사업자 정보 조회"에서 "전기차 충전 사업자"가 문자열 일치로 검색되더라도, 사용자가 사업자등록 또는 기업정보를 찾는 상황이면 우선순위를 낮춘다.

반대로 서로 다른 검색어에서 반복적으로 나타나며 사용자의 실제 기능 요구를 직접 충족하는 후보는 우선순위를 높인다.

## Search commands

기본 검색:

```bash
api-catalog-search 사업자 --json
```

여러 단어 중 하나:

```bash
api-catalog-search 문자 알림톡 --mode any --json
```

모든 단어 일치:

```bash
api-catalog-search 문자 알림톡 --mode all --json
```

넓은 탐색이 꼭 필요한 경우에만:

```bash
api-catalog-search <query> --min-score 1 --json
```

기본 `--min-score`를 불필요하게 낮추지 않는다.

## Health interpretation

Catalog의 health 값은 최근 URL 관측 결과다.

```text
OBSERVED_AVAILABLE
```

은 최근 관측에서 응답을 얻었다는 의미이지 다음을 뜻하지 않는다.

- API 기능 전체가 정상이라는 공식 검증
- 신규 가입 또는 신규 키 발급 가능
- 무료 사용 가능
- 현재 가격·쿼터 확정
- 사용자가 요구하는 endpoint 동작 확인

```text
UNKNOWN
```

도 장애 또는 폐지를 뜻하지 않는다.

Health 값은 참고 정보로만 표현한다. 자세한 기준은 `references/verification-policy.md`를 따른다.

## Official verification

사용자가 단순히 "어떤 API가 있나"를 묻는 discovery 단계에서는 Catalog 결과로 후보를 제시할 수 있다.

다음 단계에서는 공식 제공기관 문서를 확인한다.

- 실제 도입 추천
- 현재 사용 가능 여부 확인
- 인증 방식 확정
- 가격·무료 구간·쿼터 확인
- endpoint 또는 SDK 사용법
- 가입/제휴 필요 여부
- 개인정보 또는 상업적 이용 조건
- 후보 간 실질 비교

공식 문서에서 확인하지 않은 내용을 확정적으로 말하지 않는다.

## Relationship with other @@BRAND@@ Skills

이 Skill은 broad discovery router다.

공공데이터포털 자체를 깊게 검색해야 하면:

```text
public-data-finder
```

를 우선한다.

Catalog에서 이미 전문 Skill이 있는 영역을 발견하면 그 Skill로 넘기는 것을 우선한다. 예:

```text
nts-business-registration
kosis-stats
bok-ecos-stats
k-dart
fsc-corporate-info
building-register-search
```

`api-finder`가 전문 Skill의 기능을 재구현하지 않는다.

## Output

후보별로 가능하면 다음을 정리한다.

- API/서비스명
- 사용자의 요구와 맞는 이유
- 분류
- Catalog에 기록된 인증 방식
- 최근 관측 상태
- 공식 URL
- 추가 검증이 필요한 사항

후보가 많으면 적합도 기준으로 3~7개만 보여주고, 왜 상위에 뽑았는지 간단히 설명한다.

검색 결과가 없으면 "API가 없다"고 단정하지 않는다. 검색어를 바꿔 다시 검색하거나 중앙 Catalog 범위 밖일 수 있음을 설명한다.

## Safety and secrets

조회·탐색 중심으로 동작한다.

- API 키, 토큰, 비밀번호를 답변이나 로그에 노출하지 않는다.
- 사용자의 명시적 요청 없이 가입, 활용신청, 유료 결제, 키 발급을 진행하지 않는다.
- Catalog에 있는 인증 문자열만으로 실제 인증 절차를 추정하지 않는다.

## References

Catalog 구조는 `references/catalog-architecture.md`를 참고한다.

공식 검증 및 health 해석은 `references/verification-policy.md`를 참고한다.

Upstream 및 라이선스는 `references/UPSTREAM-ATTRIBUTION.md`를 참고한다.
