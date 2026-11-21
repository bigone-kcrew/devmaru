# Kordoc — filling forms and redaction

Read this before filling a form (including the built-in 기안문 templates) or redacting personal data.

## Fill forms

For @@BRAND@@ built-in public-office templates, no source HWPX file is required.

Supported built-in template names are:

```text
gian
gian-simple
일반기안문
간이기안문
```

Example:

```bash
kordoc-api fill   --template gian   --values values.json   --format hwpx   -o filled.hwpx
```

Use `gian-simple` or `간이기안문` when the simpler built-in form is appropriate.

When using an existing document as the form source, inspect the form first:

```bash
kordoc-api form-parse form.hwpx
```

Store fill values in a JSON file. Do not place sensitive values directly in shell command arguments.

Example structure:

```json
{
  "성명": "홍길동",
  "부서": "기획팀"
}
```

Fill while preserving an existing HWPX layout:

```bash
kordoc-api fill form.hwpx \
  --values values.json \
  --format hwpx-preserve \
  -o filled.hwpx
```

Prefer `hwpx-preserve` when modifying an existing HWPX form whose styles and layout should remain intact.

Use formatting rules through a JSON file:

```bash
kordoc-api fill form.hwpx \
  --values values.json \
  --formats formats.json \
  --format hwpx \
  -o filled.hwpx
```

Use `--require-unique` when a scalar input label matching multiple locations could fill the wrong field.

A repeated scalar label rejected by the uniqueness guard is reported as rejected. A label that cannot be matched is reported as unmatched.

Use `--mask-values` when filled values do not need to be exposed in response metadata:

```bash
kordoc-api fill form.hwpx \
  --values values.json \
  --mask-values \
  --format hwpx-preserve \
  -o filled.hwpx
```

`--mask-values` hides values from API/helper response metadata. It does not remove or redact the value inserted into the document.

For Markdown output:

```bash
kordoc-api fill form.hwpx \
  --values values.json \
  --format markdown
```

Never overwrite the source document.

## Redact sensitive data

Do not confuse form-fill masking with source-document redaction.

For document redaction, first perform a dry run:

```bash
kordoc-api redact input.hwpx \
  --rules rules.json \
  --dry-run
```

Use a JSON array for explicit rules, for example:

```json
[
  "rrn",
  "phone",
  "email"
]
```

Review hit counts and masked previews. Then create the redacted document:

```bash
kordoc-api redact input.hwpx \
  --rules rules.json \
  -o redacted.hwpx
```

Validate and re-parse HWPX redaction output.

Treat redaction as a security-sensitive operation. Do not expose original sensitive values in conversational output, logs, or shell arguments.
