import Fastify from "fastify";
import multipart from "@fastify/multipart";
import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import * as kordoc from "kordoc";
import {
  Client
} from "@modelcontextprotocol/sdk/client/index.js";
import {
  StdioClientTransport,
  getDefaultEnvironment
} from "@modelcontextprotocol/sdk/client/stdio.js";
import {
  mkdtemp,
  mkdir,
  writeFile,
  readFile,
  readdir,
  rm
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, basename } from "node:path";


// API 표면 버전. 종전에는 네 곳에 문자열로 박혀 있어 갈리기 쉬웠다 (2026-09-27).
const API_VERSION = "1.11.0";
const PORT = Number(process.env.PORT || 3400);
const API_KEY = process.env.KORDOC_API_KEY || "";
// 인증 모드: proxy(기본) = 공개 프록시(Caddy)를 거친 요청만 키를 검사한다. 내부 직접 접속은 무인증이다(@@BRAND@@).
//           always       = 직접 접속에도 Bearer 키를 요구한다(LAN 에 노출되는 환경).
const AUTH_MODE = String(process.env.KORDOC_AUTH_MODE || "proxy").toLowerCase();
if (AUTH_MODE !== "proxy" && AUTH_MODE !== "always") {
  throw new Error('KORDOC_AUTH_MODE must be "proxy" or "always"');
}
const MAX_FILE_MB = Number(process.env.KORDOC_MAX_FILE_MB || 250);
const TIMEOUT_MS = Number(process.env.KORDOC_TIMEOUT_MS || 600000);
const CONCURRENCY = Math.max(
  1,
  Number(process.env.KORDOC_CONCURRENCY || 1)
);

function safeUploadFilename(filename) {
  const name = basename(String(filename || ""));

  if (!name || name === "." || name === "..") {
    const e = new Error("invalid upload filename");
    e.statusCode = 400;
    throw e;
  }

  return name;
}

async function withTempWorkspace(fn) {
  const dir = await mkdtemp(
    join(tmpdir(), "kordoc-generate-")
  );

  try {
    return await fn(dir);
  } finally {
    await rm(dir, {
      recursive: true,
      force: true
    });
  }
}

const KORDOC_MCP =
  "/app/node_modules/kordoc/dist/mcp.js";

async function runKordocMcpTool(
  root,
  toolName,
  toolArguments
) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [KORDOC_MCP],
    cwd: root,
    env: {
      ...getDefaultEnvironment(),
      KORDOC_ROOT: root,
      KORDOC_OFFLINE: "1",
      ...(process.env.PUPPETEER_EXECUTABLE_PATH
        ? { PUPPETEER_EXECUTABLE_PATH: process.env.PUPPETEER_EXECUTABLE_PATH }
        : {}),
      ...(process.env.KORDOC_CHROMIUM_NO_SANDBOX
        ? { KORDOC_CHROMIUM_NO_SANDBOX: process.env.KORDOC_CHROMIUM_NO_SANDBOX }
        : {})
    },
    stderr: "pipe"
  });

  const client = new Client({
    name: "@@PFX@@-kordoc-api",
    version: API_VERSION
  });

  try {
    await client.connect(transport);

    const result = await client.callTool(
      {
        name: toolName,
        arguments: toolArguments
      },
      undefined,
      {
        timeout: TIMEOUT_MS,
        maxTotalTimeout: TIMEOUT_MS
      }
    );

    return result;
  } finally {
    await client.close().catch(() => {});
  }
}

async function attachFiles(result, dir) {
  if (result?.isError) return result;
  const mimeTypes = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".svg": "image/svg+xml"
  };
  let names = [];
  try {
    names = (await readdir(dir)).sort();
  } catch {
    names = [];
  }
  const outputs = [];
  for (const n of names) {
    const ext = n.slice(n.lastIndexOf(".")).toLowerCase();
    if (!mimeTypes[ext]) continue;
    outputs.push({
      name: n,
      mimeType: mimeTypes[ext],
      data: (await readFile(join(dir, n))).toString("base64")
    });
  }
  return { ...result, files: outputs };
}

const app = Fastify({
  logger: true,
  bodyLimit: MAX_FILE_MB * 1024 * 1024,
  requestTimeout: 0
});

await app.register(multipart, {
  limits: {
    fileSize: MAX_FILE_MB * 1024 * 1024,
    files: 8
  }
});

await app.register(swagger, {
  openapi: {
    info: {
      title: "@@BRAND@@ Kordoc API",
      version: API_VERSION,
      description:
        "Kordoc document processing API for HWP/HWPX/PDF/DOCX/XLSX/PPTX/images, OCR, RAG chunks, forms, document generation, patching, rendering, validation, seals and redaction."
    },
    ...(process.env.KORDOC_PUBLIC_URL
      ? {
          servers: [
            {
              url: process.env.KORDOC_PUBLIC_URL,
              description: process.env.KORDOC_PUBLIC_URL_NOTE || "Kordoc API"
            }
          ]
        }
      : {}),
    components: {
      securitySchemes: {
        bearerAuth: {
          type: "http",
          scheme: "bearer"
        }
      }
    }
  }
});

function multipartBody(properties, required = ["file"]) {
  return {
    required: true,
    content: {
      "multipart/form-data": {
        schema: {
          type: "object",
          required,
          properties
        }
      }
    }
  };
}

const fileProperty = {
  type: "string",
  format: "binary",
  description: "Input document"
};

const boolStringProperty = (description, defaultValue = "false") => ({
  type: "string",
  enum: ["true", "false"],
  default: defaultValue,
  description
});

const ocrProperty = {
  type: "string",
  enum: ["false", "true", "force"],
  default: "false",
  description:
    "false=disable OCR; true=OCR pages that need recognition, plus small images and logos "
    + "and, for HWP/HWPX, images embedded in the body (Kordoc 4.21.23+); force=OCR every page. "
    + "When omitted this service sends false (OCR off) — unlike the Kordoc CLI, whose default OCRs scanned pages."
};

// 기본값이 «형식마다 다르거나 상류가 정한다» 인 옵션에는 거짓 default 를 달지 않는다.
const optionalBoolProperty = (description) => ({
  type: "string",
  enum: ["true", "false"],
  description
});

// kordoc ParseOptions 나머지 (4.18.2) — 파싱 라우트 5개(parse·metadata·parse/pages·parse/chunks·parse/table)가 공유한다.
const extraParseProperties = {
  pages: {
    type: "string",
    description:
      'Page/section range to parse, 1-based: "1-3" or "1,3,5-7". Exact pages for PDF, '
      + "a section-level approximation for HWP/HWPX. Omit to parse the whole document."
  },
  scriptTags: optionalBoolProperty(
    "Write superscript/subscript as inline <sup>/<sub> (kordoc ParseOptions). Default depends on the "
    + "format: on for HWPX/HWP/DOCX, off for PDF (recommended for papers and formulas). "
    + "false forces plain text everywhere."
  ),
  keepTrailingEmptyCols: optionalBoolProperty(
    "Keep empty columns at the right edge of a table (the input cells of forms). Default false trims them."
  ),
  layoutTables: {
    type: "string",
    enum: ["visual", "keep"],
    default: "visual",
    description:
      "Frame tables without visible borders (HWPX, HWP5, PDF). visual=as seen: borderless frames become text, "
      + "only ruled parts stay tables. keep=the original table structure (for round-trip patching and form filling)."
  },
  classifyTables: optionalBoolProperty(
    "Classify tables as data / layout / uncertain and attach it to each table block (blocks[].table.classification). "
    + "Default false leaves the normal output unchanged."
  ),
  keepEmptyParagraphs: optionalBoolProperty(
    "Keep empty paragraphs as text:\"\" blocks so paragraph count equals line count (HWPX). Default false drops them."
  ),
  formulaOcr: optionalBoolProperty(
    "PDF formula OCR: detect formula regions and write LaTeX as $...$ / $$...$$. Default false. The model "
    + "(~155 MB) downloads on first use; if the optional dependencies or the download fail, the parse still "
    + "succeeds with a warning and skips formulas."
  ),
  dedupeRunningHeaders: optionalBoolProperty(
    "Drop numbered running headers that an old HWP5 re-inserts on every page, keeping the first. Default false: "
    + "the heuristic can also delete legitimately repeated numbering (e.g. renumbered attachments); "
    + "removals raise HIDDEN_TEXT_FILTERED."
  ),
  inlineImages: optionalBoolProperty(
    "Inline extracted images into the Markdown as base64 data URIs (HWP5 only). Default false. "
    + "The response grows with the image bytes; ignored when images=false."
  ),
  tables: optionalBoolProperty(
    "PDF table detection. Default true. false turns off ruled-grid and cluster table detection and returns "
    + "natural reading-order text — for text-centred documents whose bordered boxes are not tables. "
    + "Ignored by other formats."
  ),
  ocrRec: {
    type: "string",
    enum: ["handwriting", "auto", "printed"],
    description:
      "Built-in OCR recognition model. Omit for the default: PP-OCRv5 Korean rec, and since Kordoc 4.24.42 pages with clearly "
      + "handwritten text (page confidence < .85) are re-read with the handwriting rec (~15 MB, downloaded the first time such a page is met). "
      + "printed (API 1.11.0+) = the default rec only: never downloads or uses the handwriting rec. "
      + "auto (API 1.11.0+) = more generous thresholds (< .90, +.06) for switching pages to the handwriting rec, and downloads it up front. "
      + "handwriting = Korean handwriting/official-form rec (~15 MB, downloaded on first use). "
      + "Only the preset name is accepted (no local model paths). "
      + "Takes effect only on requests where OCR runs (ocr=true or force)."
  },
  ocrDet: {
    type: "string",
    enum: ["mobile", "server", "medium"],
    description:
      "Built-in OCR text-line detection model. Default mobile (PP-OCRv5 mobile det, ~5 MB). server = PP-OCRv5 server det "
      + "(~88 MB, downloaded on first use): better on small text, slower. medium (API 1.11.0+) = PP-OCRv6 medium det (~62 MB, "
      + "downloaded on first use): for tilted, blurred, scanned or noisy pages. Only preset names are accepted. "
      + "Takes effect only on requests where OCR runs (ocr=true or force)."
  },
  ocrDetLongSide: {
    type: "integer",
    minimum: 32,
    maximum: 4096,
    description:
      "OCR detection input long side in px (integer 32-4096). Upstream default 960. Larger catches smaller text but is slower. "
      + "Takes effect only on requests where OCR runs (ocr=true or force)."
  },
  ocrLines: {
    type: "string",
    enum: ["true", "false", "all"],
    description:
      "API 1.10.0+. Return the lines recognised by the built-in OCR as ocrLines[] (per page: text, box, confidence) in the "
      + "response of routes that return the full parse result (e.g. POST /v1/parse). PDF and image input only. "
      + "true = the lines used to build blocks; all = also the low-confidence lines it dropped (dropped: true). "
      + "Default off (false or omitted): the response is unchanged. Takes effect only on requests where OCR runs (ocr=true or force). "
      + "ocrRecDict (a server-local model file) is not accepted."
  },
  memos: optionalBoolProperty(
    "API 1.11.0+. HWPX/HWP5: also append the document's memos (Hancom \"insert memo\") to the end of the Markdown as a \"메모\" section. "
    + "Default false: body only. The memos are returned in the response field memos[] (HWPX/HWP5 documents that have memos) regardless of this option."
  ),
  qrCodes: optionalBoolProperty(
    "API 1.11.0+. Read QR codes inside images (all formats) and write the values to the image block's qr[] and on the line after the "
    + "image placeholder in the Markdown. Default false: output unchanged. Works even with images=false."
  ),
  imageFormat: {
    type: "string",
    enum: ["png", "webp"],
    description:
      "API 1.11.0+. Force every extracted image to one format: png or lossless webp (file name, MIME and bytes agree). "
      + "Omit to keep the default (PNG for PDF images, the original bytes for other formats). Ignored when images=false."
  },
  imagePlacement: {
    type: "string",
    enum: ["page-end", "flow"],
    description:
      "API 1.11.0+. PDF only. page-end (default) = images are collected after the last block of their page. "
      + "flow = images are placed in reading position between text blocks and image blocks get a bbox."
  },
  dropBlankImages: optionalBoolProperty(
    "API 1.11.0+. Drop blank images (nearly one colour: empty plates, solid bands, faint gradients) from the image blocks, images and Markdown. "
    + "Default false: output unchanged. Only evaluated when image bytes are produced (images not false)."
  ),
  htmlCellLinks: optionalBoolProperty(
    "API 1.11.0+ (Kordoc 4.24.63+). Emit [text](URL), bare URLs (incl. www.) and QR URLs inside HTML table cells as <a href> so merged/nested "
    + "table cells are clickable in Markdown viewers (GFM does not parse Markdown inside HTML blocks). Only http, https, mailto, tel and # links. "
    + "Default false: output unchanged (the address is written twice, which is usually unwanted for LLM/RAG input)."
  ),
  password: {
    type: "string",
    format: "password",
    description:
      "Open password of a protected document: HWPX (ODF AES-256-CBC) and HWP3 (DES). Hancom DRM is a "
      + "different mechanism and is not supported. The value is never logged."
  }
};

