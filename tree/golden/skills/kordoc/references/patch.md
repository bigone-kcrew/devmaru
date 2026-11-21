# Kordoc — patching and copying a sample's form

Read this before editing an existing HWP/HWPX or when the user hands over a sample document and wants new content in the same form.

## Patch existing HWP/HWPX

Use the helper:

```text
kordoc-api patch <file> --markdown <markdown-file> -o <output.hwp|output.hwpx> [--options <options.json>]
kordoc-api patch-native <file> --markdown <markdown-file> -o <output.hwp|output.hwpx> [--no-structure]
```

`patch-native` also adds or deletes paragraphs to follow the edited Markdown (HWPX). Add `--no-structure` to apply text edits only and keep the document skeleton fixed.

Fall back to the central REST endpoint only when the helper cannot express the request:

```text
POST /v1/document/patch
```

Keep the original document and write changes to a new output.

After patching HWPX, validate the result.

### Copy a sample's form

"Write ○○ in the same form as this document", "use this as the template": when the user hands over a sample HWPX/HWP and wants new content in it, do not use `generate-hwpx*` — it re-typesets with Kordoc's default form and the sample's logo, approval box, title box, fonts and spacing are lost. Edit the sample with `patch-native` instead:

```bash
kordoc-api parse sample.hwpx --layout-tables keep --keep-trailing-empty-cols true | jq -r .markdown > sample.md   # 1. read the sample
# 2. copy sample.md to new.md and rewrite only the content, keeping the skeleton
kordoc-api patch-native sample.hwpx --markdown new.md -o new.hwpx                                               # 3. apply with the sample's form
kordoc-api validate new.hwpx
kordoc-api render-native new.hwpx -o preview.png --pages 1                                                       # 4. look at each page
```

Rules for step 2:
- Keep big `<table>` blocks (cover, approval box), the title and image lines where they are and change only the text.
- Start each line with the same item mark as the sample (`□`, `ㅇ`, `-`, `※`, `1.`, `가.`) and keep the sample's `**bold**` places; the mark selects the sample's paragraph style.
- An HWPX sample may get more or fewer lines: a new line is cloned from the sample paragraph with the same mark (same indent, font, weight) and a deleted line is removed with its paragraph. Reordering blocks is not supported.
- Keep a table in the sample's notation (an HTML `<table>` stays HTML, do not turn it into a GFM table), change only cell text; rows can be added or removed.
- Do not invent personal names, document numbers or dates: write `○○○`. Masked `****` lines are deleted or replaced with new content.
- Read the "not applied" items in the result and compare the render with the sample before handing it over.
- An HWP (5.x) sample cannot get added or deleted paragraphs: keep the line count, or use a sample saved as HWPX in Hancom.
