# API Verification Policy

## Discovery vs verification

Keep two concepts separate.

### Catalog discovery

Catalog metadata is appropriate for:

- finding candidate APIs;
- identifying likely categories;
- seeing the authentication label recorded by the source catalog;
- observing the most recent URL-health state.

### Authoritative verification

Verify against the official provider before making current factual claims about:

- API availability;
- endpoint behavior;
- authentication procedure;
- account requirements;
- partnership requirements;
- price;
- free quota;
- rate limits;
- commercial-use terms;
- privacy/data-processing terms;
- SDK support;
- deprecation or migration.

## Health states

Health data represents observations, not authoritative service judgments.

`OBSERVED_AVAILABLE` means the latest observation obtained a successful-ish response according to the central checker.

It does not mean the API itself has been functionally verified.

`UNKNOWN` means the observation history is insufficient to make a useful state determination. It does not mean broken.

Transport failures may be temporary and can vary by time, provider, TLS configuration, network path, authentication requirement, or maintenance.

Never rewrite `UNKNOWN` as `BROKEN`, `DOWN`, or `DISCONTINUED` without separate authoritative evidence.

## Recommendation language

For discovery-only results, use language such as:

- "Catalog에서 후보로 확인됨"
- "최근 URL 관측 상태는 OBSERVED_AVAILABLE"
- "실제 도입 전 공식 문서 확인 필요"

After official verification, clearly distinguish the newly verified facts from the catalog metadata.