function decorateOpenApi(original) {
  const spec = structuredClone(original);
  const paths = spec.paths ?? {};

  const setBody = (path, body) => {
    if (paths[path]?.post) paths[path].post.requestBody = body;
  };

  const setJsonBody = (path, schema, example) => {
    if (!paths[path]?.post) return;

    paths[path].post.requestBody = {
      required: true,
      content: {
        "application/json": {
          schema,
          example
        }
      }
    };
  };

  setBody("/v1/detect", multipartBody({
    file: fileProperty
  }));

  for (const path of [
    "/v1/parse",
    "/v1/metadata",
    "/v1/parse/pages"
  ]) {
    setBody(path, multipartBody({
      file: fileProperty,
      ocr: ocrProperty,
      ...extraParseProperties,
      images: boolStringProperty(
        "Extract image bytes (kordoc ParseOptions). Set false for text-only callers "
        + "such as search indexers: image placeholders stay, text and OCR are unaffected.",
        "true"
      ),
      includeBlocks: boolStringProperty(
        "Return blocks in parse response",
        "true"
      ),
      includeImages: boolStringProperty(
        "Include extracted image bytes in the response. Applies to /v1/parse only "
        + "— the other routes never return image bytes. Requires images=true "
        + "(the default); with images=false there is nothing to include. "
        + "Responses can grow by orders of magnitude.",
        "false"
      ),
      removeHeaderFooter: boolStringProperty(
        "Remove repeated header/footer blocks (kordoc ParseOptions). "
        + "Set false to keep repeated section headings the filter would delete.",
        "true"
      ),
      includeFieldPlaceholders: boolStringProperty(
        "Keep the guidance text of unfilled form fields (kordoc 4.15.7+, issue #92). "
        + "Blank public-sector forms carry their meaning in that text — with it "
        + "removed a blank form is an empty table. Leave false when parsing "
        + "filled-in documents, where the guidance text is noise.",
        "false"
      ),
      plain: boolStringProperty(
        "Plain Markdown (kordoc 4.15.7+): drop image placeholders, link URLs, "
        + "underline (<u>) and bold (**) markup and keep the text. Heading, list "
        + "and table structure and the blocks IR are unchanged. For indexing and "
        + "RAG callers that do not store image bytes — pair it with images=false.",
        "false"
      ),
      htmlTables: boolStringProperty(
        "Emit every table as indented HTML (kordoc 4.15.7+), including the ones "
        + "that would otherwise be GFM pipe tables, with <th> on the first row. "
        + "Use it when the consumer handles only one table shape. Output grows.",
        "false"
      ),
      tableFormat: {
        type: "string",
        enum: ["gfm"],
        description: "kordoc 4.19.0+. \"gfm\" converts merged and nested tables to GFM pipe tables too (no HTML tables; "
          + "vertical merges repeat the value per row, nested tables are emitted after the parent with a parent_id comment). "
          + "Omit for the previous output (byte-identical). Cannot be combined with htmlTables."
      }
    }));
  }

  setBody("/v1/parse/chunks", multipartBody({
    file: fileProperty,
    ocr: ocrProperty,
    ...extraParseProperties,
    images: boolStringProperty(
      "Extract image bytes (kordoc ParseOptions). Set false for text-only callers "
      + "such as search indexers: image placeholders stay, text and OCR are unaffected.",
      "true"
    ),
    granularity: {
      type: "string",
      enum: ["section", "block"],
      default: "section"
    },
    includeTableCells: boolStringProperty(
      "Include table cell values in chunk metadata"
    ),
    tableFormat: {
      type: "string",
      enum: ["gfm"],
      description: "kordoc 4.19.0+. \"gfm\" renders merged and nested tables as GFM pipe tables in the table chunks "
        + "(table ids are numbered across the whole document; no HTML tables). "
        + "Omit for the previous output (byte-identical). Cannot be combined with htmlTables."
    }
  }));

  setBody("/v1/parse/table", multipartBody({
    file: fileProperty,
    ocr: ocrProperty,
    ...extraParseProperties,
    images: boolStringProperty(
      "Extract image bytes (kordoc ParseOptions). Set false for text-only callers "
      + "such as search indexers: image placeholders stay, text and OCR are unaffected.",
      "true"
    )
  }));

  setBody("/v1/compare", multipartBody({
    fileA: {
      ...fileProperty,
      description: "Original / first document"
    },
    fileB: {
      ...fileProperty,
      description: "Compared / second document"
    },
    ocr: ocrProperty
  }, ["fileA", "fileB"]));

  setBody("/v1/form/parse", multipartBody({
    file: fileProperty
  }));

  setBody("/v1/form/fill", multipartBody({
    file: {
      ...fileProperty,
      description:
        "Input document. Either file or template is required."
    },
    template: {
      type: "string",
      enum: [
        "gian",
        "gian-simple",
        "일반기안문",
        "간이기안문"
      ],
      description:
        "Built-in government form template. Use instead of file."
    },
    values: {
      type: "string",
      description:
        'JSON object of form values, e.g. {"성명":"홍길동"}'
    },
    formats: {
      type: "string",
      description:
        'Optional JSON object mapping field labels to formats, e.g. {"전화번호":"phone:hyphen"}'
    },
    requireUnique: boolStringProperty(
      "When true, fields are not filled when a label matches multiple locations. Ambiguous labels are returned in unmatched."
    ),
    maskValues: boolStringProperty(
      "Do not expose filled values in API response metadata or Markdown preview."
    ),
    outputFormat: {
      type: "string",
      enum: ["markdown", "hwpx", "hwpx-preserve"],
      default: "markdown"
    }
  }, ["values"]));

  {
    const schema =
      paths["/v1/form/fill"]?.post?.requestBody
        ?.content?.["multipart/form-data"]?.schema;

    if (schema) {
      schema.anyOf = [
        { required: ["file"] },
        { required: ["template"] }
      ];
    }
  }

  setBody("/v1/document/profile/extract", multipartBody({
    file: {
      ...fileProperty,
      description: "Reference HWPX document"
    }
  }));

  setBody("/v1/document/redact", multipartBody({
    file: fileProperty,
    rules: {
      type: "string",
      description:
        'Optional JSON array of redaction rules, e.g. ["rrn","phone","email"]'
    },
    maskChar: {
      type: "string",
      description: "Optional single masking character. Default is Kordoc default."
    },
    dryRun: boolStringProperty(
      "Detect and report redactions without changing document bytes."
    )
  }));

  setBody("/v1/document/patch/native", multipartBody({
    file: { ...fileProperty, description: "HWP or HWPX document" },
    markdown: { type: "string", description: "Edited Markdown content" },
    structure: optionalBoolProperty(
      "API 1.9.0+. false = apply text edits only, do not add or delete paragraphs (HWPX). Default: structure edits applied."
    )
  }, ["file", "markdown"]));

  setBody("/v1/document/patch", multipartBody({
    file: fileProperty,
    markdown: {
      type: "string",
      description: "Edited Markdown content"
    },
    options: {
      type: "string",
      description: "Optional JSON options"
    }
  }, ["file", "markdown"]));

  setBody("/v1/document/render", multipartBody({
    file: {
      ...fileProperty,
      description: "HWPX document"
    },
    options: {
      type: "string",
      description:
        'Optional JSON render options. Use {"reflow":true} when the HWPX has no Hancom linesegarray layout cache.'
    }
  }));

  setBody("/v1/document/render/native", multipartBody({
    file: {
      ...fileProperty,
      description: "HWP or HWPX document"
    },
    format: {
      type: "string",
      enum: ["png", "jpeg", "svg", "html", "pdf"],
      description:
        "png/jpeg: image content in the response (default png). svg/html/pdf (API 1.9.0+): "
        + "the files come back in files[] as base64 (one file per page when pages is given); "
        + "pdf needs Chromium."
    },
    highlights: {
      type: "string",
      description:
        'Optional JSON array of text strings to highlight, e.g. ["검증","완료"].'
    },
    reflowMode: {
      type: "string",
      enum: ["keep", "charAll"],
      description:
        "Kordoc render_document reflow_mode. Default: keep."
    },
    pages: {
      type: "string",
      description:
        "Optional 1-based page selection, e.g. 1, 1-3, or 1,3,7-9."
    },
    maxWidthPx: {
      type: "integer",
      minimum: 200,
      maximum: 4000,
      description:
        "Maximum raster width in pixels."
    }
  }));

  setBody("/v1/document/extract-tables", multipartBody({
    file: { ...fileProperty, description: "HWP or HWPX document" },
    visual: {
      type: "string",
      enum: ["none", "non-tabular", "non-tabular-and-uncertain", "all"],
      description: "Which tables to also render as images. Default: none."
    },
    format: { type: "string", enum: ["png", "jpeg"], description: "Image format. Default: png." },
    paddingPt: { type: "number", minimum: 0, maximum: 100, description: "Padding in points. Default: 0." },
    cells: optionalBoolProperty("Include cell text in the table metadata."),
    returnFiles: optionalBoolProperty(
      "API 1.9.0+. true = the image files the tool wrote come back in files[] as base64. Default: false (unchanged response)."
    )
  }));

  setBody("/v1/document/crop-regions", multipartBody({
    file: { ...fileProperty, description: "HWP or HWPX document" },
    target: {
      type: "string",
      description: 'JSON array of table, image, paragraph or shape, e.g. ["table"]. Default: ["table"].'
    },
    format: { type: "string", enum: ["png", "jpeg"], description: "Image format. Default: png." },
    pages: { type: "string", description: "Optional 1-based page selection." },
    paddingPt: { type: "number", minimum: 0, maximum: 100, description: "Padding in points. Default: 0." },
    returnFiles: optionalBoolProperty(
      "API 1.9.0+. true = the cropped image files come back in files[] as base64. Default: false (unchanged response)."
    )
  }));

  setBody("/v1/document/lint/full", multipartBody({
    file: {
      ...fileProperty,
      description: "Document to lint (give exactly one of file, text, blocks)"
    },
    text: { type: "string", description: "Markdown or plain text" },
    blocks: {
      type: "string",
      description: "JSON array of {id,text,table?} blocks in document order"
    },
    munche: optionalBoolProperty("Gaejosik style check"),
    slop: optionalBoolProperty("AI-style prose check"),
    logic: optionalBoolProperty("Report/plan logic-structure check"),
    numbers: optionalBoolProperty("Body numbers vs table numbers"),
    budget: optionalBoolProperty("Budget document check"),
    gate: optionalBoolProperty("Pre-approval gate (notation and style errors block)"),
    preset: { type: "string", description: "Preset that scopes the gate (e.g. 보고서, 개조식)" }
  }, []));

  setBody("/v1/document/validate", multipartBody({
    file: {
      ...fileProperty,
      description: "HWPX document"
    }
  }));

  setBody("/v1/document/seal", multipartBody({
    file: {
      ...fileProperty,
      description: "HWPX document"
    },
    image: {
      type: "string",
      format: "binary",
      description: "Seal image"
    },
    ops: {
      type: "string",
      description:
        'JSON array of seal operations. Each operation requires anchor; uploaded image is injected as image.'
    }
  }, ["file", "image", "ops"]));

  setJsonBody(
    "/v1/document/generate/hwpx",
    {
      type: "object",
      required: ["markdown"],
      properties: {
        markdown: {
          type: "string",
          description: "Markdown source used to generate the HWPX document"
        },
        options: {
          type: "object",
          additionalProperties: true,
          description:
            "Optional Kordoc markdownToHwpx options. Document-format presets live under "
            + "gongmun — a top-level preset key is silently ignored (measured 2026-09-24: "
            + "byte-identical output to sending no options at all).",
          properties: {
            gongmun: {
              type: "object",
              additionalProperties: true,
              description:
                "Korean official-document mode (kordoc GongmunOptions). "
                + "Omit it entirely for plain markdown conversion.",
              properties: {
                preset: {
                  type: "string",
                  enum: [
              "official", "report", "plan", "notice", "minutes", "gaejosik",
              "press", "ministry",
              "기안문", "시행문", "공문", "공문서", "보고서", "계획서", "계획", "통지",
              "알림", "안내", "회의록", "개조식", "개조식보고서", "정부보고서",
              "정부표준개조식보고서", "보도자료", "업무보고", "부처업무보고",
              "중앙부처보고서", "서울방침", "방침서", "방침"
                  ],
                  description:
                    "Document-type preset. 개조식 and 업무보고 turn the cover page on "
                    + "by default; the others do not. An unknown value falls back to the default."
                },
                cover: {
                  oneOf: [
                    { type: "boolean" },
                    {
                      type: "object",
                      additionalProperties: true,
                      properties: {
                        date: { type: "string", description: "기본 오늘, 'YYYY. M. D.'" },
                        org: { type: "string", description: "기관명" },
                        dept: { type: "string", description: "부서명" },
                        label: {
                          type: "string",
                          description:
                            "표지 우상단 취급 표시 (예: 대외주의 · 비공개). "
                            + "업무보고 프리셋에서 빨간 테두리 박스로 그려진다."
                        }
                      }
                    }
                  ],
                  description: "표지 페이지. false 로 끈다."
                },
                toc: {
                  type: "boolean",
                  description: "목차 페이지 (개조식 프리셋 기본 켜짐). h2 를 Ⅰ Ⅱ Ⅲ… 로 생성."
                },
                agency: {
                  type: "string",
                  description:
                    "기관 서식 (Kordoc 4.21.x). 중앙행정기관 이름(예: 국세청) 또는 '공통' — 정책브리핑 보도자료 실측 "
                    + "□·ㅇ·- 글꼴·크기, 2단계 부호, 표 머리, 기관 색을 기본값으로 깐다. 명시 옵션이 이긴다. "
                    + "보고서·계획서·업무보고·개조식·보도자료 프리셋 전용."
                },
                bullet2: {
                  type: "string",
                  enum: ["ㅇ", "○", "◦", "❍"],
                  description: "2단계 항목부호. 미지정이면 통지·보도자료 ㅇ, 그 외 ○."
                }
              }
            }
          }
        }
      }
    },
    {
      markdown: "# @@BRAND@@ Kordoc\n\n한글 HWPX 생성 예제입니다.",
      options: { gongmun: { preset: "기안문" } }
    }
  );

  setBody("/v1/document/generate/hwpx/advanced", multipartBody({
    markdown: {
      type: "string",
      description:
        "Markdown source used to generate the HWPX document"
    },
    options: {
      type: "string",
      description:
        "Optional JSON object using official Kordoc generate_document options. " +
        "Server-controlled markdown, output_path, profile_path and image_dir values are ignored. " +
        "Options are FLAT here (unlike generate/hwpx, which nests them under gongmun): " +
        "e.g. {\"preset\":\"보고서\",\"agency\":\"국세청\"}. An unknown agency name returns 400 with the supported list."
    },
    profile: {
      type: "string",
      format: "binary",
      description:
        "Optional Kordoc HWPX profile JSON file."
    },
    template: {
      type: "string",
      format: "binary",
      description:
        "Optional department template HWPX (official generate_document template_path). "
        + "Cannot be combined with profile or the document-preset options."
    },
    image: {
      type: "array",
      maxItems: 8,
      items: {
        type: "string",
        format: "binary"
      },
      description:
        "Optional image files. Send as repeated multipart fields named image. " +
        "The service accepts at most 8 uploaded files per request in total; " +
        "when profile is included, at most 7 images can be uploaded."
    }
  }, ["markdown"]));

  setJsonBody(
    "/v1/document/generate/pdf",
    {
      type: "object",
      required: ["markdown"],
      properties: {
        markdown: {
          type: "string",
          description: "Markdown source used to generate the PDF document"
        },
        options: {
          type: "object",
          additionalProperties: true,
          description:
            "Optional Kordoc markdownToPdf options (PrintOptions). These print presets are "
            + "a different system from the gongmun document presets used by generate/hwpx — "
            + "do not mix them.",
          properties: {
            preset: {
              type: "string",
              enum: ["default", "gov-formal", "compact"],
              description: "Print preset. gov-formal shows the header automatically."
            },
            pageSize: { type: "string", enum: ["A4", "Letter"] },
            orientation: { type: "string", enum: ["portrait", "landscape"] },
            header: { type: "string", description: "페이지 머리글 (HTML 허용)" },
            footer: { type: "string", description: "페이지 바닥글 (HTML 허용)" },
            watermark: { type: "string", description: "워터마크 텍스트 (대각선 회색)" }
          }
        }
      }
    },
    {
      markdown: "# @@BRAND@@ Kordoc\n\n한글 PDF 생성 예제입니다.",
      options: {}
    }
  );

  setJsonBody(
    "/v1/document/lint",
    {
      type: "object",
      required: ["text"],
      properties: {
        text: {
          type: "string",
          description:
            "Markdown or plain text to check. Fenced code blocks are skipped. "
            + "Checks the notation rules of the Korean administrative-work handbook "
            + "(dates, times, amounts, attachments, symbols). From kordoc 4.20.0 it also checks "
            + "period and time range dashes, weekday that does not match the date, Hangul amount "
            + "that does not match the digits, plain-language wording, spelling, and the double "
            + "space after the closing 끝. and 붙임. A weekday mismatch is an error (the response "
            + "has ok:false, still HTTP 200); the other new rules are warnings."
        },
        munche: {
          type: "boolean",
          default: false,
          description:
            "Also check the gaejosik (bulleted report) style: narrative '~다' endings, "
            + "imperatives, rhetorical questions, item length. For report and plan drafts."
        }
      }
    },
    {
      text: "2026.10.2 에 회의를 개최함.",
      munche: false
    }
  );

  setJsonBody(
    "/v1/document/redact/text",
    {
      type: "object",
      required: ["text"],
      properties: {
        text: {
          type: "string",
          description: "Plain text to redact"
        },
        options: {
          type: "object",
          additionalProperties: true,
          description: "Optional Kordoc redactText options"
        }
      }
    },
    {
      text: "이메일 test@example.com, 전화 010-1234-5678",
      options: {}
    }
  );

  setJsonBody(
    "/v1/document/redact/markdown",
    {
      type: "object",
      required: ["markdown"],
      properties: {
        markdown: {
          type: "string",
          description: "Markdown text to redact while preserving Markdown structure"
        },
        options: {
          type: "object",
          additionalProperties: true,
          description: "Optional Kordoc redactMarkdown options"
        }
      }
    },
    {
      markdown: "# 개인정보\n\n이메일: test@example.com\n\n전화: 010-1234-5678",
      options: {}
    }
  );

  spec.paths = paths;
  return spec;
}

