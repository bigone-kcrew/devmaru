# Kordoc — generating HWPX

Read this before creating a document from Markdown, using a department template, a formatting profile or images, or when a report must pass the approval gate.

## Generate HWPX

Prefer the advanced generator for normal document generation:

```bash
kordoc-api generate-hwpx-advanced input.md   -o output.hwpx
```

The advanced generator uses the central service implementation of Kordoc's high-level document generation workflow.

Pass supported Kordoc generation options through a JSON object:

```bash
kordoc-api generate-hwpx-advanced input.md   --options options.json   -o output.hwpx
```

Typical options may include document presets, organization information, approval lines, table of contents, title boxes, paper settings, page settings, and other options supported by the central Kordoc service.

For example:

```json
{
  "preset": "개조식",
  "org": "@@BRAND@@",
  "toc": true,
  "approval": ["담당", "팀장"],
  "body_title_box": true,
  "paper": "A4"
}
```

Do not put `markdown`, `output_path`, `profile_path`, or `image_dir` into the options file. The central service controls those paths and ignores client-provided values for them.

Agency styling (central Kordoc 4.21+): `agency` takes a central-government agency name (for example `"국세청"`) or `"공통"` and uses that agency's measured font, size, level markers and table-header style as the defaults. Explicit options still win. It applies only to the report, plan, ministry, gaejosik and press presets.

```json
{ "preset": "보고서", "agency": "국세청" }
```

- With `generate-hwpx-advanced` the options file is flat, as above. With `generate-hwpx` the same keys go under `gongmun`: `{"gongmun": {"preset": "보고서", "agency": "국세청"}}`.
- An unknown agency name is rejected with HTTP 400 and the list of supported agencies.
- `bullet2` sets the second-level marker (`ㅇ`, `○`, `◦` or `❍`). `autoFit.safety` (for example `0.95`) leaves a little more room on each line for typesetters other than Hancom.

Content of reports and plans: organise the chapters as why, then what, then how (not "introduction, body, conclusion") — background, grounds, present state and problems; then the outline, improvement measures and detailed plan; then schedule, budget, expected effect and next steps. Open the background with facts (date of an instruction, enforcement date of a law, number of complaints), pair every problem with a measure in the same order, and write the expected effect as the target value of the problem's indicator. Do not use generic AI filler ("in a rapidly changing environment", "improved satisfaction", "in conclusion"). Keep only the chapters the matter needs. Never invent numbers: write a placeholder such as `○○건` (placeholders pass the gate).

For documents that go to approval, pass the gate first: `kordoc-api lint-full --text-file draft.md --gate --preset 보고서` blocks notation and style errors, AI-style prose (`SLOP_*`) and structure findings (`LOGIC_*`). Fix the findings, run it again until it passes, then generate with `"gate": true` in the options file.

Department template (central Kordoc 4.24+): to write a new document in a department's own HWPX form (page setup, fonts, headers, approval box kept), pass the template file:

```bash
kordoc-api generate-hwpx-advanced input.md   --template template.hwpx   -o output.hwpx
```

The template's page setup, fonts, title table, contact line, summary box (`>`), `□ ○ -` paragraphs, `※` notes and data-table styles are reused and only the content comes from your Markdown (the sample's own text is not kept). The new content may be structured differently from the sample. A template cannot be combined with `--profile`, `--image` or the document-style options (`preset`, `font`, `cover`, `toc`, paper/page options, ...): the call is rejected and lists the conflicting options. The template counts toward the 8-file upload limit.

If the user hands over a sample HWPX and asks to keep it exactly ("the same form", edit its lines and cells in place, keep logos, approval box and tables as they are), do not use `--template`: follow "Copy a sample's form" in `references/patch.md`.

More generation options accepted in the options file (same names as the official `generate_document` tool): `paper` (A4, A3, B4, B5, Letter), `landscape`, `columns` (1-8), `header`, `footer`, `inline_math` (render `$...$` as Hancom equations), and `gate: true` (approval gate: when the draft has notation or style errors, or prose or structure findings, the call returns the list of findings instead of a file; fix the text and call again).

The lower-level generator remains available:

```bash
kordoc-api generate-hwpx input.md   --options options.json   -o output.hwpx
```

Use the lower-level command only when the advanced generator is not appropriate for the requested workflow or compatibility requires it.

### Generate with images

Markdown may reference uploaded images by filename:

```markdown
![diagram](diagram.png)
```

Upload each referenced image with a repeated `--image` option:

```bash
kordoc-api generate-hwpx-advanced input.md   --options options.json   --image diagram.png   --image chart.png   -o output.hwpx
```

Image filenames must be safe simple filenames and must not collide.

The service accepts at most 8 uploaded files per advanced generation request in total. A profile file counts toward this limit, so a request with one profile may contain at most 7 images.

After generation, always validate:

```bash
kordoc-api validate output.hwpx
```

Render or re-parse when visual or layout verification is relevant.

Never claim equivalence to manual Hancom Office verification unless that verification actually occurred.

## Reuse an HWPX formatting profile

Extract the reference profile:

```bash
kordoc-api profile-extract reference.hwpx -o profile.json
```

Then pass the profile file directly to the advanced generator:

```bash
kordoc-api generate-hwpx-advanced input.md   --profile profile.json   --options options.json   -o output.hwpx
```

The central advanced endpoint accepts both:

- the raw profile object produced by `kordoc-api profile-extract`
- the full wrapper returned by the central `/v1/document/profile/extract` REST endpoint

Do not manually wrap a helper-produced profile under `options.profile` for the normal advanced workflow.

A profile may also be combined with uploaded images:

```bash
kordoc-api generate-hwpx-advanced input.md   --profile profile.json   --image logo.png   --options options.json   -o output.hwpx
```

Remember that profile plus image uploads share the 8-file request limit.

Validate the generated HWPX afterward.
