# Kordoc — compare, lint, validate, render, seals

Read this before comparing documents, linting notation and style, validating, rendering previews or region images, or placing seals.

## Compare documents

Use the helper:

```text
kordoc-api compare <fileA> <fileB> [--ocr <false|true|force>]
```

The result is under `result`. It compares two documents of any parsable format.

Use block/paragraph differences for document comparison and 신구대조 workflows.

Do not describe a comparison as legally authoritative unless that level of review actually occurred.

## Check notation and style (lint)

Use the helper to check Korean public-document notation (dates, times, amounts, attachments, symbols) against the administrative-work handbook rules:

```text
kordoc-api lint <file|-> [--munche <true|false>] [--strict]
```

- `<file>` is Markdown or plain text; `-` reads standard input. Fenced code blocks are skipped.
- `--munche true` also checks the gaejosik (bulleted report) style: narrative `~다` endings, imperatives, rhetorical questions, item length. Use it for report and plan drafts.
- The JSON result has `ok`, `errors`, `warnings` and the findings (`gongmun`, and `munche` when requested); each finding has `line`, `match`, `rule`, `severity`, `message` and usually `suggest`.
- `ok: false` only means that there is at least one error finding. It is a normal result (exit code 0). `--strict` exits with 1 when there is an error.
- Besides date, time, amount and symbol notation, lint (Kordoc 4.20.0+) also flags:
  - `RANGE_DASH` (warning): a period or time range written with a hyphen, such as `2026. 3. 1.-6. 30.`; the suggestion is the wave dash (`2026. 3. 1.∼6. 30.`, `14:00∼16:00`).
  - `WEEKDAY_MISMATCH` (**error**): the weekday does not match the date, such as `2026. 10. 9.(목)` (that day is a Friday).
  - Mismatch between an amount in digits and the same amount in Hangul (`MONEY_HANGUL_MISMATCH`), and two spaces after the closing `끝.` mark or after `붙임` (`END_MARK_SPACE`).
  - `PLAIN_LANGUAGE` (warning): easier public-language wording is recommended (`금번` → `이번`); the original is not wrong.
  - `SPELLING_ERROR` (warning): common misspellings such as `몇일` → `며칠`.
- A weekday error comes back as `ok: false` with HTTP 200, and `--strict` exits with 1. Fix the date or the weekday after checking the calendar, not by guessing which one is right.
- Lint is advice. It does not change the document. Apply the suggestions to the source, then lint again.

Full lint (central Kordoc 4.24+) with every check the official tool has, on a Markdown file, on text, or directly on a document (HWP, HWPX, PDF, DOCX, ...), or on blocks you supply:

```text
kordoc-api lint-full --file report.hwpx --slop true --logic true --numbers true
kordoc-api lint-full --text-file draft.md --munche true --gate true --preset 보고서
kordoc-api lint-full --blocks blocks.json --slop true
```

- Give exactly one of `--file`, `--text-file`, `--blocks`. `blocks.json` is an array of `{"id": "...", "text": "...", "table": {"id": "...", "row": 0, "col": 0}}` in document order (the `table` part is optional).
- `--slop` finds AI-style prose (conclusive filler, generic openers, empty buzzwords); `--logic` checks the structure of reports and plans (background, problem, measure, schedule, effect); `--numbers` cross-checks numbers in the body against the tables; `--budget` re-computes budget tables and calculation bases; `--gate` is the pre-approval gate: notation and style errors plus prose and structure findings make the result not ok (scope it with `--preset`, for example `보고서` or `개조식`).
- The result is JSON with a summary and findings. Findings are advice; fix the source and run it again. This command always prints the result (exit code 0 unless the request itself failed).

## Validate HWPX

Prefer:

```bash
kordoc-api validate output.hwpx
```

Validation checks package/XML consistency. Treat validation success as structural validation, not proof that every visual detail matches Hancom Office rendering.

## Render HWPX

Use the helper. It renders HWP/HWPX in the actual typeset layout:

```text
kordoc-api render-native <file> -o <output> [--format <png|jpeg|svg|html|pdf>] [--pages <range>] [--max-width-px <200-4000>] [--highlight <text>]... [--reflow-mode <keep|charAll>]
```

- `png` / `jpeg` (default png): raster image. Without `--pages` an HWPX is stacked into one tall image; with `--pages` each page is its own file. `svg`: one file for the whole HWPX without `--pages`. `html`: one self-contained layout HTML file. `pdf`: PDF printed by the central service's Chromium.
- When more than one file comes out, the names get a page suffix: `out.png` becomes `out_page_001.png`, `out_page_002.png`, and the result lists them under `outputs`.
- `--highlight <text>` (repeat it) marks the places where a search text occurs, for example the values you just filled or the sentences you edited; use it to check generated or patched output by eye.
- `--reflow-mode charAll` breaks lines per character instead of per word (the typesetting engine's reflow for documents without a Hancom layout cache; word wrap is the default).
- Documents saved by Hancom render exactly from their layout cache; AI-generated HWPX (no cache) is rendered by the reflow engine and is an approximation of Hancom's real typesetting. Treat it as a preview.

Region images from HWP/HWPX: `kordoc-api crop-regions <file> --target table --output-dir ./crops` writes the cropped region images (target: table, image, paragraph, shape) into the directory, and `kordoc-api extract-tables <file> --visual all --output-dir ./tables` also writes images of the tables chosen by `--visual`. Without `--output-dir` only the coordinates and metadata come back.

The older REST endpoint `POST /v1/document/render` still returns SVG for HWPX through the library renderer.

For Kordoc-generated HWPX or documents without a usable Hancom layout cache, use `reflow=true` when appropriate.

Visually inspect layout when tables, seals, positioning, or generated formatting matter.

## Place seals or signatures

Use the helper. Prefer anchor-based placement; use the ops form when explicit coordinates are required:

```text
kordoc-api seal-native <file> --image <seal-image> -o <output.hwpx> [--anchor <text>] [--occurrence <n>] [--size-mm <n>] [--mode <auto|overlap|right>] [--dx-mm <n>] [--dy-mm <n>]
kordoc-api seal <file> --image <seal-image> --ops <ops.json> -o <output.hwpx>
```

Fall back to the REST endpoint when neither anchor nor ops placement fits:

```text
POST /v1/document/seal
```

Provide the source HWPX, image, and seal operation array.

Prefer transparent PNG seal/signature images.

Inspect placement visually, especially with nested tables, text boxes, merged cells, line breaks, or row spans.