await app.register(swaggerUi, {
  routePrefix: "/docs",
  transformSpecification: (swaggerObject) =>
    decorateOpenApi(swaggerObject),
  transformSpecificationClone: true
});

let activeJobs = 0;
const jobQueue = [];

function acquireSlot() {
  if (activeJobs < CONCURRENCY) {
    activeJobs += 1;
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    jobQueue.push(resolve);
  });
}

function releaseSlot() {
  if (jobQueue.length > 0) {
    const next = jobQueue.shift();
    next();
    return;
  }

  activeJobs = Math.max(0, activeJobs - 1);
}

async function withTimeout(fn) {
  await acquireSlot();

  let timer;

  try {
    return await Promise.race([
      fn(),
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("processing timeout")),
          TIMEOUT_MS
        );
      })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
    releaseSlot();
  }
}

async function withSlot(fn) {
  await acquireSlot();

  try {
    return await fn();
  } finally {
    releaseSlot();
  }
}

function requireAuth(request, reply, done) {
  const viaPublicProxy =
    request.headers["x-kordoc-public-proxy"] === "1";

  // Direct port 3400 access is internal-only.
  if (!viaPublicProxy && AUTH_MODE !== "always") {
    done();
    return;
  }

  if (!API_KEY) {
    reply.code(503).send({
      error: "KORDOC_API_KEY is not configured"
    });
    return;
  }

  const auth = request.headers.authorization || "";

  if (auth !== `Bearer ${API_KEY}`) {
    reply.code(401).send({
      error: "Unauthorized"
    });
    return;
  }

  done();
}

function boolValue(value, fallback = false) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  return String(value).toLowerCase() === "true";
}

function ocrValue(value) {
  if (value === undefined || value === null || value === "") {
    return false;
  }

  const v = String(value).toLowerCase();

  if (v === "force") return "force";
  if (v === "true") return true;

  return false;
}

function jsonValue(value, fallback = undefined) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  if (typeof value === "object") return value;

  try {
    return JSON.parse(String(value));
  } catch {
    const e = new Error("invalid JSON field");
    e.statusCode = 400;
    throw e;
  }
}

function booleanValue(value, fallback = false) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  if (typeof value === "boolean") return value;

  const v = String(value).toLowerCase();

  if (v === "true" || v === "1") return true;
  if (v === "false" || v === "0") return false;

  const e = new Error("invalid boolean field");
  e.statusCode = 400;
  throw e;
}

function buildFillInputs(values, formats = {}) {
  const out = {};

  for (const [key, value] of Object.entries(values)) {
    const format = formats?.[key];
    out[key] = format ? { value, format } : value;
  }

  return out;
}

