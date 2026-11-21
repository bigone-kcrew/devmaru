# Kordoc — parse options and PPTX

Read this before parsing with non-default options (page ranges, OCR models, tables, passwords, PPTX).

### PPTX (PowerPoint)

`parse` reads `.pptx` directly. One slide is one page (`metadata.pageMode` is `"layout"`, `pageCount` is the number of slides).

- Title placeholders become headings, body placeholders become bullet lists (nested levels are kept), text boxes become paragraphs, tables keep merged cells.
- Speaker notes are written as a quote paragraph at the end of that slide.
- Hidden slides are skipped, the page numbers stay, and the warning `HIDDEN_TEXT_FILTERED` is returned.
- Charts and SmartArt are not read; the warning `UNSUPPORTED_ELEMENT` is returned. Embedded video, audio and OLE objects are not extracted.
- `--pages 2` selects a slide (supported from Kordoc 4.18.3). A range outside the deck returns an empty result with a `PARTIAL_PARSE` warning.


### Parse options

These options are accepted by `parse`, `metadata`, `parse-pages`, `parse-chunks` and `parse-table`. They are sent only when given; otherwise the engine default applies.
An unknown option name is rejected by the helper, but a misspelled field sent by raw `curl` is silently ignored by the service — compare the result with and without the option.

```text
--pages <range>                     3, 1-3, 1,3,5-7 (1-based). PDF: pages. HWP/HWPX: sections (approximate). PPTX: slides
--images <true|false>               extract image bytes; false for text-only/RAG callers
--remove-header-footer <true|false> PDF header/footer removal (default true; false keeps repeated headings)
--script-tags <true|false>          <sup>/<sub> for superscript/subscript. Default: on for HWPX/HWP/DOCX/PPTX, off for PDF (use true for papers)
--keep-trailing-empty-cols <true|false>  keep empty right-edge table columns (form input cells)
--layout-tables <visual|keep>       borderless frame tables: visual (default) = as seen, keep = original table structure
--classify-tables <true|false>      add blocks[].table.classification (data / layout / uncertain)
--keep-empty-paragraphs <true|false>  keep empty paragraphs (HWPX)
--ocr <false|true|force>            the central service sends false when you give nothing. true also reads small images and, since Kordoc 4.21.23, images embedded in HWP/HWPX bodies (more output, slower); force OCRs every page
--formula-ocr <true|false>          PDF formula OCR ($...$). Slow: 30-120 s per request
--ocr-rec <handwriting|auto|printed>  OCR recognition model. Default: the service re-reads clearly handwritten pages with the handwriting model by itself (Kordoc 4.24.42+). handwriting = Korean handwriting/official-form model; printed = never use or download it; auto = switch to it more readily (API 1.11.0+). Only with --ocr true|force
--ocr-det <mobile|server|medium>    OCR detection model (Kordoc 4.22.0+; default mobile, server = larger PP-OCRv5 model, medium = PP-OCRv6 medium for tilted, blurred or noisy scans, API 1.11.0+). Only with --ocr true|force
--ocr-det-long-side <32-4096>       long side of the OCR detection input in pixels (default 960). Only with --ocr true|force
--ocr-lines <true|false|all>        also return the lines the built-in OCR read as ocrLines[] in the JSON (Kordoc 4.24.4+, PDF and image input; default off). Full parse only; only with --ocr true|force
                                      true = the lines used to build blocks; all = also the low-confidence lines that were dropped (marked dropped: true)
                                      one item per page: {pageNumber,width,height,scale,deskewAngle,lines:[{text,box:{x,y,w,h},confidence}]}
                                      box is in OCR raster pixels, origin top-left, not PDF points (divide by scale); without the option the output is unchanged; MCP: parse_document only, ocr_lines "true" | "all"
--memos <true|false>               HWPX/HWP5: also append the document's memos (Hancom "insert memo") as a "메모" section at the end of the Markdown (default false; the memos[] field is returned either way) (API 1.11.0+)
--qr-codes <true|false>             read QR codes inside images; values go to the image block's qr[] and the line after the image placeholder (default false; works with --images false) (API 1.11.0+)
--drop-blank-images <true|false>    drop blank (nearly one colour) images from blocks, images and Markdown (default false; needs image bytes, i.e. --images not false) (API 1.11.0+)
--image-format <png|webp>           force every extracted image to png or lossless webp (default: PNG for PDF images, original bytes otherwise) (API 1.11.0+)
--image-placement <page-end|flow>   PDF only: page-end (default) collects images after the last block of the page; flow puts them in reading position and gives image blocks a bbox (API 1.11.0+)
--html-cell-links <true|false>      write links and URLs inside HTML table cells as <a href> so merged/nested table cells are clickable (default false; the address is otherwise written twice) (API 1.11.0+, Kordoc 4.24.63+)
--dedupe-running-headers <true|false>  drop numbered running headers re-inserted per page by old HWP5 (can delete legitimate repeats)
--inline-images <true|false>        inline images as base64 in the Markdown (HWP5 only; response grows)
--tables <true|false>               PDF table detection; false = reading-order text only
--password-env <ENV_NAME> | --password-file <path>   open password of a protected HWPX/HWP3, from an environment variable (by name) or a file
```

Recommended combinations:

```text
Original table structure of a form (for patching/filling):   --layout-tables keep --keep-trailing-empty-cols true
A blank form whose guidance text matters:                    --include-field-placeholders true
Text-only indexing / RAG:                                    --plain true --images false --include-blocks false
Text-centred PDF whose bordered boxes are not tables:        --tables false
Papers and formulas:                                         --script-tags true --formula-ocr true
Handwritten forms (scans):                                   --ocr true --ocr-rec handwriting
Tilted or blurred scans:                                     --ocr force --ocr-det medium
HWPX/HWP5 with review memos:                                 --memos true
RAG input with merged/nested tables and links:               --html-tables true --html-cell-links true
```

Password-protected documents: never put the password on the command line, and never paste it into the conversation. Keep it in a file readable only by you (mode 600) and pass the path, or put it in an environment variable and pass only its name:

```bash
kordoc-api parse protected.hwpx --password-file ./pw.txt
KORDOC_PW='...' kordoc-api parse protected.hwpx --password-env KORDOC_PW
```

Delete the password file when you are done. Without the password the result is `ENCRYPTED`. Hancom DRM documents cannot be opened.

`--formula-ocr true` is slow and the central service downloads the formula models once if it does not have them yet; do not use it by default and do not run it for many files in parallel.

`--ocr-rec handwriting`, `--ocr-det server` and `--ocr-det medium` use extra OCR models (about 15 MB, 88 MB and 62 MB). The central service downloads each one the first time it is requested, so the first request is slower. The three OCR model options do nothing unless OCR runs (`--ocr true` or `force`). The central service accepts preset names only; local model files cannot be selected.