function toNodeBuffer(value) {
  if (Buffer.isBuffer(value)) return value;

  if (value instanceof ArrayBuffer) {
    return Buffer.from(value);
  }

  if (ArrayBuffer.isView(value)) {
    return Buffer.from(
      value.buffer,
      value.byteOffset,
      value.byteLength
    );
  }

  return null;
}

// includeImages 기본 false -- 안 주면 종전대로 이미지 바이트를 뺀다.
// images=false 로 «추출» 자체를 껐다면 여기서 실을 것이 없다. 두 옵션은 짝이다.
function cleanResult(result, includeBlocks = true, includeImages = false) {
  if (
    result &&
    typeof result === "object" &&
    !Array.isArray(result)
  ) {
    const response = { ...result };

    if (!includeImages) {
      delete response.images;
    }

    if (!includeBlocks) {
      delete response.blocks;
    }

    return response;
  }

  return result;
}

async function readParts(request) {
  const files = {};
  const fields = {};

  for await (const part of request.parts()) {
    if (part.type === "file") {
      files[part.fieldname] = {
        filename: part.filename,
        mimetype: part.mimetype,
        buffer: await part.toBuffer()
      };
    } else {
      fields[part.fieldname] = part.value;
    }
  }

  return { files, fields };
}

async function readAdvancedGenerateParts(request) {
  const fields = {};
  let profile = null;
  let template = null;
  const images = [];

  for await (const part of request.parts()) {
    if (part.type !== "file") {
      fields[part.fieldname] = part.value;
      continue;
    }

    const item = {
      filename: part.filename,
      mimetype: part.mimetype,
      buffer: await part.toBuffer()
    };

    if (part.fieldname === "profile") {
      if (profile) {
        const e = new Error("only one profile file is allowed");
        e.statusCode = 400;
        throw e;
      }
      profile = item;
      continue;
    }

    if (part.fieldname === "image") {
      images.push(item);
      continue;
    }

    if (part.fieldname === "template") {
      if (template) {
        const e = new Error("only one template file is allowed");
        e.statusCode = 400;
        throw e;
      }
      template = item;
      continue;
    }

    const e = new Error(
      `unsupported file field: ${part.fieldname}`
    );
    e.statusCode = 400;
    throw e;
  }

  return { fields, profile, template, images };
}

function requireFile(files, name = "file") {
  const file = files[name];

  if (!file) {
    const e = new Error(`${name} is required`);
    e.statusCode = 400;
    throw e;
  }

  return file;
}

function routeSchema(tag, summary, description) {
  return {
    tags: [tag],
    summary,
    description,
    security: [{ bearerAuth: [] }],
    consumes: ["multipart/form-data"],
    response: {
      200: {
        type: "object",
        additionalProperties: true
      },
      400: {
        type: "object",
        properties: {
          error: { type: "string" },
          code: { type: "string" }
        }
      },
      404: {
        type: "object",
        properties: {
          error: { type: "string" },
          code: { type: "string" }
        }
      },
      422: {
        type: "object",
        properties: {
          error: { type: "string" },
          code: { type: "string" }
        }
      },
      401: {
        type: "object",
        properties: {
          error: { type: "string" }
        }
      }
    }
  };
}

function setDownload(reply, filename, contentType, buffer) {
  reply
    .header("Content-Type", contentType)
    .header(
      "Content-Disposition",
      `attachment; filename="${filename}"`
    );

  return reply.send(buffer);
}

function binaryFromResult(result) {
  const direct = toNodeBuffer(result);
  if (direct) return direct;

  if (!result || typeof result !== "object") return null;

  for (const key of ["data", "buffer", "output"]) {
    const value = toNodeBuffer(result[key]);
    if (value) return value;
  }

  return null;
}

// kordoc ParseOptions 중 불리언으로 «그대로 통과» 시키는 것들 (4.18.2). 필드를 안 주면 kordoc 기본값이다.
const PASS_THROUGH_BOOLEANS = [
  "scriptTags",
  "keepTrailingEmptyCols",
  "classifyTables",
  "keepEmptyParagraphs",
  "formulaOcr",
  "dedupeRunningHeaders",
  "inlineImages",
  "tables",
  "memos",
  "qrCodes",
  "dropBlankImages",
  "htmlCellLinks"
];

async function parseInput(file, fields = {}) {
  const ocr = ocrValue(fields.ocr);

  // kordoc ParseOptions.removeHeaderFooter 통과 (공식 옵션, 기본 true).
  // 🔴 2026-09-21: 켜져 있으면 «반복되는 진짜 제목»까지 지운다. 실측(48p 회계감사보고서):
  //    `### 대차대조표`·`### 주석`·단체협약 조항 본문이 삭제됐다. 상하 12% 안에서
  //    숫자를 # 로 뭉갠 패턴이 3개 페이지 이상 반복되면 제거 — 재무제표 항목 제목이 정확히 이 꼴이다.
  //    4페이지 이상 문서에서만 발동한다(kordoc: parsedPageCount >= 3).
  //    끄면 쪽번호가 본문에 남으므로 «우리 후처리에서» 걷어낼 것.
  //    필드를 안 주면 종전과 동일하게 동작한다.
  const opts = {
    filename: file.filename,
    mimeType: file.mimetype,
    ocr
  };
  if (fields.removeHeaderFooter !== undefined && fields.removeHeaderFooter !== "") {
    opts.removeHeaderFooter = boolValue(fields.removeHeaderFooter, true);
  }
  // kordoc ParseOptions.images 통과 (4.14.3+, 기본 true).
  // false 면 이미지 «바이트»만 빠진다 -- 자리 표시는 남고 글자·OCR 은 그대로다.
  // 최상위 images 는 cleanResult 가 어차피 지우지만 blocks[].imageData 는 나가므로
  // 기본값은 건드리지 않는다. 필드를 안 주면 종전과 동일하게 동작한다.
  if (fields.images !== undefined && fields.images !== "") {
    opts.images = boolValue(fields.images, true);
  }

  // kordoc ParseOptions.includeFieldPlaceholders 통과 (4.15.7+, 기본 false).
  // 🔴 우리가 올린 이슈(kordoc#92)의 수정이다. 4.14.3 부터 «미기입 누름틀 안내문»이
  //    마크다운에서 빠지는데, 공공기관 채용 서식은 대부분 «빈 양식» 으로 공시된다.
  //    안내문이 빠지면 「학교명 기재 금지」 같은 실질 규정이 사라져 표 껍데기만 남는다
  //    (실측: 같은 이력서 서식이 194자 -> 152자, 동종 25건 중 14건 동일 증상).
  //    채워진 문서를 읽을 때는 안내문이 잡음이므로 기본값(빼기)은 그대로 둔다.
  //    «빈 서식 자체가 대상» 일 때만 켠다. 필드를 안 주면 종전과 동일하게 동작한다.
  if (fields.includeFieldPlaceholders !== undefined && fields.includeFieldPlaceholders !== "") {
    opts.includeFieldPlaceholders = boolValue(fields.includeFieldPlaceholders, false);
  }

  // kordoc ParseOptions.plain 통과 (4.15.7+, 기본 false).
  // 그림 자리 표시·링크 URL·밑줄(<u>)·굵게(**) 표기를 빼고 글만 남긴다.
  // 제목·목록·표 «구조» 는 유지되고 blocks IR 도 그대로다 — 마크다운 표기만 빠진다.
  // 이미지 바이트를 따로 저장하지 않는 색인·RAG 소비자용:
  // images=false 로 부르면 ![image](image_001.png) 가 «가리키는 파일이 없는 링크» 로
  // 남는데, plain 은 그 자리 표시 자체를 뺀다. 둘은 같이 쓰라고 있는 옵션이다.
  if (fields.plain !== undefined && fields.plain !== "") {
    opts.plain = boolValue(fields.plain, false);
  }

  // kordoc ParseOptions.htmlTables 통과 (4.15.7+, 기본 false).
  // 모든 표를 HTML 로 낸다 — 파이프 표도 HTML 로 옮기고 태그를 한 줄씩 들여쓴다
  // (첫 행 <th>). 기본값에서는 병합·중첩 없는 표만 GFM 파이프 표로 나가므로
  // «표 모양이 두 가지» 인데, 이 옵션은 한 가지로 통일한다. HTML 표만 다루는
  // 소비자·채점기용이다. 켜면 출력이 커진다.
  if (fields.htmlTables !== undefined && fields.htmlTables !== "") {
    opts.htmlTables = boolValue(fields.htmlTables, false);
  }

  // kordoc ParseOptions.tableFormat 통과 (4.19.0+). "gfm" = 병합·중첩 표까지 HTML 없이 GFM 파이프 표로(세로 병합은 행마다 값 반복,
  // 중첩 표는 부모 표 뒤 독립 표 + parent_id 주석). 안 주면 종전과 «바이트 동일». htmlTables 와 같이 쓰면 kordoc 이 오류를 낸다.
  if (fields.tableFormat !== undefined && fields.tableFormat !== "") {
    const tf = String(fields.tableFormat).toLowerCase();
    if (tf !== "gfm") {
      const e = new Error('tableFormat must be "gfm" (or omitted)');
      e.statusCode = 400;
      throw e;
    }
    opts.tableFormat = tf;
  }

  // kordoc ParseOptions 나머지 전부 통과 (4.18.2). 필드를 안 주면 종전과 동일하게 동작한다 — 기본값을 여기서 정하지 않는다.
  for (const name of PASS_THROUGH_BOOLEANS) {
    if (fields[name] !== undefined && fields[name] !== "") {
      opts[name] = boolValue(fields[name], false);
    }
  }
  if (fields.layoutTables !== undefined && fields.layoutTables !== "") {
    const v = String(fields.layoutTables).toLowerCase();
    if (v !== "visual" && v !== "keep") {
      const e = new Error('layoutTables must be "visual" or "keep"');
      e.statusCode = 400;
      throw e;
    }
    opts.layoutTables = v;
  }
  // pages: "1-3" · "1,3,5-7" (1-based). PDF 는 쪽 단위, HWP/HWPX 는 섹션 단위 근사.
  if (fields.pages !== undefined && fields.pages !== "") {
    opts.pages = String(fields.pages);
  }
  // OCR 모델 프리셋 (kordoc 4.22.x). 값이 있을 때만 전달 — 안 주면 종전과 동일. 로컬 파일 경로·SHA 지정은 열지 않는다(프리셋 이름만).
  // ocr=false 여도 ocr 을 올리지 않는다.
  for (const [name, allowed] of [
    ["ocrRec", ["handwriting", "auto", "printed"]],
    ["ocrDet", ["mobile", "server", "medium"]],
    ["imageFormat", ["png", "webp"]],
    ["imagePlacement", ["page-end", "flow"]]
  ]) {
    if (fields[name] !== undefined && fields[name] !== "") {
      const v = String(fields[name]);
      if (!allowed.includes(v)) {
        const e = new Error(`${name} must be one of: ${allowed.join(", ")} (or omitted)`);
        e.statusCode = 400;
        throw e;
      }
      opts[name] = v;
    }
  }
  if (fields.ocrDetLongSide !== undefined && fields.ocrDetLongSide !== "") {
    const raw = String(fields.ocrDetLongSide);
    const n = Number(raw);
    if (!/^\d+$/.test(raw) || n < 32 || n > 4096) {
      const e = new Error("ocrDetLongSide must be an integer between 32 and 4096 (or omitted)");
      e.statusCode = 400;
      throw e;
    }
    opts.ocrDetLongSide = n;
  }
  // ocrLines (kordoc 4.24.x, API 1.10.0): 켜면 결과에 ocrLines 가 붙고 cleanResult 가 그대로 내보낸다.
  // 끄면(안 주거나 false) 엔진에 아무것도 넘기지 않아 종전과 산출이 같다. ocrRecDict(서버 로컬 모델 파일)는 열지 않는다.
  if (fields.ocrLines !== undefined && fields.ocrLines !== "") {
    const v = String(fields.ocrLines).toLowerCase();
    if (!["true", "false", "all"].includes(v)) {
      const e = new Error("ocrLines must be one of: true, false, all (or omitted)");
      e.statusCode = 400;
      throw e;
    }
    if (v !== "false") {
      opts.ocrLines = v === "all" ? "all" : true;
    }
  }
  // password: 암호가 걸린 HWPX·HWP3 용. 🔴 값은 로그·응답·오류 메시지에 남기지 않는다 — opts 를 통째로 기록하지 말 것.
  if (fields.password !== undefined && fields.password !== "") {
    opts.password = String(fields.password);
  }

  return withTimeout(() => kordoc.parse(file.buffer, opts));
}

/* ------------------------------------------------------------------ */
/* Public endpoints                                                    */
/* ------------------------------------------------------------------ */

app.get("/", async () => ({
  service: "@@BRAND@@ Kordoc API",
  version: API_VERSION,
  kordoc: kordoc.VERSION ?? "unknown",
  docs: "/docs",
  openapi: "/openapi.json",
  health: "/health"
}));

// 2026-09-27: /v1/ 별칭을 더한다. parse URL 에서 base 를 유도하는 프로브가
// /v1/health 를 찔러 404 를 받던 것을 막는다. 루트 경로는 그대로 둔다.
const healthPayload = async () => ({
  // ok 와 status 를 «둘 다» 낸다 — 두 대의 응답을 맞추되 어느 쪽 키를 읽던
  // 기존 소비자도 깨지지 않게 한다 (2026-09-27).
  ok: true,
  status: "ok",
  service: "kordoc",
  kordoc: kordoc.VERSION ?? "unknown",
  api: API_VERSION,
  activeJobs,
  queuedJobs: jobQueue.length,
  concurrency: CONCURRENCY
});
app.get("/health", healthPayload);
app.get("/v1/health", healthPayload);

// 2026-09-27: /v1/ 별칭을 더한다. parse URL 에서 base 를 유도하는 프로브가
// /v1/version 를 찔러 404 를 받던 것을 막는다. 루트 경로는 그대로 둔다.
const versionPayload = async () => ({
  service: "@@PFX@@-kordoc-api",
  api: API_VERSION,
  kordoc: kordoc.VERSION ?? "unknown",
  node: process.version
});
app.get("/version", versionPayload);
app.get("/v1/version", versionPayload);

app.get("/openapi.json", async () =>
  decorateOpenApi(app.swagger())
);

/* ------------------------------------------------------------------ */
/* Parse / analysis                                                    */
/* ------------------------------------------------------------------ */

app.post(
  "/v1/detect",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Parse",
      "Detect document format",
      "Detect document format without fully parsing it."
    )
  },
  async (request) => {
    const { files } = await readParts(request);
    const file = requireFile(files);

    // 동기 detectFormat 은 ZIP 을 전부 "hwpx" 로 답한다(상류 문서: 하위 호환). XLSX·DOCX·PPTX 를 가르려면 ZIP 안을 본다.
    // 못 가르면("unknown") 종전 답 그대로 둔다.
    let format = kordoc.detectFormat(file.buffer);
    if (format === "hwpx") {
      const b = file.buffer;
      const zip = await kordoc.detectZipFormat(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));
      if (zip && zip !== "unknown") format = zip;
    }

    return { format };
  }
);

app.post(
  "/v1/parse",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Parse",
      "Parse document",
      "Parse a Kordoc-supported document. OCR supports false, true and force."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);

    const includeBlocks = boolValue(
      fields.includeBlocks,
      true
    );

    const includeImages = boolValue(
      fields.includeImages,
      false
    );

    const result = await parseInput(file, fields);

    return cleanResult(result, includeBlocks, includeImages);
  }
);

app.post(
  "/v1/metadata",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Parse",
      "Extract document metadata",
      "Parse a document and return metadata and quality information without blocks."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);
    const r = await parseInput(file, fields);

    return {
      success: r.success,
      fileType: r.fileType,
      metadata: r.metadata,
      pageCount: r.pageCount,
      outline: r.outline,
      warnings: r.warnings,
      isImageBased: r.isImageBased,
      pageQuality: r.pageQuality,
      qualitySummary: r.qualitySummary,
      error: r.error,
      code: r.code
    };
  }
);

app.post(
  "/v1/parse/pages",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Parse",
      "Parse document by page",
      "Return page-level Markdown representation."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);
    const r = await parseInput(file, fields);

    if (!r.success) return r;

    const pages =
      r.pages ??
      (r.blocks ? kordoc.blocksToPages(r.blocks) : undefined);

    return {
      success: true,
      fileType: r.fileType,
      pageCount: r.pageCount ?? pages?.length,
      pages: pages ?? []
    };
  }
);

app.post(
  "/v1/parse/chunks",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "RAG",
      "Create RAG chunks",
      "Convert parsed Kordoc blocks into section or block granularity chunks."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);
    const r = await parseInput(file, fields);

    if (!r.success) return r;

    // parseInput 이 tableFormat 값을 이미 검증했다(gfm 이 아니면 400). 청크 렌더에도 같은 값을 넘긴다.
    const chunkTableFormat =
      String(fields.tableFormat ?? "").toLowerCase() === "gfm" ? "gfm" : undefined;

    const chunks = kordoc.blocksToChunks(r.blocks ?? [], {
      granularity:
        fields.granularity === "block" ? "block" : "section",
      includeTableCells: boolValue(
        fields.includeTableCells,
        false
      ),
      ...(chunkTableFormat ? { tableFormat: chunkTableFormat } : {})
    });

    return {
      success: true,
      fileType: r.fileType,
      chunkCount: chunks.length,
      chunks
    };
  }
);

app.post(
  "/v1/parse/table",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Parse",
      "Extract tables",
      "Parse the document and return table blocks."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);
    const r = await parseInput(file, fields);

    if (!r.success) return r;

    const tables = (r.blocks ?? [])
      .map((block, index) => ({
        block,
        index
      }))
      .filter(({ block }) =>
        block?.type === "table" && block.table
      )
      .map(({ block, index }) => ({
        index,
        pageNumber: block.pageNumber,
        table: block.table,
        markdown:
          typeof kordoc.blocksToMarkdown === "function"
            ? kordoc.blocksToMarkdown([block])
            : undefined
      }));

    return {
      success: true,
      fileType: r.fileType,
      tableCount: tables.length,
      tables
    };
  }
);

app.post(
  "/v1/compare",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Compare",
      "Compare two documents",
      "Parse two documents and return Kordoc block differences."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);

    const a = requireFile(files, "fileA");
    const b = requireFile(files, "fileB");

    const result = await withTimeout(() =>
      kordoc.compare(
        a.buffer,
        b.buffer,
        { ocr: ocrValue(fields.ocr) }
      )
    );

    return {
      success: true,
      result
    };
  }
);

/* ------------------------------------------------------------------ */
/* Forms                                                               */
/* ------------------------------------------------------------------ */

app.post(
  "/v1/form/parse",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Form",
      "Detect form fields",
      "Parse a document and infer form fields and schema."
    )
  },
  async (request) => {
    const { files } = await readParts(request);
    const file = requireFile(files);

    const r = await withTimeout(() =>
      kordoc.parse(file.buffer)
    );

    if (!r.success) return r;

    return {
      success: true,
      fileType: r.fileType,
      form: kordoc.extractFormFields(r.blocks ?? []),
      schema: kordoc.extractFormSchema(r.blocks ?? [])
    };
  }
);

app.post(
  "/v1/form/fill",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Form",
      "Fill document form",
      "Fill detected form fields and return Markdown or generated HWPX."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = files.file;
const templateName =
  fields.template !== undefined
    ? String(fields.template)
    : undefined;

let sourceBuffer;

if (file) {
  sourceBuffer = file.buffer;
} else if (templateName) {
  const template =
    kordoc.resolveBuiltinTemplate(templateName);

  if (!template) {
    return reply.code(400).send({
      error:
        "unknown built-in template; supported: gian, gian-simple, 일반기안문, 간이기안문"
    });
  }

  sourceBuffer =
    kordoc.readBuiltinTemplate(template);
} else {
  return reply.code(400).send({
    error: "file or template is required"
  });
}

    const values = jsonValue(fields.values, {});
    const formats = jsonValue(fields.formats, {});
    const requireUnique = booleanValue(
      fields.requireUnique,
      false
    );
    const maskValues = booleanValue(
      fields.maskValues,
      false
    );
    const outputFormat =
      fields.outputFormat || "markdown";

    if (
      !["markdown", "hwpx", "hwpx-preserve"]
        .includes(outputFormat)
    ) {
      return reply.code(400).send({
        error:
          "outputFormat must be markdown, hwpx, or hwpx-preserve"
      });
    }

    const inputs = buildFillInputs(values, formats);

    /*
     * markdown / hwpx use the same logical fill path:
     *
     *   parse
     *     -> fillFormFields
     *     -> blocksToMarkdown
     *
     * hwpx then regenerates a new HWPX from that Markdown.
     * This intentionally does not preserve source layout; callers that
     * need source formatting use hwpx-preserve.
     */
    if (
      outputFormat === "markdown" ||
      outputFormat === "hwpx"
    ) {
      const parsed = await withTimeout(() =>
        kordoc.parse(sourceBuffer)
      );

      if (!parsed.success) {
        return parsed;
      }

      const formInfo = kordoc.extractFormFields(
        parsed.blocks ?? []
      );

      const fillResult = requireUnique
        ? await kordoc.fillWithUniqueGuard(
            inputs,
            (vals, blocked) =>
              kordoc.fillFormFields(
                parsed.blocks ?? [],
                vals,
                blocked
              )
          )
        : {
            ...kordoc.fillFormFields(
              parsed.blocks ?? [],
              inputs
            ),
            rejected: []
          };

      const markdown = kordoc.blocksToMarkdown(
        fillResult.blocks
      );

      if (outputFormat === "markdown") {
        return {
          success: true,
          format: "markdown",
          filledCount:
            fillResult.filled?.length ?? 0,
          rejected:
            fillResult.rejected ?? [],
          unmatched:
            fillResult.unmatched ?? [],
          form: {
            fields:
              formInfo.fields?.length ?? 0,
            confidence:
              formInfo.confidence ?? 0
          },
          markdown:
            maskValues ? undefined : markdown,
          masked: maskValues
        };
      }

      const generated = await withTimeout(() =>
        kordoc.markdownToHwpx(markdown)
      );

      const buffer = toNodeBuffer(generated);

      if (!buffer) {
        return reply.code(500).send({
          error:
            "Kordoc HWPX generation did not return binary output"
        });
      }

      /*
       * maskValues controls response metadata / previews.
       * It must not remove the requested document output itself.
       */
      reply.header(
        "x-kordoc-filled-count",
        String(fillResult.filled?.length ?? 0)
      );
      reply.header(
        "x-kordoc-rejected-count",
        String(fillResult.rejected?.length ?? 0)
      );
      reply.header(
        "x-kordoc-unmatched-count",
        String(fillResult.unmatched?.length ?? 0)
      );
      reply.header(
        "x-kordoc-mask-values",
        String(maskValues)
      );

      return setDownload(
        reply,
        "filled.hwpx",
        "application/hwp+zip",
        buffer
      );
    }

    /*
     * hwpx-preserve:
     * fill the existing HWPX package directly.
     */
    const format = kordoc.detectFormat(sourceBuffer);

    if (format !== "hwpx") {
      return reply.code(400).send({
        error:
          `hwpx-preserve requires HWPX input (detected: ${format})`
      });
    }

    const hwpxResult = requireUnique
      ? await kordoc.fillWithUniqueGuard(
          inputs,
          (vals, blocked) =>
            kordoc.fillHwpx(
              sourceBuffer,
              vals,
              blocked
            )
        )
      : {
          ...await kordoc.fillHwpx(
            sourceBuffer,
            inputs
          ),
          rejected: []
        };

    const buffer = binaryFromResult(hwpxResult);

    if (!buffer) {
      return reply.code(500).send({
        error:
          "Kordoc form fill did not return binary output"
      });
    }

    reply.header(
      "x-kordoc-filled-count",
      String(hwpxResult.filled?.length ?? 0)
    );
    reply.header(
      "x-kordoc-rejected-count",
      String(hwpxResult.rejected?.length ?? 0)
    );
    reply.header(
      "x-kordoc-unmatched-count",
      String(hwpxResult.unmatched?.length ?? 0)
    );
    reply.header(
      "x-kordoc-mask-values",
      String(maskValues)
    );

    return setDownload(
      reply,
      "filled.hwpx",
      "application/hwp+zip",
      buffer
    );
  }
);

/* ------------------------------------------------------------------ */
/* Document mutation / generation                                     */
/* ------------------------------------------------------------------ */

app.post(
  "/v1/document/patch",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Patch HWP/HWPX",
      "Patch an existing HWP or HWPX using edited Markdown."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);

    if (!fields.markdown) {
      return reply.code(400).send({
        error: "markdown is required"
      });
    }

    const options = jsonValue(fields.options, {});
    const format = kordoc.detectFormat(file.buffer);

    let result;

    if (format === "hwpx") {
      result = await withTimeout(() =>
        kordoc.patchHwpx(
          file.buffer,
          String(fields.markdown),
          options
        )
      );
    } else if (format === "hwp") {
      result = await withTimeout(() =>
        kordoc.patchHwp(
          file.buffer,
          String(fields.markdown),
          options
        )
      );
    } else {
      return reply.code(400).send({
        error: `patch supports HWP/HWPX only; detected ${format}`
      });
    }

    if (result?.success === false) {
      return reply.code(422).send(result);
    }

    const buffer = binaryFromResult(result);

    if (!buffer) {
      return reply.code(500).send({
        error: "patch operation did not return document binary",
        result: cleanResult(result)
      });
    }

    return setDownload(
      reply,
      format === "hwp" ? "patched.hwp" : "patched.hwpx",
      format === "hwp"
        ? "application/x-hwp"
        : "application/hwp+zip",
      buffer
    );
  }
);

app.post(
  "/v1/document/profile/extract",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Extract HWPX format profile",
      "Extract table border, shading, column width and cell font profile from a reference HWPX."
    )
  },
  async (request, reply) => {
    const { files } = await readParts(request);
    const file = requireFile(files);

    const format = kordoc.detectFormat(
      file.buffer
    );

    if (format !== "hwpx") {
      return reply.code(400).send({
        error:
          `profile extraction requires HWPX input (detected: ${format})`
      });
    }

    const profile = await withTimeout(() =>
      kordoc.hwpxToProfile(file.buffer)
    );

    return {
      success: true,
      format: "hwpx-profile",
      tableCount:
        profile.tables?.length ?? 0,
      profile
    };
  }
);

app.post(
  "/v1/document/generate/hwpx",
  {
    preHandler: requireAuth,
    schema: {
      tags: ["Document"],
      summary: "Generate HWPX from Markdown",
      security: [{ bearerAuth: [] }],
      response: {
        200: {
          type: "object",
          additionalProperties: true
        },
        400: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        404: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        422: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        401: {
          type: "object",
          properties: {
            error: { type: "string" }
          }
        }
      },
    }
  },
  async (request, reply) => {
    const { markdown, options = {} } = request.body ?? {};

    if (typeof markdown !== "string") {
      return reply.code(400).send({
        error: "markdown is required"
      });
    }

    const output = await withTimeout(() =>
      kordoc.markdownToHwpx(markdown, options)
    );

    const buffer = toNodeBuffer(output);

    if (!buffer) {
      return reply.code(500).send({
        error: "HWPX generation did not return binary"
      });
    }

    return setDownload(
      reply,
      "generated.hwpx",
      "application/hwp+zip",
      buffer
    );
  }
);

app.post(
  "/v1/document/generate/hwpx/advanced",
  {
    preHandler: requireAuth,
    schema: {
      tags: ["Document"],
      summary: "Generate HWPX via official Kordoc MCP",
      description:
        "High-level HWPX generation with official Kordoc generate_document semantics. " +
        "Accepts markdown, MCP options JSON, one optional profile JSON file, " +
        "and repeated image file fields.",
      security: [{ bearerAuth: [] }],
      response: {
        200: {
          type: "object",
          additionalProperties: true
        },
        400: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        404: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        422: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        401: {
          type: "object",
          properties: {
            error: { type: "string" }
          }
        }
      },
      consumes: ["multipart/form-data"]
    }
  },
  async (request, reply) => {
    const {
      fields,
      profile,
      template,
      images
    } = await readAdvancedGenerateParts(request);

    const markdown =
      fields.markdown !== undefined
        ? String(fields.markdown)
        : "";

    if (!markdown.trim()) {
      return reply.code(400).send({
        error: "markdown is required"
      });
    }

    const options = jsonValue(fields.options, {});

    if (
      !options ||
      typeof options !== "object" ||
      Array.isArray(options)
    ) {
      return reply.code(400).send({
        error: "options must be a JSON object"
      });
    }

    const {
      markdown: _ignoredMarkdown,
      output_path: _ignoredOutputPath,
      profile_path: _ignoredProfilePath,
      image_dir: _ignoredImageDir,
      ...mcpOptions
    } = options;

    const buffer = await withSlot(() =>
      withTempWorkspace(async (root) => {
        const outputPath =
          join(root, "generated.hwpx");

        let profilePath;

        if (profile) {
          profilePath = join(root, "profile.json");

          let profileJson;

          try {
            profileJson = JSON.parse(
              profile.buffer.toString("utf8")
            );
          } catch {
            const e = new Error(
              "profile must be a valid JSON file"
            );
            e.statusCode = 400;
            throw e;
          }

          const normalizedProfile =
            profileJson &&
            typeof profileJson === "object" &&
            !Array.isArray(profileJson) &&
            profileJson.profile &&
            typeof profileJson.profile === "object" &&
            !Array.isArray(profileJson.profile)
              ? profileJson.profile
              : profileJson;

          await writeFile(
            profilePath,
            JSON.stringify(normalizedProfile)
          );
        }

        let imageDir;

        if (images.length > 0) {
          imageDir = join(root, "images");
          await mkdir(imageDir, {
            recursive: true
          });

          const seen = new Set();

          for (const image of images) {
            const name =
              safeUploadFilename(image.filename);

            if (
              !/^[A-Za-z0-9._-]+\.[A-Za-z0-9]+$/.test(name) ||
              name.includes("..")
            ) {
              const e = new Error(
                `invalid image filename: ${name}`
              );
              e.statusCode = 400;
              throw e;
            }

            if (seen.has(name)) {
              const e = new Error(
                `duplicate image filename: ${name}`
              );
              e.statusCode = 400;
              throw e;
            }

            seen.add(name);

            await writeFile(
              join(imageDir, name),
              image.buffer
            );
          }
        }

        let templatePath;

        if (template) {
          templatePath = join(root, "template.hwpx");
          await writeFile(templatePath, template.buffer);
        }

        const toolArguments = {
          ...mcpOptions,
          markdown,
          output_path: outputPath,
          ...(templatePath
            ? { template_path: templatePath }
            : {}),
          ...(profilePath
            ? { profile_path: profilePath }
            : {}),
          ...(imageDir
            ? { image_dir: imageDir }
            : {})
        };

        const result = await runKordocMcpTool(
          root,
          "generate_document",
          toolArguments
        );

        if (result?.isError) {
          const message = (result.content ?? [])
            .filter(
              (item) =>
                item &&
                item.type === "text"
            )
            .map((item) => item.text)
            .join("\n")
            .trim();

          const e = new Error(
            message ||
            "Kordoc generate_document failed"
          );
          e.statusCode = 400;
          throw e;
        }

        return readFile(outputPath);
      })
    );

    const ab = buffer.buffer.slice(
      buffer.byteOffset,
      buffer.byteOffset + buffer.byteLength
    );

    if (kordoc.detectFormat(ab) !== "hwpx") {
      return reply.code(500).send({
        error:
          "generated output is not a valid HWPX container"
      });
    }

    return setDownload(
      reply,
      "generated.hwpx",
      "application/hwp+zip",
      buffer
    );
  }
);

app.post(
  "/v1/document/generate/pdf",
  {
    preHandler: requireAuth,
    schema: {
      tags: ["Document"],
      summary: "Generate PDF from Markdown",
      security: [{ bearerAuth: [] }],
      response: {
        200: {
          type: "object",
          additionalProperties: true
        },
        400: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        404: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        422: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        401: {
          type: "object",
          properties: {
            error: { type: "string" }
          }
        }
      },
    }
  },
  async (request, reply) => {
    const { markdown, options = {} } = request.body ?? {};

    if (typeof markdown !== "string") {
      return reply.code(400).send({
        error: "markdown is required"
      });
    }

    const output = await withTimeout(() =>
      kordoc.markdownToPdf(markdown, options)
    );

    const buffer = toNodeBuffer(output);

    if (!buffer) {
      return reply.code(500).send({
        error: "PDF generation did not return binary"
      });
    }

    return setDownload(
      reply,
      "generated.pdf",
      "application/pdf",
      buffer
    );
  }
);

app.post(
  "/v1/document/render",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Render HWPX to SVG",
      "Render an HWPX document using Kordoc's SVG renderer. " +
        "For HWPX files without Hancom linesegarray layout cache, " +
        "pass options={\"reflow\":true}. Kordoc-generated HWPX normally requires reflow=true."
    )
  },
  async (request) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);
    const options = jsonValue(fields.options, {});

    return withTimeout(() =>
      kordoc.renderHwpxToSvg(file.buffer, options)
    );
  }
);

app.post(
  "/v1/document/render/native",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Render HWP/HWPX via native Kordoc MCP",
      "Render HWP or HWPX using Kordoc native render_document. " +
      "Supports PNG/JPEG JSON responses."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);

    const fileFormat = ["svg", "html", "pdf"].includes(fields.format)
      ? fields.format
      : null;

    const format =
      fields.format === "jpeg" ? "jpeg" : "png";

    let highlights;

    if (fields.highlights) {
      highlights = jsonValue(fields.highlights);

      if (!Array.isArray(highlights)) {
        return reply.code(400).send({
          error: "highlights must be a JSON array"
        });
      }
    }

    const maxWidthPx =
      fields.maxWidthPx !== undefined
        ? Number(fields.maxWidthPx)
        : undefined;

    if (
      maxWidthPx !== undefined &&
      (!Number.isInteger(maxWidthPx) ||
        maxWidthPx < 200 ||
        maxWidthPx > 4000)
    ) {
      return reply.code(400).send({
        error: "maxWidthPx must be an integer between 200 and 4000"
      });
    }

    return withSlot(() =>
      withTempWorkspace(async (root) => {
        const name = safeUploadFilename(
          file.filename || "document.hwpx"
        );

        if (!/\.(hwpx|hwp)$/i.test(name)) {
          return reply.code(400).send({
            error: "native render supports HWP/HWPX only"
          });
        }

        const inputPath = join(root, name);
        await writeFile(inputPath, file.buffer);

        const outputBase = fileFormat ? join(root, `rendered.${fileFormat}`) : null;
        const rendered = await runKordocMcpTool(
          root,
          "render_document",
          {
            file_path: inputPath,
            format: fileFormat || format,
            ...(outputBase ? { output_path: outputBase } : {}),
            ...(highlights ? { highlights } : {}),
            ...(fields.reflowMode
              ? { reflow_mode: String(fields.reflowMode) }
              : {}),
            ...(fields.pages
              ? { pages: String(fields.pages) }
              : {}),
            ...(maxWidthPx !== undefined
              ? { max_width_px: maxWidthPx }
              : {})
          }
        );

        if (!fileFormat || rendered?.isError) return rendered;
        const mimeTypes = {
          svg: "image/svg+xml",
          html: "text/html",
          pdf: "application/pdf"
        };
        const names = (await readdir(root))
          .filter((n) => n.startsWith("rendered") && n.endsWith(`.${fileFormat}`))
          .sort();
        const outputs = [];
        for (const n of names) {
          outputs.push({
            name: n,
            mimeType: mimeTypes[fileFormat],
            data: (await readFile(join(root, n))).toString("base64")
          });
        }
        return { ...rendered, files: outputs };
      })
    );
  }
);
app.post(
  "/v1/document/extract-tables",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Extract and classify tables via native Kordoc MCP",
      "Use Kordoc native extract_tables to classify HWP/HWPX tables, " +
      "return bbox/region metadata, and optionally include cell text."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);

    const visualAllowed = new Set([
      "none",
      "non-tabular",
      "non-tabular-and-uncertain",
      "all"
    ]);

    const visual =
      fields.visual !== undefined
        ? String(fields.visual)
        : "none";

    if (!visualAllowed.has(visual)) {
      return reply.code(400).send({
        error:
          "visual must be none, non-tabular, non-tabular-and-uncertain, or all"
      });
    }

    const format =
      fields.format === "jpeg" ? "jpeg" : "png";

    const paddingPt =
      fields.paddingPt !== undefined
        ? Number(fields.paddingPt)
        : 0;

    if (
      !Number.isFinite(paddingPt) ||
      paddingPt < 0 ||
      paddingPt > 100
    ) {
      return reply.code(400).send({
        error: "paddingPt must be between 0 and 100"
      });
    }

    const cells =
      String(fields.cells ?? "false") === "true";

    return withSlot(() =>
      withTempWorkspace(async (root) => {
        const name = safeUploadFilename(
          file.filename || "document.hwpx"
        );

        if (!/\.(hwpx|hwp)$/i.test(name)) {
          return reply.code(400).send({
            error: "extract-tables supports HWP/HWPX only"
          });
        }

        const inputPath = join(root, name);
        await writeFile(inputPath, file.buffer);

        const returnFiles = String(fields.returnFiles ?? "false") === "true";
        const tablesDir = join(root, "tables");

        const extracted = await runKordocMcpTool(
          root,
          "extract_tables",
          {
            file_path: inputPath,
            visual,
            format,
            padding_pt: paddingPt,
            cells,
            ...(returnFiles ? { output_dir: tablesDir } : {})
          }
        );

        return returnFiles ? await attachFiles(extracted, tablesDir) : extracted;
      })
    );
  }
);


app.post(
  "/v1/document/crop-regions",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Crop rendered document regions via native Kordoc MCP",
      "Use Kordoc native crop_regions to crop table, image, paragraph, " +
      "or shape regions from HWP/HWPX rendering output."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);

    let target = ["table"];

    if (fields.target) {
      target = jsonValue(fields.target);

      if (!Array.isArray(target) || target.length === 0) {
        return reply.code(400).send({
          error: "target must be a non-empty JSON array"
        });
      }

      const allowed = new Set([
        "table",
        "image",
        "paragraph",
        "shape"
      ]);

      if (target.some((v) => !allowed.has(v))) {
        return reply.code(400).send({
          error:
            "target values must be table, image, paragraph, or shape"
        });
      }
    }

    const format =
      fields.format === "jpeg" ? "jpeg" : "png";

    const paddingPt =
      fields.paddingPt !== undefined
        ? Number(fields.paddingPt)
        : 0;

    if (
      !Number.isFinite(paddingPt) ||
      paddingPt < 0 ||
      paddingPt > 100
    ) {
      return reply.code(400).send({
        error: "paddingPt must be between 0 and 100"
      });
    }

    return withSlot(() =>
      withTempWorkspace(async (root) => {
        const name = safeUploadFilename(
          file.filename || "document.hwpx"
        );

        if (!/\.(hwpx|hwp)$/i.test(name)) {
          return reply.code(400).send({
            error: "crop-regions supports HWP/HWPX only"
          });
        }

        const inputPath = join(root, name);
        const outputDir = join(root, "cropped");

        await writeFile(inputPath, file.buffer);

        const cropped = await runKordocMcpTool(
          root,
          "crop_regions",
          {
            file_path: inputPath,
            output_dir: outputDir,
            target,
            format,
            ...(fields.pages
              ? { pages: String(fields.pages) }
              : {}),
            padding_pt: paddingPt
          }
        );

        return String(fields.returnFiles ?? "false") === "true"
          ? await attachFiles(cropped, outputDir)
          : cropped;
      })
    );
  }
);


app.post(
  "/v1/document/seal/native",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Place seal via native Kordoc MCP",
      "Place a seal/signature image on an HWPX anchor using Kordoc native place_seal."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);

    const file = requireFile(files, "file");
    const image = requireFile(files, "image");

    const anchorText =
      fields.anchor !== undefined
        ? String(fields.anchor)
        : "(인)";

    const occurrence =
      fields.occurrence !== undefined
        ? Number(fields.occurrence)
        : 0;

    if (
      !Number.isInteger(occurrence) ||
      occurrence < 0
    ) {
      return reply.code(400).send({
        error: "occurrence must be a non-negative integer"
      });
    }

    const mode =
      fields.mode !== undefined
        ? String(fields.mode)
        : "auto";

    if (!["auto", "overlap", "right"].includes(mode)) {
      return reply.code(400).send({
        error: "mode must be auto, overlap, or right"
      });
    }

    const numberField = (name) => {
      if (fields[name] === undefined || fields[name] === "") {
        return undefined;
      }

      const value = Number(fields[name]);

      if (!Number.isFinite(value)) {
        const e = new Error(`${name} must be numeric`);
        e.statusCode = 400;
        throw e;
      }

      return value;
    };

    const sizeMm = numberField("sizeMm");
    const dxMm = numberField("dxMm");
    const dyMm = numberField("dyMm");

    if (sizeMm !== undefined && sizeMm <= 0) {
      return reply.code(400).send({
        error: "sizeMm must be greater than 0"
      });
    }

    return withSlot(() =>
      withTempWorkspace(async (root) => {
        const inputName = safeUploadFilename(
          file.filename || "document.hwpx"
        );

        if (!/\.hwpx$/i.test(inputName)) {
          return reply.code(400).send({
            error: "native seal supports HWPX only"
          });
        }

        const imageName = safeUploadFilename(
          image.filename || "seal.png"
        );

        const inputPath = join(root, inputName);
        const imagePath = join(root, imageName);
        const outputPath = join(root, "sealed.hwpx");

        await writeFile(inputPath, file.buffer);
        await writeFile(imagePath, image.buffer);

        const result = await runKordocMcpTool(
          root,
          "place_seal",
          {
            file_path: inputPath,
            image_path: imagePath,
            anchor: anchorText,
            occurrence,
            mode,
            output_path: outputPath,
            ...(sizeMm !== undefined
              ? { size_mm: sizeMm }
              : {}),
            ...(dxMm !== undefined
              ? { dx_mm: dxMm }
              : {}),
            ...(dyMm !== undefined
              ? { dy_mm: dyMm }
              : {})
          }
        );

        if (result?.isError) {
          const message = (result.content ?? [])
            .filter(
              (item) =>
                item &&
                item.type === "text" &&
                typeof item.text === "string"
            )
            .map((item) => item.text)
            .join("\n")
            .trim();

          return reply.code(400).send({
            error: message || "Kordoc place_seal failed"
          });
        }

        const buffer = await readFile(outputPath);

        return setDownload(
          reply,
          "sealed.hwpx",
          "application/hwp+zip",
          buffer
        );
      })
    );
  }
);


app.post(
  "/v1/document/patch/native",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Patch HWP/HWPX via native Kordoc MCP",
      "Patch an existing HWP or HWPX using Kordoc native patch_document. " +
      "The edited Markdown should preserve the original block order and structure."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = requireFile(files);

    if (
      fields.markdown === undefined ||
      !String(fields.markdown).trim()
    ) {
      return reply.code(400).send({
        error: "markdown is required"
      });
    }

    return withSlot(() =>
      withTempWorkspace(async (root) => {
        const inputName = safeUploadFilename(
          file.filename || "document.hwpx"
        );

        if (!/\.(hwpx|hwp)$/i.test(inputName)) {
          return reply.code(400).send({
            error: "native patch supports HWP/HWPX only"
          });
        }

        const ext = inputName.toLowerCase().endsWith(".hwp")
          ? ".hwp"
          : ".hwpx";

        const inputPath = join(root, inputName);
        const outputPath = join(root, `patched${ext}`);

        await writeFile(inputPath, file.buffer);

        const result = await runKordocMcpTool(
          root,
          "patch_document",
          {
            file_path: inputPath,
            edited_markdown: String(fields.markdown),
            output_path: outputPath,
            ...(fields.structure !== undefined
              ? { structure: booleanValue(fields.structure, true) }
              : {})
          }
        );

        if (result?.isError) {
          const message = (result.content ?? [])
            .filter(
              (item) =>
                item &&
                item.type === "text" &&
                typeof item.text === "string"
            )
            .map((item) => item.text)
            .join("\n")
            .trim();

          return reply.code(400).send({
            error: message || "Kordoc patch_document failed"
          });
        }

        const buffer = await readFile(outputPath);

        return setDownload(
          reply,
          ext === ".hwp" ? "patched.hwp" : "patched.hwpx",
          ext === ".hwp"
            ? "application/x-hwp"
            : "application/hwp+zip",
          buffer
        );
      })
    );
  }
);

app.post(
  "/v1/document/validate",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Validate HWPX",
      "Validate HWPX ZIP structure and XML consistency."
    )
  },
  async (request) => {
    const { files } = await readParts(request);
    const file = requireFile(files);

    return withTimeout(() =>
      kordoc.validateHwpx(file.buffer)
    );
  }
);

app.post(
  "/v1/document/seal",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Place seal into HWPX",
      "Place an uploaded seal image at one or more anchor positions in an HWPX."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);

    const file = requireFile(files, "file");
    const image = requireFile(files, "image");
    const ops = jsonValue(fields.ops);

    if (!Array.isArray(ops) || ops.length === 0) {
      return reply.code(400).send({
        error: "ops must be a non-empty JSON array"
      });
    }

    const preparedOps = ops.map((op) => ({
      ...op,
      image: image.buffer
    }));

    const result = await withTimeout(() =>
      kordoc.placeSealHwpx(
        file.buffer,
        preparedOps
      )
    );

    const buffer = binaryFromResult(result);

    if (!buffer) {
      return reply.code(500).send({
        error: "seal operation did not return HWPX binary",
        result: cleanResult(result)
      });
    }

    return setDownload(
      reply,
      "sealed.hwpx",
      "application/hwp+zip",
      buffer
    );
  }
);

/* ------------------------------------------------------------------ */
/* Redaction                                                           */
/* ------------------------------------------------------------------ */

app.post(
  "/v1/document/redact",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Redaction",
      "Redact sensitive values from a document",
      "Detect sensitive values and preserve HWP/HWPX formatting when possible."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(
      request
    );
    const file = requireFile(files);

    const rules = jsonValue(
      fields.rules,
      undefined
    );
    const maskChar =
      fields.maskChar || undefined;
    const dryRun = booleanValue(
      fields.dryRun,
      false
    );

    if (
      rules !== undefined &&
      !Array.isArray(rules)
    ) {
      return reply.code(400).send({
        error: "rules must be a JSON array"
      });
    }

    if (
      maskChar !== undefined &&
      [...String(maskChar)].length !== 1
    ) {
      return reply.code(400).send({
        error:
          "maskChar must be exactly one character"
      });
    }

    const format = kordoc.detectFormat(
      file.buffer
    );

    const parsed = await withTimeout(() =>
      kordoc.parse(file.buffer)
    );

    if (!parsed.success) {
      return parsed;
    }

    const options = {
      ...(rules !== undefined
        ? { rules }
        : {}),
      ...(maskChar !== undefined
        ? { maskChar }
        : {})
    };

    const redacted = kordoc.redactMarkdown(
      parsed.markdown,
      options
    );

    /*
     * Never return raw matched sensitive values in report metadata.
     */
    const safeHits = (
      redacted.hits ?? []
    ).map((hit) => ({
      rule: hit.rule,
      masked: hit.masked
    }));

    const report = {
      success: true,
      format,
      dryRun,
      hitCount: safeHits.length,
      hits: safeHits,
      maskedMarkdown: redacted.text
    };

    if (dryRun) {
      return report;
    }

    const patchable =
      format === "hwpx" ||
      format === "hwp";

    if (!patchable) {
      return {
        ...report,
        dryRun: false,
        outputFormat: "markdown"
      };
    }

    /*
     * Stable REST behavior:
     * for HWP/HWPX non-dry requests always return document binary.
     * With zero hits this is the original byte stream.
     */
    let buffer = file.buffer;
    let skippedCount = 0;

    if (safeHits.length > 0) {
      const result =
        format === "hwp"
          ? await kordoc.patchHwp(
              new Uint8Array(file.buffer),
              redacted.text
            )
          : await kordoc.patchHwpx(
              new Uint8Array(file.buffer),
              redacted.text
            );

      if (!result.success) {
        return reply.code(500).send({
          error:
            result.error ||
            "Kordoc redaction patch failed"
        });
      }

      const patched = binaryFromResult(
        result
      );

      if (!patched) {
        return reply.code(500).send({
          error:
            "Kordoc redaction patch did not return document binary"
        });
      }

      buffer = patched;
      skippedCount =
        result.skipped?.length ?? 0;
    }

    reply.header(
      "x-kordoc-redaction-hits",
      String(safeHits.length)
    );
    reply.header(
      "x-kordoc-redaction-skipped",
      String(skippedCount)
    );

    return setDownload(
      reply,
      format === "hwp"
        ? "redacted.hwp"
        : "redacted.hwpx",
      format === "hwp"
        ? "application/x-hwp"
        : "application/hwp+zip",
      buffer
    );
  }
);

// 공문서 표기법(+선택: 개조식 문체) 검수 — CLI `kordoc lint [--munche]` 와 같은 규격.
// 검수는 조언용이다. error 가 있으면 ok:false 로 알리되 HTTP 는 200 이다(CLI 는 exit 1).
app.post(
  "/v1/document/lint",
  {
    preHandler: requireAuth,
    schema: {
      tags: ["Document"],
      summary: "Lint Korean public-document notation and style",
      security: [{ bearerAuth: [] }],
      response: {
        200: {
          type: "object",
          additionalProperties: true
        },
        400: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        401: {
          type: "object",
          properties: {
            error: { type: "string" }
          }
        }
      }
    }
  },
  async (request, reply) => {
    const { text, munche } = request.body ?? {};

    if (typeof text !== "string" || text === "") {
      return reply.code(400).send({
        error: "text is required"
      });
    }

    const gongmun = kordoc.lintGongmunText(text);
    const result = { gongmun };
    let findings = gongmun;

    if (booleanValue(munche, false)) {
      result.munche = kordoc.lintMuncheText(text);
      findings = findings.concat(result.munche);
    }

    const errors = findings.filter((f) => f.severity === "error").length;

    return {
      ok: errors === 0,
      errors,
      warnings: findings.length - errors,
      ...result
    };
  }
);

app.post(
  "/v1/document/lint/full",
  {
    preHandler: requireAuth,
    schema: routeSchema(
      "Document",
      "Lint via official Kordoc lint_document (all options)",
      "API 1.9.0+. Exactly one of file (any supported document), text or blocks (JSON array). "
      + "Booleans munche, slop, logic, numbers, budget, gate and preset follow the official "
      + "lint_document tool. /v1/document/lint is unchanged."
    )
  },
  async (request, reply) => {
    const { files, fields } = await readParts(request);
    const file = files.file;
    const toolArguments = {};

    for (const key of ["munche", "slop", "logic", "numbers", "budget", "gate"]) {
      if (fields[key] !== undefined) {
        toolArguments[key] = booleanValue(fields[key], false);
      }
    }
    if (fields.preset) toolArguments.preset = String(fields.preset);
    if (fields.text !== undefined) toolArguments.text = String(fields.text);
    if (fields.blocks !== undefined) {
      const blocks = jsonValue(fields.blocks);
      if (!Array.isArray(blocks)) {
        return reply.code(400).send({ error: "blocks must be a JSON array" });
      }
      toolArguments.blocks = blocks;
    }

    const sources = [file, toolArguments.text, toolArguments.blocks]
      .filter((v) => v !== undefined).length;
    if (sources !== 1) {
      return reply.code(400).send({
        error: "give exactly one of file, text or blocks"
      });
    }

    return withSlot(() =>
      withTempWorkspace(async (root) => {
        if (file) {
          const name = safeUploadFilename(file.filename || "document");
          const inputPath = join(root, name);
          await writeFile(inputPath, file.buffer);
          toolArguments.file_path = inputPath;
        }
        const result = await runKordocMcpTool(root, "lint_document", toolArguments);
        const text = (result.content ?? [])
          .filter((item) => item && item.type === "text" && typeof item.text === "string")
          .map((item) => item.text)
          .join("\n")
          .trim();
        if (result?.isError) {
          return reply.code(400).send({ error: text || "Kordoc lint_document failed" });
        }
        try {
          return JSON.parse(text);
        } catch {
          return { result: text };
        }
      })
    );
  }
);

app.post(
  "/v1/document/redact/text",
  {
    preHandler: requireAuth,
    schema: {
      tags: ["Redaction"],
      summary: "Redact sensitive values from plain text",
      security: [{ bearerAuth: [] }],
      response: {
        200: {
          type: "object",
          additionalProperties: true
        },
        400: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        404: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        422: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        401: {
          type: "object",
          properties: {
            error: { type: "string" }
          }
        }
      },
    }
  },
  async (request, reply) => {
    const { text, options = {} } = request.body ?? {};

    if (typeof text !== "string") {
      return reply.code(400).send({
        error: "text is required"
      });
    }

    return kordoc.redactText(text, options);
  }
);

app.post(
  "/v1/document/redact/markdown",
  {
    preHandler: requireAuth,
    schema: {
      tags: ["Redaction"],
      summary: "Redact sensitive values from Markdown",
      security: [{ bearerAuth: [] }],
      response: {
        200: {
          type: "object",
          additionalProperties: true
        },
        400: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        404: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        422: {
          type: "object",
          properties: {
            error: { type: "string" },
            code: { type: "string" }
          }
        },
        401: {
          type: "object",
          properties: {
            error: { type: "string" }
          }
        }
      },
    }
  },
  async (request, reply) => {
    const { markdown, options = {} } = request.body ?? {};

    if (typeof markdown !== "string") {
      return reply.code(400).send({
        error: "markdown is required"
      });
    }

    return kordoc.redactMarkdown(markdown, options);
  }
);

/* ------------------------------------------------------------------ */

// 2026-09-27: kordoc 의 KordocError 에는 statusCode 가 없어 전부 500 으로 떨어졌다.
// 「한컴 저장 HWPX 만 렌더 가능」 같은 입력 조건까지 500 이 되면 호출부가 서버 장애로
// 보고 재시도·서킷브레이커를 발동시킨다. 라이브러리가 HTTP 를 모르는 건 당연하고,
// 매핑은 우리 몫이다.
//
// 422 인 이유: 요청 «자체» 는 올바르다. 문서가 처리 불가일 뿐이라 400 이 아니다.
// instanceof 로 못 거른다 — KordocError 는 dist/index.d.ts 에 클래스로 export 되지
// 않고 doc comment 에만 나온다. 그래서 name 으로 식별한다.
//
// 4.15.6 의 ErrorCode 13종 중 «서버» 문제는 MISSING_DEPENDENCY 뿐이다
// (모델 파일·onnxruntime 누락 — 우리가 고칠 문제다). 나머지는 전부 입력 조건이다:
// EMPTY_INPUT UNSUPPORTED_FORMAT ENCRYPTED DRM_PROTECTED CORRUPTED DECOMPRESSION_BOMB
// ZIP_BOMB IMAGE_BASED_PDF NO_SECTIONS PARSE_ERROR OUTPUT_TOO_LARGE
const KORDOC_SERVER_CODES = new Set(["MISSING_DEPENDENCY"]);

function httpStatusFor(error) {
  if (Number(error.statusCode) >= 400) return Number(error.statusCode);
  if (error.name !== "KordocError") return 500;
  if (error.code === "FILE_NOT_FOUND") return 404;
  if (KORDOC_SERVER_CODES.has(error.code)) return 500;
  return 422;
}

// 요청 추적: x-request-id 요청 헤더가 안전한 문자열이면 그대로, 아니면 새로 만들어 응답 헤더로 돌려준다.
// (본문에는 넣지 않는다 — 두 환경의 응답 본문이 갈라지지 않게.)
app.addHook("onRequest", (request, reply, done) => {
  const incoming = request.headers["x-request-id"];
  const id =
    typeof incoming === "string" && /^[A-Za-z0-9._:-]{1,128}$/.test(incoming)
      ? incoming
      : globalThis.crypto.randomUUID();
  reply.header("x-request-id", id);
  done();
});

app.setErrorHandler((error, request, reply) => {
  request.log.error(error);

  const status = httpStatusFor(error);

  const body = { error: error.message || "Internal Server Error" };
  // 호출부가 메시지 «문자열» 을 파싱하지 않아도 되도록 코드를 함께 낸다.
  // 다만 code 가 없는 KordocError 도 있다 (render 가 그렇다).
  if (error.code) body.code = error.code;

  reply.code(status).send(body);
});

await app.listen({
  host: "0.0.0.0",
  port: PORT
});
