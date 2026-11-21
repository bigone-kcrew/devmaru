#!/usr/bin/env node

import { spawn } from "node:child_process";
import { access, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { constants as fsConstants } from "node:fs";
import { isAbsolute, join, resolve as nodeResolve } from "node:path";

import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from "@modelcontextprotocol/sdk/types.js";

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

// @@PFX@@-mcp-hub 자식(AI_MCP_HUB_CHILD=1)은 세션별 작업 디렉터리를 알 수 없다 → 상대 경로는 거부하고 절대 경로를 다시 요구한다(stdio 로 직접 뜬 경우는 종전과 같다).
const HUB_CHILD = process.env.AI_MCP_HUB_CHILD === "1";
function absInHub(p, label = "path") {
  if (HUB_CHILD && typeof p === "string" && p.trim() !== "" && !isAbsolute(p)) {
    throw new Error(`${label}: 상대 경로는 지원하지 않습니다(${p}). 파일·폴더의 절대 경로로 다시 지정하세요.`);
  }
}
function resolve(p, ...rest) {
  absInHub(p);
  return nodeResolve(p, ...rest);
}


const HELPER =
  process.env.KORDOC_API_HELPER || "/usr/local/bin/kordoc-api";

function okText(value) {
  return {
    content: [
      {
        type: "text",
        text:
          typeof value === "string"
            ? value
            : JSON.stringify(value, null, 2)
      }
    ]
  };
}

function errorText(message) {
  return {
    isError: true,
    content: [
      {
        type: "text",
        text: String(message)
      }
    ]
  };
}

async function requireReadableFile(path, label = "file_path") {
  if (typeof path !== "string" || path.trim() === "") {
    throw new Error(`${label} is required`);
  }

  const resolved = resolve(path);
  await access(resolved, fsConstants.R_OK);
  return resolved;
}

async function requireOutputPath(path) {
  if (typeof path !== "string" || path.trim() === "") {
    throw new Error("output_path is required");
  }

  return resolve(path);
}

function boolArg(value, fallback = false) {
  return typeof value === "boolean" ? value : fallback;
}

function pushFlag(args, flag, value) {
  if (value !== undefined && value !== null && value !== "") {
    args.push(flag, String(value));
  }
}

async function runHelper(args) {
  return await new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(
      HELPER,
      args,
      {
        stdio: ["ignore", "pipe", "pipe"],
        env: process.env
      }
    );

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");

    child.stdout.on("data", chunk => {
      stdout += chunk;
    });

    child.stderr.on("data", chunk => {
      stderr += chunk;
    });

    child.on("error", rejectPromise);

    child.on("close", code => {
      if (code !== 0) {
        rejectPromise(
          new Error(
            stderr.trim() ||
              stdout.trim() ||
              `kordoc-api exited with code ${code}`
          )
        );
        return;
      }

      const text = stdout.trim();

      if (!text) {
        resolvePromise({ success: true });
        return;
      }

      try {
        resolvePromise(JSON.parse(text));
      } catch {
        resolvePromise(text);
      }
    });
  });
}

/* 파싱 공통 옵션(API 1.5.0~, kordoc ParseOptions 나머지). 값이 «주어진 것만» 헬퍼에 넘긴다 — 안 주면 엔진 기본값이다.
   password 는 값이 아니라 password_file(암호가 든 파일 경로)만 받는다: 도구 인자는 대화 기록에 남는다. */
const PARSE_OPTION_FLAGS = [
  ["pages", "--pages", "string"],
  ["images", "--images", "bool"],
  ["remove_header_footer", "--remove-header-footer", "bool"],
  ["script_tags", "--script-tags", "bool"],
  ["keep_trailing_empty_cols", "--keep-trailing-empty-cols", "bool"],
  ["layout_tables", "--layout-tables", "string"],
  ["classify_tables", "--classify-tables", "bool"],
  ["keep_empty_paragraphs", "--keep-empty-paragraphs", "bool"],
  ["formula_ocr", "--formula-ocr", "bool"],
  ["dedupe_running_headers", "--dedupe-running-headers", "bool"],
  ["inline_images", "--inline-images", "bool"],
  ["tables", "--tables", "bool"],
  ["ocr_rec", "--ocr-rec", "string"],
  ["ocr_det", "--ocr-det", "string"],
  ["ocr_det_long_side", "--ocr-det-long-side", "int"],
  ["ocr_lines", "--ocr-lines", "ocrlines"],
  ["memos", "--memos", "bool"],
  ["qr_codes", "--qr-codes", "bool"],
  ["drop_blank_images", "--drop-blank-images", "bool"],
  ["html_cell_links", "--html-cell-links", "bool"],
  ["image_format", "--image-format", "string"],
  ["image_placement", "--image-placement", "string"],
  ["password_file", "--password-file", "string"]
];

function pushParseOptions(args, input, skip = []) {
  for (const [key, flag, kind] of PARSE_OPTION_FLAGS) {
    if (skip.includes(key)) continue;
    const value = input[key];
    if (value === undefined || value === null || value === "") continue;
    if (key === "password_file") absInHub(value, "password_file");
    if (kind === "bool") {
      if (typeof value !== "boolean") throw new Error(`${key} must be a boolean`);
      args.push(flag, value ? "true" : "false");
    } else if (kind === "int") {
      if (!Number.isInteger(value)) throw new Error(`${key} must be an integer`);
      args.push(flag, String(value));
    } else if (kind === "ocrlines") {
      const v = String(value);
      if (!["true", "false", "all"].includes(v)) throw new Error('ocr_lines must be "true", "false" or "all"');
      args.push(flag, v);
    } else {
      args.push(flag, String(value));
    }
  }
}

function pushTableFormat(args, input) {
  const v = input.table_format;
  if (v === undefined || v === null || v === "") return;
  if (v !== "gfm") throw new Error('table_format must be "gfm" (or omitted)');
  args.push("--table-format", "gfm");
}

const IMAGES_PROPERTY = {
  type: "boolean",
  description:
    "Extract image bytes. Set false for text-only callers such as search indexers "
    + "(image placeholders stay, text and OCR are unaffected)."
};

const PARSE_OPTION_PROPERTIES = {
  pages: {
    type: "string",
    description:
      "Page/section range, 1-based: 3, 1-3 or 1,3,5-7. PDF: exact pages. HWP/HWPX: sections "
      + "(approximate). PPTX: slides. A range outside the document returns an empty result with "
      + "a PARTIAL_PARSE warning."
  },
  remove_header_footer: {
    type: "boolean",
    description:
      "PDF header/footer removal. Default true; false keeps repeated headings the filter "
      + "would delete."
  },
  script_tags: {
    type: "boolean",
    description:
      "Write superscript/subscript as <sup>/<sub>. Default: on for HWPX/HWP/DOCX/PPTX, off for "
      + "PDF (use true for papers). false forces plain text everywhere."
  },
  keep_trailing_empty_cols: {
    type: "boolean",
    description: "Keep empty columns at the right edge of a table (input cells of forms)."
  },
  layout_tables: {
    type: "string",
    enum: ["visual", "keep"],
    description:
      "Borderless frame tables (HWPX, HWP5, PDF). visual (default) = as seen; keep = the "
      + "original table structure. For a form's original structure use keep together with "
      + "keep_trailing_empty_cols=true."
  },
  classify_tables: {
    type: "boolean",
    description: "Add blocks[].table.classification (data / layout / uncertain)."
  },
  keep_empty_paragraphs: {
    type: "boolean",
    description: "Keep empty paragraphs (HWPX)."
  },
  formula_ocr: {
    type: "boolean",
    description:
      "PDF formula OCR ($...$). SLOW: 30-120 s per request. Do not use by default or in parallel."
  },
  dedupe_running_headers: {
    type: "boolean",
    description:
      "Drop numbered running headers that an old HWP5 re-inserts on every page. Can also delete "
      + "legitimately repeated numbering; default false."
  },
  inline_images: {
    type: "boolean",
    description: "Inline images into the Markdown as base64 (HWP5 only). The response grows."
  },
  tables: {
    type: "boolean",
    description:
      "PDF table detection. false = reading-order text only, for text-centred documents."
  },
  ocr_rec: {
    type: "string",
    enum: ["handwriting", "auto", "printed"],
    description:
      "OCR recognition model preset. Omit for the default (the service re-reads clearly handwritten pages with the "
      + "handwriting model by itself, kordoc 4.24.42+). handwriting = Korean handwriting/official-form model (~15 MB, "
      + "downloaded on first use). printed (REST API 1.11.0+) = default model only, never uses or downloads the handwriting "
      + "model. auto (API 1.11.0+) = more generous thresholds for switching pages to the handwriting model; downloads it up "
      + "front. Only has an effect when OCR runs (ocr=true or force)."
  },
  ocr_det: {
    type: "string",
    enum: ["mobile", "server", "medium"],
    description:
      "OCR detection model preset (kordoc 4.22.0+): mobile (default), server (PP-OCRv5 server "
      + "det, 88 MB, downloaded on first use) or medium (REST API 1.11.0+, PP-OCRv6 medium det, ~62 MB, downloaded on "
      + "first use; for tilted, blurred, scanned or noisy pages). Only has an effect when OCR runs."
  },
  ocr_det_long_side: {
    type: "integer",
    minimum: 32,
    maximum: 4096,
    description:
      "Long side of the OCR detection input in pixels (kordoc 4.22.0+, default 960). Only has an "
      + "effect when OCR runs."
  },
  ocr_lines: {
    type: "string",
    enum: ["true", "false", "all"],
    description:
      "Return the lines read by the built-in OCR as ocrLines[] in the result (kordoc 4.24.4, PDF and image input). "
      + "One item per page: {pageNumber,width,height,scale,deskewAngle,lines:[{text,box:{x,y,w,h},confidence}]}. "
      + "box is in OCR raster pixels, origin top-left, not PDF points (divide by scale). \"true\" = lines used "
      + "to build blocks, \"all\" = also dropped low-confidence lines (dropped: true). Default off. "
      + "Only has an effect when OCR runs."
  },
  memos: {
    type: "boolean",
    description:
      "HWPX/HWP5 (REST API 1.11.0+): also append the document's memos (Hancom insert memo) to the end of the "
      + "Markdown as a \"메모\" section. Default false. The memos[] field of the result is returned either way."
  },
  qr_codes: {
    type: "boolean",
    description:
      "Read QR codes inside images, all formats (REST API 1.11.0+). The values go to the image block's qr[] and "
      + "to the line after the image placeholder in the Markdown. Default false. Works even with images=false."
  },
  drop_blank_images: {
    type: "boolean",
    description:
      "Drop blank images (nearly one colour: empty plates, solid bands, faint gradients) from the image blocks, "
      + "images and Markdown (REST API 1.11.0+). Default false. Only evaluated when image bytes are produced."
  },
  html_cell_links: {
    type: "boolean",
    description:
      "Emit [text](URL), bare URLs and QR URLs inside HTML table cells as <a href> so merged/nested table cells are "
      + "clickable (REST API 1.11.0+, kordoc 4.24.63+). Only http, https, mailto, tel and # links. Default false."
  },
  image_format: {
    type: "string",
    enum: ["png", "webp"],
    description:
      "Force every extracted image to one format: png or lossless webp (REST API 1.11.0+). Omit to keep the "
      + "default (PNG for PDF images, the original bytes for other formats). Ignored when images=false."
  },
  image_placement: {
    type: "string",
    enum: ["page-end", "flow"],
    description:
      "PDF only (REST API 1.11.0+). page-end (default) = images are collected after the last block of their page. "
      + "flow = images are placed in reading position between text blocks and image blocks get a bbox."
  },
  password_file: {
    type: "string",
    description:
      "Path of a file that holds the open password of a protected HWPX or HWP3 document "
      + "(mode 600; delete it afterwards). Never put the password itself in a tool argument."
  }
};

/* ───────── kordoc 4.24.0 공식 kordoc-mcp 정렬(2026-10-21) ─────────
   도구 이름·필드·enum·default·required 는 공식 kordoc-mcp tools/list 그대로(OFFICIAL_TOOLS, build-aligned.py 가 삽입).
   우리 쪽 추가는 «공식 ParseOptions 에 있는 파싱 옵션»(상위집합)과 health·validate_hwpx 뿐이다.
   값이 대화 기록에 남는 인자(password, fill 의 fields)는 막거나 파일 경로로만 받는다. */

const OFFICIAL_TOOLS = [
 {
  "name": "parse_document",
  "description": "한국 문서 파일(HWP, HWPX, PDF, XLSX, DOCX)과 이미지(PNG/JPG/WebP)를 마크다운으로 변환합니다. 파일 경로를 입력하면 포맷을 자동 감지하여 텍스트를 추출합니다. 이미지는 OCR(내장 PP-OCRv5)이 자동 적용되고 표 괘선도 복원됩니다. 견본 서식대로 새 문서를 쓰거나(서식 베끼기) 문구를 고쳐 patch_document 로 넘길 마크다운이면 keep_layout_tables: true 로 읽으세요.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "파싱할 문서 파일의 절대 경로 (HWP, HWPX, PDF, XLSX, DOCX, PNG/JPG/WebP)"
    },
    "ocr": {
     "anyOf": [
      {
       "type": "boolean"
      },
      {
       "type": "string",
       "const": "force"
      }
     ],
     "description": "스캔/이미지 PDF 텍스트 OCR (내장 PP-OCRv5 korean, 첫 사용 시 ~18MB 자동 다운로드). true=텍스트층이 없거나 깨진 페이지만 인식하고 정상 페이지는 그대로 둡니다. \"force\"=텍스트층이 있어도 무시하고 전 페이지 강제 재인식. parse 결과에 NEEDS_OCR 경고가 있으면 이 옵션으로 재시도하세요"
    },
    "remove_header_footer": {
     "type": "boolean",
     "description": "PDF 머리글/바닥글 자동 제거 (기본 true — false로 끄기, CLI --no-header-footer 대응)"
    },
    "formula_ocr": {
     "type": "boolean",
     "description": "PDF 수식 OCR 활성화 (MFD+MFR ONNX, 첫 사용 시 모델 ~155MB 자동 다운로드, CLI --formula-ocr 대응)"
    },
    "ocr_rec": {
     "type": "string",
     "enum": [
      "handwriting"
     ],
     "description": "OCR 글자 인식 모델 — \"handwriting\": 수기 서류용 한국어 손글씨 rec(첫 사용 시 ~15MB 다운로드). 손글씨 칸이 많은 서식용이며 금액·날짜·전화번호의 쉼표·마침표·하이픈을 빠뜨리는 경우가 있다. OCR 이 도는 곳(이미지, PDF 는 ocr: true·\"force\" — ocr 을 빼면 고른 모델이 캐시에 있을 때만 자동 OCR)에 적용 (CLI --ocr-rec handwriting 대응)"
    },
    "ocr_det": {
     "type": "string",
     "enum": [
      "mobile",
      "server"
     ],
     "description": "OCR 글줄 검출 모델 — \"mobile\"(기본) | \"server\"(첫 사용 시 ~88MB 다운로드) (CLI --ocr-det 대응)"
    },
    "ocr_det_long_side": {
     "type": "integer",
     "minimum": 32,
     "maximum": 4096,
     "description": "OCR 글줄 검출 입력 긴 변 픽셀 (32~4096, 기본 960) — 키우면 작은 글씨를 더 잡고 느려진다 (CLI --ocr-det-long-side 대응)"
    },
    "dedupe_running_headers": {
     "type": "boolean",
     "description": "HWP5 레이아웃 표 페이지 반복 러닝 헤더 중복 제거 (기본 off — 붙임별 재번호 오삭제 주의, CLI --dedupe-headers 대응)"
    },
    "keep_trailing_empty_cols": {
     "type": "boolean",
     "description": "표 오른쪽 끝 빈 열(서식 입력란) 보존 (#47, 기본 off: 후행 빈 열 트림, CLI --keep-empty-cols 대응)"
    },
    "keep_empty_paragraphs": {
     "type": "boolean",
     "description": "빈 문단 보존 — 본문은 빈 paragraph 블록, 표 셀은 빈 줄 (#57, 기본 off, CLI --keep-empty-paragraphs 대응)"
    },
    "include_field_placeholders": {
     "type": "boolean",
     "description": "미기입 누름틀 안내문도 출력 — 빈 서식 문서의 칸 용도 보존 (#92, 기본 off, CLI --include-field-placeholders 대응)"
    },
    "keep_layout_tables": {
     "type": "boolean",
     "description": "테두리가 안 보이는 틀 표도 원본 표 구조 그대로 (기본 off = 보이는 대로: 틀은 글, 칸으로 조립한 분수는 수식). patch_document 로 되돌릴 편집본은 켜서 뽑는다 (CLI --keep-layout-tables)"
    },
    "html_tables": {
     "type": "boolean",
     "description": "모든 표를 HTML 로 — 파이프 표도 HTML 표로, 태그마다 한 줄씩 들여써 냄 (기본 off, CLI --html-tables 대응)"
    },
    "table_format": {
     "type": "string",
     "enum": [
      "gfm"
     ],
     "description": "\"gfm\": 모든 표를 HTML 없이 GFM 파이프 표로 — 셀 안 표는 부모 뒤 독립 표로 꺼내고 관계를 <!-- <table id parent_id /> --> 표지로 남김 (RAG 색인용, html_tables 와 함께 못 씀, CLI --table-format 대응)"
    },
    "script_tags": {
     "type": "boolean",
     "description": "위·아래첨자를 <sup>·<sub> 로 표기(\"10⁴ m²\" 가 \"104 m2\" 로 펴지지 않게) — 기본: HWPX·HWP·DOCX 켬, PDF 끔(논문·수식 PDF 는 true 권장), false 면 모두 평문. CLI --script-tags / --no-script-tags 대응"
    },
    "plain": {
     "type": "boolean",
     "description": "평문 Markdown — 그림 자리 표시·링크 URL·밑줄/굵게 표기를 빼고 글만 (제목·목록·표 구조는 유지, 기본 off, CLI --plain 대응)"
    },
    "password": {
     "type": "string",
     "description": "암호로 보호된 문서의 열기 암호 (#59, HWPX·HWP3·HWP5 지원. 파싱이 ENCRYPTED로 실패하면 이 옵션으로 재시도하세요. 한컴 DRM 보호 문서는 해당 없음)"
    },
    "tables": {
     "type": "boolean",
     "description": "PDF 표 감지 (기본 true — false로 끄기, CLI --no-tables 대응). 테두리 박스를 표로 오인해 읽기 순서가 뒤집히는 문서(2단 시험지 등)에서 자연 읽기순 텍스트만 뽑습니다 (#64)"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "detect_format",
  "description": "파일의 포맷을 매직 바이트와 컨테이너 내부 구조로 감지합니다 (hwpx, hwp, hwp3, hwpml, pdf, xls, xlsx, docx, pptx, image, unknown).",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "감지할 파일의 절대 경로"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "parse_metadata",
  "description": "문서의 메타데이터(제목, 작성자, 날짜 등)만 빠르게 추출합니다. 전체 파싱 없이 헤더/매니페스트만 읽습니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "메타데이터를 추출할 문서 파일의 절대 경로"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "parse_pages",
  "description": "문서의 특정 페이지 범위만 파싱합니다. PDF와 한컴 저장본 HWP/HWPX는 실제 페이지 기준(metadata.pageMode=layout), 조판 캐시가 없는 생성 파일은 섹션 단위 근사(pageMode=section)입니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "파싱할 문서 파일의 절대 경로"
    },
    "pages": {
     "type": "string",
     "minLength": 1,
     "description": "페이지 범위 (예: '1-3', '1,3,5-7')"
    }
   },
   "required": [
    "file_path",
    "pages"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "parse_table",
  "description": "문서에서 N번째 테이블만 추출합니다 (0-based index). 테이블이 없거나 인덱스 범위를 초과하면 오류를 반환합니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "파싱할 문서 파일의 절대 경로"
    },
    "table_index": {
     "type": "integer",
     "minimum": 0,
     "description": "추출할 테이블 인덱스 (0부터 시작)"
    }
   },
   "required": [
    "file_path",
    "table_index"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "compare_documents",
  "description": "두 한국 문서 파일을 비교하여 추가/삭제/변경된 블록을 표시합니다. 신구대조표 생성에 활용됩니다. 크로스 포맷(HWP↔HWPX) 비교 가능.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path_a": {
     "type": "string",
     "minLength": 1,
     "description": "비교 원본 문서의 절대 경로"
    },
    "file_path_b": {
     "type": "string",
     "minLength": 1,
     "description": "비교 대상 문서의 절대 경로"
    }
   },
   "required": [
    "file_path_a",
    "file_path_b"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "parse_chunks",
  "description": "문서를 RAG용 구조 청크 JSON으로 파싱합니다. 헤딩·개조식 위계(□○- / 1.·가.·1))가 breadcrumb 경로로 보존되고 표는 독립 청크로 나옵니다 — 임베딩·인덱싱 전처리용. 자르기(토큰 상한·오버랩)는 소비자 몫입니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "대상 문서의 절대 경로 (HWP/HWPX/PDF/XLSX/DOCX)"
    },
    "granularity": {
     "type": "string",
     "enum": [
      "section",
      "block"
     ],
     "default": "section",
     "description": "section=같은 breadcrumb 아래 연속 텍스트 병합(기본), block=IRBlock 1개=청크 1개"
    },
    "include_table_cells": {
     "type": "boolean",
     "default": false,
     "description": "표 청크에 셀 텍스트 2차원 배열 포함 여부"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "parse_form",
  "description": "한국 서식 문서에서 레이블-값 쌍을 구조화된 JSON으로 추출합니다. 양식/서식 문서에 최적화.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "서식 문서 파일의 절대 경로"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "fill_form",
  "description": "한국 서식 문서의 빈칸을 채워서 새 문서로 출력합니다. hwpx-preserve를 사용하면 원본 서식(테두리, 폰트, 병합 등)을 100% 유지합니다. HWPX 누름틀(CLICK_HERE) 필드는 이름으로 정확 매칭되어 우선 채워집니다. file_path 대신 template으로 내장 정부 표준 기안문 서식을 쓸 수 있습니다 — gian(일반기안문, 별지 제1호서식: 행정기관명·수신자·경유·제목·본문·붙임·발신명의·기안자·검토자·결재권자 등 23필드) / gian-simple(간이기안문, 별지 제2호서식: 내부결재용 13필드).",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "서식 템플릿 문서의 절대 경로 (HWP, HWPX, PDF, XLSX, DOCX). template 사용 시 생략"
    },
    "template": {
     "type": "string",
     "enum": [
      "gian",
      "gian-simple",
      "일반기안문",
      "간이기안문"
     ],
     "description": "내장 정부 표준 서식 이름 — file_path 대신 사용. gian=일반기안문(별지 제1호서식), gian-simple=간이기안문(별지 제2호서식)"
    },
    "fields": {
     "type": "object",
     "additionalProperties": {
      "type": "string"
     },
     "description": "채울 필드 맵 (라벨 → 값). 예: {\"성명\": \"홍길동\", \"전화번호\": \"010-1234-5678\"}. 개인정보는 fields_file 로"
    },
    "fields_file": {
     "type": "string",
     "minLength": 1,
     "description": "채울 필드 JSON 파일의 절대 경로 — fields 대신. {\"성명\": \"홍길동\"} 모양(반복 양식은 값 배열). 값이 도구 인자로 대화에 남지 않고, 응답도 값 대신 글자 수만 낸다(mask_values: false 로 끔)"
    },
    "formats": {
     "type": "object",
     "additionalProperties": {
      "type": "string"
     },
     "description": "필드별 값 서식 (라벨 → 포맷). 정준값 하나로 서식마다 다른 모양을 채울 때: date:yy.mm.dd / phone:hyphen·dot·digits / rrn:hyphen·masked / mask:###-## / 자유 패턴(yyyy년 m월 d일, ###-####-####)"
    },
    "require_unique": {
     "type": "boolean",
     "description": "한 키가 서식의 2곳 이상에 매칭되면 채우지 않고 거부 — 반복 라벨 양식에서 남의 블록 오염 방지 (배열 값은 예외)"
    },
    "mask_values": {
     "type": "boolean",
     "description": "응답에 값 대신 글자수만 표시 — 개인정보 채움 시 값이 대화 로그에 남지 않게 (fields_file 이면 기본 켬)"
    },
    "output_format": {
     "type": "string",
     "enum": [
      "markdown",
      "hwpx",
      "hwpx-preserve"
     ],
     "default": "hwpx-preserve",
     "description": "출력 포맷: hwpx-preserve (원본 스타일 보존, HWPX 전용), hwpx (새 HWPX 생성), markdown"
    },
    "output_path": {
     "type": "string",
     "description": "출력 파일 저장 경로 (선택). 지정 시 파일로 저장, 미지정 시 텍스트로 반환"
    }
   },
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "place_seal",
  "description": "도장/서명 이미지를 앵커 문구(\"(인)\"·\"서명 또는 인\" 등) 위에 부유(글 앞) 배치합니다. 표/페이지를 키우지 않습니다 (HWPX 전용).",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "대상 HWPX 문서의 절대 경로"
    },
    "image_path": {
     "type": "string",
     "minLength": 1,
     "description": "도장/서명 이미지 절대 경로 (투명 배경 PNG 권장)"
    },
    "anchor": {
     "type": "string",
     "default": "(인)",
     "description": "앵커 문구 — 이 문구 기준으로 배치"
    },
    "occurrence": {
     "type": "integer",
     "minimum": 0,
     "default": 0,
     "description": "같은 앵커가 여럿일 때 0-based 선택"
    },
    "size_mm": {
     "type": "number",
     "exclusiveMinimum": 0,
     "description": "도장 한 변 크기 mm (기본: 줄높이×1.6, 7~18 클램프)"
    },
    "mode": {
     "type": "string",
     "enum": [
      "overlap",
      "right",
      "auto"
     ],
     "default": "auto",
     "description": "overlap=문구 위 겹침, right=문구 오른쪽 옆, auto=공간 있으면 right"
    },
    "dx_mm": {
     "type": "number",
     "description": "x 미세조정 mm"
    },
    "dy_mm": {
     "type": "number",
     "description": "y 미세조정 mm"
    },
    "output_path": {
     "type": "string",
     "minLength": 1,
     "description": "출력 HWPX 저장 경로"
    }
   },
   "required": [
    "file_path",
    "image_path",
    "output_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "patch_document",
  "description": "원본 HWPX/HWP의 서식(글꼴·표·도장칸·로고·결재란·이미지)을 그대로 두고, 편집된 마크다운대로 글을 바꿔 새 문서로 출력합니다. 두 가지 용도: (1) 문구 수정·빈칸 채우기, (2) ★서식 베끼기 — \"이 문서 서식대로/똑같은 양식으로/이거 참고해서 ○○ 문서 써줘\"처럼 견본의 분위기를 그대로 재현해 새 공문서를 쓰는 요청. 절차: parse_document(견본, keep_layout_tables: true) → 받은 마크다운의 골격(표지·결재란 표, 제목, □·ㅇ·- 부호와 들여쓰기, 강조 표지 **, 표 표기)을 유지한 채 내용만 새로 쓰기 → 이 도구(file_path=견본, output_path=새 파일) → render_document 로 확인. HWPX 견본은 문단을 자유롭게 늘리고 줄여도 됩니다: 새 줄은 같은 항목 부호(□·ㅇ·-·※·1.·가.)를 단 견본 문단을 복제해 같은 들여쓰기·글꼴·굵기로 들어가고, 지운 줄은 문단째 빠집니다. 표는 견본 표를 그대로 두고 칸 글만 바꾸며 행은 추가·삭제(<table> 표기면 그 HTML 꼴 유지, GFM 으로 바꾸지 말 것). 견본에 없는 요소를 새로 만들거나 kordoc 기본 서식으로 다시 짜는 generate_document 는 서식 베끼기에 쓰지 마세요. HWP(5.x) 견본은 문단 추가·삭제가 안 돼 줄 수를 견본에 맞춰야 합니다. 미적용 항목은 결과에 보고됩니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "원본 문서의 절대 경로 (HWPX 또는 HWP 5.x)"
    },
    "edited_markdown": {
     "type": "string",
     "minLength": 1,
     "description": "parse_document(keep_layout_tables: true) 출력 마크다운을 편집한 전체 마크다운. 문단 사이는 빈 줄, 줄마다 견본과 같은 항목 부호로 시작(부호가 서식 견본을 고른다). HWPX 는 문단 추가·삭제 반영, 블록 순서 바꾸기는 미지원. 견본의 이미지 줄·<img> 는 그대로 둘 것"
    },
    "output_path": {
     "type": "string",
     "minLength": 1,
     "description": "출력 파일 저장 절대 경로 (원본과 같은 확장자: .hwpx 또는 .hwp)"
    },
    "structure": {
     "type": "boolean",
     "description": "문단 추가·삭제 반영 (HWPX, 기본 true). false 면 추가·삭제를 건너뛰고 미적용으로 보고 — 글 수정만 하고 문서 골격을 절대 바꾸지 않을 때"
    }
   },
   "required": [
    "file_path",
    "edited_markdown",
    "output_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "redact_document",
  "description": "문서의 개인정보(주민·외국인등록번호·전화·이메일·카드·계좌·사업자등록번호·여권·운전면허, rules 로 인명·주소 opt-in)를 탐지해 서식 보존 마스킹합니다. HWPX/HWP는 원본 서식 그대로 같은 길이로 가린 파일 — 본문·표·중첩표·머리말/꼬리말·각주·글상자·필드·미리보기(텍스트·이미지)·문서 정보(제목·작성자)까지 가리고, 저장 전 결과 파일을 다시 훑어 남은 PII를 보고합니다. 그 외 포맷(PDF·DOCX·XLSX 등)은 원본을 건드리지 않고 마스킹된 마크다운만 출력합니다. 자동 검출 보조 도구 — 결과 리포트를 사람이 최종 확인해야 하며 이미지 속 글자는 탐지하지 못합니다. 마스킹 후 render_document로 눈으로 확인하는 것을 권장합니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "대상 문서의 절대 경로"
    },
    "rules": {
     "type": "array",
     "items": {
      "type": "string",
      "enum": [
       "rrn",
       "phone",
       "email",
       "card",
       "account",
       "brn",
       "passport",
       "driver",
       "crn",
       "ip",
       "name",
       "address"
      ]
     },
     "description": "적용 룰 (기본: rrn·phone·email·card·account·brn·passport·driver — crn(법인등록번호)·ip·name(인명, 문맥 게이트)·address(주소)는 opt-in)"
    },
    "mask_char": {
     "type": "string",
     "minLength": 1,
     "maxLength": 1,
     "description": "마스크 문자 1글자 (기본: ●)"
    },
    "output_path": {
     "type": "string",
     "minLength": 1,
     "description": "출력 경로 (HWPX/HWP는 같은 확장자, 그 외는 .md) — dry_run이 아니면 필수"
    },
    "dry_run": {
     "type": "boolean",
     "default": false,
     "description": "탐지 리포트만 반환, 파일 미생성"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "render_document",
  "description": "HWPX·HWP 문서를 실제 조판 그대로 렌더해 PNG/JPEG 이미지로 응답하거나 SVG·HTML·PDF 파일로 저장합니다. generate_document·fill_form·patch_document·place_seal 결과물을 눈으로 확인하는 용도 — 생성/수정 후 이 도구로 렌더해 깨짐·잘림·배치를 검증하고 다시 고치는 루프를 권장합니다. 한컴 저장본(HWPX·HWP 모두)은 조판 캐시로 정확히, AI 생성본(캐시 없음)은 순수 조판 엔진(reflow)으로 렌더되며 후자는 한컴 실조판의 근사입니다 (참고용 미리보기).",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "렌더할 HWPX 또는 HWP(5.x) 파일의 절대 경로"
    },
    "format": {
     "type": "string",
     "enum": [
      "png",
      "jpeg",
      "svg",
      "html",
      "pdf"
     ],
     "default": "png",
     "description": "png/jpeg=이미지로 응답에 직접 반환(output_path 는 선택) / svg·html·pdf=output_path 에 파일 저장(필수). svg 는 pages 미지정 HWPX 면 전체 세로 스택 1파일, 그 외 페이지별 파일. html=자급자족 레이아웃 HTML 1파일, pdf=Chromium 필요"
    },
    "output_path": {
     "type": "string",
     "minLength": 1,
     "description": "결과 저장 경로 (확장자는 format 과 일치 — .png/.jpg/.svg/.html/.pdf). 페이지별 산출은 _page_NNN 접미"
    },
    "highlights": {
     "type": "array",
     "items": {
      "type": "string",
      "minLength": 1
     },
     "description": "형광펜 표시할 검색어 목록 — 채운 값·수정 문구 위치 확인용"
    },
    "reflow_mode": {
     "type": "string",
     "enum": [
      "keep",
      "charAll"
     ],
     "default": "keep",
     "description": "reflow 줄바꿈: keep=어절 단위, charAll=글자 단위"
    },
    "pages": {
     "type": "string",
     "minLength": 1,
     "description": "페이지 선택(1-based: '3', '1-3', '1,3,7-9') — 지정하면 페이지별 산출(이미지 응답은 최대 8쪽). HWPX png/svg 에서 미지정이면 전체를 세로 스택 1장으로"
    },
    "max_width_px": {
     "type": "integer",
     "minimum": 200,
     "maximum": 4000,
     "description": "래스터(png/jpeg) 최대 폭 px — 큰 문서 응답 부피 조절"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "crop_regions",
  "description": "HWPX·HWP 문서를 렌더해 표·이미지·문단·도형 영역을 페이지 이미지에서 잘라 파일로 저장합니다(render_document 와 같은 조판 엔진, 페이지 로컬 pt bbox 를 실배율로 환산). 표가 진짜 데이터표인지 조직도인지는 판단하지 않습니다(그건 extract_tables) — 렌더러가 아는 개체를 자를 뿐. 결과: output_dir/<유형>_<번호>_page_<쪽>.png + regions.json(id·유형·페이지·bbox pt).",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "HWPX 또는 HWP(5.x) 파일 절대 경로"
    },
    "output_dir": {
     "type": "string",
     "minLength": 1,
     "description": "crop 파일 저장 디렉토리"
    },
    "target": {
     "type": "array",
     "items": {
      "type": "string",
      "enum": [
       "table",
       "image",
       "paragraph",
       "shape"
      ]
     },
     "default": [
      "table"
     ],
     "description": "잘라낼 개체 유형"
    },
    "format": {
     "type": "string",
     "enum": [
      "png",
      "jpeg"
     ],
     "default": "png"
    },
    "pages": {
     "type": "string",
     "minLength": 1,
     "description": "대상 페이지(1-based 범위)"
    },
    "padding_pt": {
     "type": "number",
     "minimum": 0,
     "maximum": 100,
     "default": 0,
     "description": "bbox 둘레 여백 pt"
    }
   },
   "required": [
    "file_path",
    "output_dir"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "extract_tables",
  "description": "HWPX·HWP 문서의 표를 추출·분류합니다(#76). 표마다 semantic-table(데이터표) / non-tabular-layout(조직도·연락망·결재란처럼 표를 캔버스로 쓴 것) / uncertain 분류와 근거 신호, 페이지·bbox(pt, 렌더 region 조인), 정책(visual)에 따른 crop 이미지를 돌려줍니다 — 조직도는 이미지로, 데이터표는 셀 구조로 넘기는 멀티모달 파이프라인용. 휴리스틱(네트워크·LLM 없음), 중첩표도 독립 분류. crop 은 output_dir 에 저장하고 8장까지 응답에 함께 담습니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "HWPX 또는 HWP(5.x) 파일 절대 경로"
    },
    "output_dir": {
     "type": "string",
     "minLength": 1,
     "description": "crop 파일·tables.json 저장 디렉토리 (visual 이 none 이 아니면 필수)"
    },
    "visual": {
     "type": "string",
     "enum": [
      "none",
      "non-tabular",
      "non-tabular-and-uncertain",
      "all"
     ],
     "default": "none",
     "description": "crop 대상: none=분류·bbox 만 / non-tabular=조직도류만 / non-tabular-and-uncertain(권장) / all"
    },
    "format": {
     "type": "string",
     "enum": [
      "png",
      "jpeg"
     ],
     "default": "png"
    },
    "padding_pt": {
     "type": "number",
     "minimum": 0,
     "maximum": 100,
     "default": 0,
     "description": "crop 둘레 여백 pt"
    },
    "cells": {
     "type": "boolean",
     "default": false,
     "description": "응답 JSON 에 셀 텍스트 격자 포함"
    }
   },
   "required": [
    "file_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "extract_profile",
  "description": "참조 HWPX 문서에서 표 서식 프로필(테두리·음영·열 너비·셀 글꼴)을 JSON으로 추출합니다. 추출한 프로필을 generate_document의 profile_path로 넘기면 원본 문서 없이 같은 표 서식을 재현합니다(표만 — 문서 전체 분위기를 따라 쓰려면 견본을 patch_document 로 고쳐 쓰는 편이 정확).",
  "inputSchema": {
   "type": "object",
   "properties": {
    "hwpx_path": {
     "type": "string",
     "minLength": 1,
     "description": "서식을 추출할 참조 HWPX 파일의 절대 경로"
    },
    "output_path": {
     "type": "string",
     "minLength": 1,
     "description": "프로필 JSON 출력 절대 경로 (.json 권장)"
    }
   },
   "required": [
    "hwpx_path",
    "output_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "generate_document",
  "description": "마크다운을 HWPX 한글 문서로 생성합니다(kordoc 공문서 서식). \"보고서로/공문서로/개조식으로/계획서로 뽑아줘·만들어줘\" 요청이 이 도구입니다. ⚠ 사용자가 견본 HWPX/HWP 를 주며 \"이 서식대로·똑같이·이거처럼 써줘\"라고 하면 이 도구가 아니라 parse_document → 내용만 새로 쓴 마크다운 → patch_document(견본 서식·로고·결재란·표 그대로, 문단 추가·삭제 가능)입니다 — 견본과 표·항목 구조가 다른 새 문서를 부서 서식으로 짤 때만 이 도구의 template_path. 프리셋 매핑: 정부 표준 보고서(표지·목차·로마숫자 장헤더 자동)='개조식', 중앙부처 업무보고·국회 서면보고(재경부 실측: 장 띠·절 숫자칸·소제목 박스·① 항목 띠·연노랑 성과 요약박스·별첨 띠, □ 뒤 (키워드) 파랑)='업무보고', 지방자치단체 방침서·추진계획(서울시 시장방침 실측: 제목표·파랑 부제·요약박스·[Ⅰ] 장 상자·절 띠)='서울방침' — 보고서·계획서를 만들 때 정부(업무보고)형과 지방(서울방침)형 중 무엇으로 할지 불명확하면 사용자에게 물어보세요, 기안문·시행문·알림공문='기안문', 1페이지 요약보고서='보고서', 추진계획='계획서'. 표는 실측 정부 서식(헤더 음영+이중선·외곽 굵은선·내용 비례 열폭), 쪽번호·결재란·'끝.' 표시 지원. ⚠ 생성 전 확인 권장: 문서종류(보고서/기안문)·제목·기관명(org)·날짜·목차 여부가 불명확하면 사용자에게 물어보세요 — 엉뚱한 프리셋 선택이 가장 흔한 오생성 원인. 마크다운 규칙(v4.13 서울 실결재 실측 위계): #(h1)=문서 제목, ##(h2)=장(보고서 Ⅰ Ⅱ / 기안문·통지는 법정 1.), ###(h3)=□ 대항목(기안문 가.), 그 아래 리스트=ㅇ → - → ㆍ(기안문 가. → 1) → 가)), 본문에 □/ㅇ/-/1./가. 를 직접 써도 같은 위계로 정규화, ※시작·'출처:'·'자료:'=참고(13pt), 제목 직후 인용문(>)=요약박스(보고서·계획서·개조식·서울방침 — 개조식은 표지(기본) 다음 본문 첫 쪽 제목 상자 아래·첫 장 앞 — cover:false 면 ※ 참고, 그 밖의 자리 인용문은 ※ 참고 / 업무보고는 `> ▪ …`=연노랑 성과 요약박스, 자리 무관) — ★내용 구성(보고서·계획서): 왜(추진배경·근거·현황 및 문제점) → 무엇을(추진개요·개선방안·세부 추진계획) → 어떻게(추진일정·소요예산·기대효과·향후계획)를 장 이름으로 — '서론·본론·결론'이라고 쓰지 말 것, 배경은 사실(지시 일자·법령 시행일·건수)로 열고 문제점마다 방안을 한 짝씩, 기대효과는 문제점 지표의 목표치, '결론적으로·만족도 향상·급변하는' 같은 AI 상투구 금지, 모르는 수치는 ○○ 자리표시. 결재용이면 gate: true(미통과면 지적 목록만 돌려줌 — 고쳐 쓰고 다시 호출). ★보고서·개조식은 반드시 제목 직후 `> …하고자 함` 한 문장(쉼표 허용·부호 없음·3줄 이내 약 90~100자)로 보고 목적을 넣을 것(3줄 초과·두 문장 이상이면 경고, 보고서·계획서·서울방침은 없어도 경고), <right>텍스트</right>=우측정렬. □·제목은 한 줄에 자동 축소, 본문은 어절 단위 줄바꿈(낱말·날짜가 줄 끝에서 안 쪼개짐)·부호 뒤 탭 정렬(둘째 줄이 첫 줄 내용과 같은 위치), 마지막 줄이 짧은 고아 줄과 공백이 크게 벌어지는 줄은 자간 축소로 정리, 곧은따옴표는 ‘’“”로. 법령 코드 (282791)·KOSIS 표 ID DT_…·(법정동코드 …)·○○ MCP 조회 같은 내부 식별자·도구 언급은 자동 제거 — 출처는 기관·자료명만 쓸 것. (원본 서식 보존 제자리 수정은 patch_document, 서식 빈칸 채우기는 fill_form)",
  "inputSchema": {
   "type": "object",
   "properties": {
    "markdown": {
     "type": "string",
     "minLength": 1,
     "description": "HWPX로 변환할 마크다운 전문. 표는 GFM 문법 사용 (예: '| 이름 | 부서 |\\n| --- | --- |\\n| 홍길동 | 기획팀 |')"
    },
    "output_path": {
     "type": "string",
     "minLength": 1,
     "description": "출력 HWPX 파일의 절대 경로 (.hwpx 권장)"
    },
    "profile_path": {
     "type": "string",
     "description": "서식 프로필 JSON 경로 (extract_profile로 추출) — 참조 문서의 표 테두리·음영·열폭·셀 글꼴을 재현. 표 행·열 수와 첫 셀 텍스트가 일치하는 표에만 적용"
    },
    "template_path": {
     "type": "string",
     "description": "부서 서식 견본 HWPX 절대 경로 — 견본의 쪽 설정·글꼴·제목표·담당 줄(☎)·요약 상자(>)·□○-·※ 문단·데이터 표·참고N 띠 서식을 그대로 쓰고 내용만 markdown 으로 새로 짠다(견본 글은 남지 않음). 견본과 내용 구조가 달라도 된다 — 견본을 고쳐 쓰는(줄·칸 그대로) 일은 patch_document. preset·서식·쪽·image_dir·profile_path 와 함께 못 씀"
    },
    "preset": {
     "type": "string",
     "enum": [
      "official",
      "기안문",
      "시행문",
      "공문",
      "공문서",
      "report",
      "보고서",
      "plan",
      "계획서",
      "계획",
      "notice",
      "통지",
      "알림",
      "안내",
      "minutes",
      "회의록",
      "gaejosik",
      "개조식",
      "개조식보고서",
      "정부보고서",
      "정부표준개조식보고서",
      "press",
      "보도자료",
      "ministry",
      "업무보고",
      "부처업무보고",
      "중앙부처보고서",
      "bangchim",
      "서울방침",
      "방침서",
      "방침"
     ],
     "description": "공문서 프리셋 — 지정 시 한국 행정 공문서 표준 서식 적용. '개조식'=정부 표준 개조식 보고서(표지·목차·로마숫자 장 헤더 자동 + □○-※ 부호별 폰트), '업무보고'=중앙부처 업무보고(##=Ⅰ 장 띠, ###=파란 숫자칸 절, ####=남색 소제목 박스, #####=① 하늘색 항목 띠, > ▪…=연노랑 성과 요약박스, ## 별첨 …=별첨 띠, ❶⇒ 부호 보존, 함초롬바탕 15·각주 맑은 고딕 12), '서울방침'=서울시 방침서(# 제목 뒤 '- 부제 -' 줄=파랑 부제·☎ 줄=담당자 행·> =요약박스, ##=[Ⅰ] 장 상자, ###=파란 번호 절 띠, ####=❶ 과제 소제목, □ HY견고딕 17·ㅇ 한컴돋움 15 굵게·- 휴먼명조 14·▸ 13, 줄간격 200%), '보도자료'=머리박스+제목 25pt+□→ㅇ→*(각주) 체계. 미지정 시 범용 마크다운 변환"
    },
    "font": {
     "type": "string",
     "enum": [
      "myeongjo",
      "gothic"
     ],
     "description": "본문 글꼴(공문서 모드): myeongjo=명조 계열(개조식·보고서·계획서는 실측 휴먼명조, 그 외 함초롬바탕), gothic=맑은 고딕"
    },
    "body_pt": {
     "type": "integer",
     "minimum": 6,
     "maximum": 40,
     "description": "본문 글자 크기(pt, 공문서 모드). 기본: 기안문 12, 보고서·계획서·통지 15"
    },
    "line_spacing": {
     "type": "integer",
     "minimum": 50,
     "maximum": 300,
     "description": "본문 줄간격(%, 공문서 모드). 기본: 프리셋별 실측값(기안문 160, 회의록 130 등)"
    },
    "org": {
     "type": "string",
     "description": "표지 기관명 (표지를 켜는 모든 프리셋에서 사용 가능). 미지정 시 표지에 기관명 생략"
    },
    "date": {
     "type": "string",
     "description": "표지 날짜 ('YYYY. M. D.' 표기 권장). 미지정 시 오늘 날짜"
    },
    "toc": {
     "type": "boolean",
     "description": "목차 페이지 생성 여부 — h2 목록을 Ⅰ Ⅱ Ⅲ 장으로 자동 구성. 전 프리셋 사용 가능(보도자료 제외). 미지정 시 개조식 프리셋만 켜짐"
    },
    "cover": {
     "type": "boolean",
     "description": "표지 페이지 생성 여부 — 첫 h1을 제목으로 파랑 장식 표지. 전 프리셋 사용 가능(보도자료 제외 — 머리박스 서식과 양립 불가). 미지정 시 개조식 프리셋만 켜짐 (org/date 지정 시 자동 켜짐)"
    },
    "approval": {
     "type": "array",
     "items": {
      "type": "string"
     },
     "maxItems": 6,
     "description": "결재란 직위 라벨 (최대 6개, 예: ['담당','팀장','과장']) — 문서 최상단 우측에 서명 공란 결재 표 생성"
    },
    "page_numbers": {
     "type": "boolean",
     "description": "쪽번호(하단 중앙 '- 1 -', 표지·목차 카운트 제외). 미지정 시 개조식·보고서·계획서 켜짐"
    },
    "end_mark": {
     "type": "boolean",
     "description": "본문 끝 '끝.' 표시 (행정업무규정). 미지정 시 기안문만 켜짐, 본문이 이미 '끝.'으로 끝나면 중복 생성 안 함"
    },
    "body_title_box": {
     "type": "boolean",
     "description": "본문 첫 페이지 제목 반복 박스 (개조식 실측 관행). 미지정 시 개조식+표지 조합에서 켜짐"
    },
    "chapter_fit": {
     "type": "boolean",
     "description": "개조식 장 헤더 제목 칸을 글자 폭에 맞춤. 미지정 시 제목 칸이 본문 폭까지"
    },
    "h2_marker": {
     "type": "string",
     "enum": [
      "band",
      "roman",
      "box",
      "number",
      "none"
     ],
     "description": "h2 장 제목 표기: band=로마자 채움 칸+제목 띠 표(보고서·계획서 기본), roman='Ⅰ. 제목' 텍스트, number='1. 제목'(통지 기본), box=장 없이 □ 대항목으로, none=번호 없음. 기안문 본문의 h2는 항상 법정 '1.' 항목"
    },
    "band_color": {
     "type": "string",
     "pattern": "^#[0-9A-Fa-f]{6}$",
     "description": "띠 제목 번호칸 채움색 #RRGGBB (기본 #003366 실측 최다. 교육청형 밝은 띠는 #DFE6F7 + band_text_color #000000)"
    },
    "band_text_color": {
     "type": "string",
     "pattern": "^#[0-9A-Fa-f]{6}$",
     "description": "띠 제목 번호 글자색 #RRGGBB (기본 #FFFFFF)"
    },
    "summary": {
     "type": "string",
     "description": "요약 박스(보고서·계획서·개조식·서울방침) — 제목표(개조식은 본문 첫 쪽 제목 상자) 아래 #DFE6F7 음영 상자(서울 실결재 관행). 마크다운 제목 직후 인용문(> …)으로도 지정 가능"
    },
    "doc_info": {
     "type": "object",
     "properties": {
      "docNum": {
       "type": "string"
      },
      "date": {
       "type": "string"
      },
      "disclosure": {
       "type": "string"
      },
      "policyNo": {
       "type": "string"
      }
     },
     "additionalProperties": false,
     "description": "보고서 표지 문서정보표 — docNum=문서번호/date=결재일자/disclosure=공개여부/policyNo=방침번호 (cover=true와 함께)"
    },
    "checklist": {
     "anyOf": [
      {
       "type": "boolean"
      },
      {
       "type": "object",
       "properties": {
        "na": {
         "type": "array",
         "items": {
          "type": "integer"
         }
        },
        "notes": {
         "type": "object",
         "additionalProperties": {
          "type": "string"
         }
        }
       },
       "additionalProperties": false
      }
     ],
     "description": "서울 사전 검토항목 점검표(표지 다음 쪽, 보고서·계획서·서울방침) — true=표시 없는 빈 서식, {na:[6,7,…]}=적은 문항(1~14)은 해당없음·나머지 검토완료, notes={\"7\":\"교육\"}=비고"
    },
    "dept": {
     "type": "string",
     "description": "표지 부서명 — 기관명 아래 '(스마트도시과)' (cover와 함께)"
    },
    "cover_label": {
     "type": "string",
     "description": "표지 우상단 취급 표시 — '대외주의'·'비공개' 빨간 테두리 박스 (업무보고 프리셋 실측, cover와 함께)"
    },
    "fonts": {
     "type": "object",
     "properties": {
      "body": {
       "type": "string"
      },
      "heading": {
       "type": "string"
      },
      "ref": {
       "type": "string"
      },
      "table": {
       "type": "string"
      }
     },
     "additionalProperties": false,
     "description": "요소별 글꼴 오버라이드(공문서 모드) — body=본문(○·-)/heading=제목 계열(□·장헤더·표지·목차)/ref=※ 참고/table=표 셀. 개조식·보고서·계획서는 네 역할 전부, 그 외 프리셋은 body만 적용"
    },
    "sizes": {
     "type": "object",
     "properties": {
      "dae": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "cham": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "chapter": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "coverTitle": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "coverSub": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "tocLabel": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "tocRoman": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "tocItem": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "table": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      },
      "bodyTitle": {
       "type": "number",
       "minimum": 6,
       "maximum": 60
      }
     },
     "additionalProperties": false,
     "description": "개조식 요소별 글자 크기(pt) 오버라이드 — dae=□/cham=※/chapter=장헤더/coverTitle·coverSub=표지/tocLabel·tocRoman·tocItem=목차/table=표 셀/bodyTitle=본문 첫 페이지 제목 반복 박스. 미지정 요소는 body_pt 비례 기본값"
    },
    "levels": {
     "type": "object",
     "additionalProperties": {
      "type": "object",
      "properties": {
       "font": {
        "type": "string"
       },
       "pt": {
        "type": "number",
        "minimum": 6,
        "maximum": 60
       },
       "bold": {
        "type": "boolean"
       }
      },
      "additionalProperties": false
     },
     "propertyNames": {
      "pattern": "^[0-7]$"
     },
     "description": "항목부호 단계별 위계 타이포(공문서 모드, v4.12.3) — {\"0\":{font:\"HY견고딕\",pt:17,bold:true},\"1\":{font:\"한컴돋움\",bold:true}} 꼴(depth 0~7). 실측: 전자결재 기안문 □/ㅇ/- 계열은 □=HY견고딕 +2~3pt 굵게·ㅇ=한컴돋움 굵게·-=휴먼명조 본문. 법정 8단계(1. 가.)는 본문 동일이 관행이라 기본 미적용"
    },
    "bullet2": {
     "type": "string",
     "enum": [
      "ㅇ",
      "○",
      "◦",
      "❍"
     ],
     "description": "2단계 항목부호 — 'ㅇ'(이응, 전자결재 기안문·공고문 실측 지배) / '○'(원, 보고서 양식) / '◦'·'❍'(일부 중앙부처). 미지정 시 통지·보도자료 ㅇ, 그 외 ○"
    },
    "agency": {
     "type": "string",
     "enum": [
      "공통",
      "개인정보보호위원회",
      "경찰청",
      "고용노동부",
      "공정거래위원회",
      "과학기술정보통신부",
      "관세청",
      "교육부",
      "국가교육위원회",
      "국가데이터처",
      "국가보훈부",
      "국가유산청",
      "국무조정실",
      "국민권익위원회",
      "국방부",
      "국세청",
      "국토교통부",
      "금융위원회",
      "기본사회위원회",
      "기상청",
      "기획예산처",
      "기후에너지환경부",
      "농림축산식품부",
      "농촌진흥청",
      "문화체육관광부",
      "방송미디어통신위원회",
      "방위사업청",
      "법무부",
      "법제처",
      "병무청",
      "보건복지부",
      "산림청",
      "산업통상부",
      "새만금개발청",
      "성평등가족부",
      "소방청",
      "식품의약품안전처",
      "외교부",
      "우주항공청",
      "원자력안전위원회",
      "인구전략위원회",
      "인사혁신처",
      "재외동포청",
      "재정경제부",
      "조달청",
      "중소벤처기업부",
      "지식재산처",
      "질병관리청",
      "통일부",
      "해양경찰청",
      "해양수산부",
      "행정안전부",
      "행정중심복합도시건설청"
     ],
     "description": "기관 서식 — 중앙행정기관 이름 또는 '공통'(기관 간 최빈값). 정책브리핑 보도자료 2,670건 실측으로 그 기관의 □·ㅇ·- 글꼴·크기, 2단계 부호, 표 머리, 기관 색을 기본값으로 깐다(명시 옵션이 우선). 보고서·계획서·업무보고·개조식·보도자료 전용"
    },
    "total_row": {
     "type": "string",
     "enum": [
      "top",
      "bottom",
      "keep"
     ],
     "description": "표 합계·총계·계 행 위치: top=머리행 바로 아래(기본, 공문 실무 관행) | bottom=맨 아래 | keep=원고 그대로. GFM 표에만 적용"
    },
    "suppress_single": {
     "type": "boolean",
     "description": "단일 형제 항목 부호 생략(편람 규정, 법정 번호 standard 전용 — 불릿 체계인 보고서·계획서·개조식·보도자료엔 무효). 기본 false — 하나뿐인 항목에도 부호(1. 가.)를 부여 (부호 없는 계단 들여쓰기가 실무 눈에 어색)"
    },
    "doc_head": {
     "type": "object",
     "properties": {
      "org": {
       "type": "string"
      },
      "slogan": {
       "type": "string"
      },
      "to": {
       "type": "string"
      },
      "via": {
       "type": "string"
      },
      "title": {
       "type": "string"
      }
     },
     "additionalProperties": false,
     "description": "기안문 두문표(별지 제1호서식·서울 실결재 6행 표) — org=행정기관명(굴림 20pt bold 자간띄움)/slogan=원훈(상단 10pt)/to=수신('내부결재'면 발신명의 생략)/via=경유/title=제목(미지정 시 첫 h1). 기안문 프리셋 전용"
    },
    "doc_foot": {
     "type": "object",
     "properties": {
      "sender": {
       "type": "string"
      },
      "drafter": {
       "type": "string"
      },
      "reviewer": {
       "type": "string"
      },
      "approver": {
       "type": "string"
      },
      "cooperator": {
       "type": "string"
      },
      "recipients": {
       "type": "string"
      },
      "docNum": {
       "type": "string"
      },
      "receive": {
       "type": "string"
      },
      "zip": {
       "type": "string"
      },
      "address": {
       "type": "string"
      },
      "site": {
       "type": "string"
      },
      "phone": {
       "type": "string"
      },
      "fax": {
       "type": "string"
      },
      "email": {
       "type": "string"
      },
      "disclosure": {
       "type": "string"
      }
     },
     "additionalProperties": false,
     "description": "기안문 결문표 — sender=발신명의(18pt bold 중앙)/drafter·reviewer·approver='직위 성명' 결재선/cooperator=협조자/recipients=수신자 목록/docNum=시행 '과-번호 (날짜)'/receive=접수/zip·address·site/phone·fax·email/disclosure=공개구분. 기안문 프리셋 전용"
    },
    "report_info": {
     "type": "string",
     "description": "보고서: 제목표 아래 담당자 행 '(2026. 9. 6., 스마트도시과 홍길동, ☎450-1234)' / 기안문: 우상단 12pt 보고정보 행"
    },
    "notice_head": {
     "type": "object",
     "properties": {
      "no": {
       "type": "string"
      },
      "date": {
       "type": "string"
      },
      "sender": {
       "type": "string"
      }
     },
     "additionalProperties": false,
     "description": "공고문 두문·결문 — no=공고번호(본문 위 bold)/date=날짜(본문 아래 우측)/sender=발신명의(우측 bold). 통지 프리셋 전용"
    },
    "press": {
     "type": "object",
     "properties": {
      "release": {
       "type": "string"
      },
      "distribute": {
       "type": "string"
      },
      "sub": {
       "type": "array",
       "items": {
        "type": "string"
       }
      },
      "contact": {
       "type": "object",
       "properties": {
        "dept": {
         "type": "string"
        },
        "manager": {
         "type": "string"
        },
        "phone": {
         "type": "string"
        },
        "people": {
         "type": "array",
         "items": {
          "type": "object",
          "properties": {
           "role": {
            "type": "string"
           },
           "title": {
            "type": "string"
           },
           "name": {
            "type": "string"
           },
           "phone": {
            "type": "string"
           }
          },
          "additionalProperties": false
         }
        }
       },
       "additionalProperties": false
      }
     },
     "additionalProperties": false,
     "description": "보도자료 옵션 — release=보도시점/distribute=배포일(머리박스)/sub=부제 배열('- … -')/contact=담당 표: dept=담당 부서, people=[{role:'책임자',title:'과장',name:'이○○',phone:'044-000-0000'},{role:'담당자',…}] 사람마다 한 행(실물 보도자료 꼴). people 없으면 manager·phone 한 행"
    },
    "paper": {
     "type": "string",
     "enum": [
      "A4",
      "A3",
      "B4",
      "B5",
      "Letter"
     ],
     "description": "용지 크기 (v4.5.0). 기본 A4"
    },
    "landscape": {
     "type": "boolean",
     "description": "용지 가로 방향 (v4.5.0). 기본 세로"
    },
    "columns": {
     "type": "integer",
     "minimum": 1,
     "maximum": 8,
     "description": "다단 개수 (v4.5.0). 기본 1단"
    },
    "header": {
     "type": "string",
     "description": "머리말 텍스트 — 모든 쪽 상단, 인라인 마크다운 허용 (v4.5.0)"
    },
    "footer": {
     "type": "string",
     "description": "꼬리말 텍스트 — 모든 쪽 하단 (v4.5.0)"
    },
    "image_dir": {
     "type": "string",
     "description": "마크다운 이미지 참조(![](x.png))를 이 디렉토리에서 읽어 실데이터 임베드 (v4.5.0, PNG/JPEG/GIF/BMP). 미지정 시 참조만 placeholder로 보존"
    },
    "inline_math": {
     "type": "boolean",
     "description": "본문·표 셀의 인라인 수식 $…$ 를 한글 수식 개체로 생성 (블록 $$…$$ 는 늘 수식). 미지정 시 글자 그대로 — 가격 표기 같은 일반 $ 오인 방지. 켜도 짝이 맞는 $…$ 만(공백으로 시작·끝나거나 \\$ 이스케이프면 제외)"
    },
    "gate": {
     "type": "boolean",
     "description": "공문서 게이트 — 표기법·문체 error 와 윤문(생성형 AI 문체)·구성(왜→무엇→어떻게, 문제점↔방안 짝, 배경 사실·기대효과 목표치) 지적이 하나라도 있으면 파일을 만들지 않고 지적 목록을 돌려준다. 결재용 원고는 켜고, 지적을 고쳐 쓴 뒤 다시 호출"
    }
   },
   "required": [
    "markdown",
    "output_path"
   ],
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 },
 {
  "name": "lint_document",
  "description": "공문서 검수 — 표기법(날짜·시각·금액·붙임·외래어·쉬운 말·차별 표현)은 늘, 개조식 문체·윤문·구성·본문↔표 수치·예산(산출근거 검산·표 합계·합계 행 위치·외화 표기·증감 기준)은 골라 켭니다. text(마크다운·평문, 한 줄 = 한 문단) 또는 file_path(HWP·HWPX·PDF 등) 중 하나. 결과 JSON 의 지적마다 line(1부터)·column(1부터, 문서 단위 지적엔 없음)·match·rule·severity·message·suggest — 열린 문서를 고치는 도구는 blocks(문단·표 칸마다 id·글·표 위치)로 넘기면 지적마다 block(id)·offset(블록 안 위치, 0부터)·length 로 돌려받습니다.",
  "inputSchema": {
   "type": "object",
   "properties": {
    "text": {
     "type": "string",
     "maxLength": 1000000,
     "description": "검수할 글(마크다운·평문). file_path 와 둘 중 하나"
    },
    "file_path": {
     "type": "string",
     "minLength": 1,
     "description": "검수할 문서 파일의 절대 경로(HWP·HWPX·PDF·DOCX 등). text·blocks 와 셋 중 하나"
    },
    "blocks": {
     "type": "array",
     "items": {
      "type": "object",
      "properties": {
       "id": {
        "type": "string",
        "minLength": 1,
        "maxLength": 200
       },
       "text": {
        "type": "string",
        "maxLength": 100000
       },
       "table": {
        "type": "object",
        "properties": {
         "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 200
         },
         "row": {
          "type": "integer",
          "minimum": 0,
          "maximum": 10000
         },
         "col": {
          "type": "integer",
          "minimum": 0,
          "maximum": 1000
         }
        },
        "required": [
         "id",
         "row",
         "col"
        ],
        "additionalProperties": false
       }
      },
      "required": [
       "id",
       "text"
      ],
      "additionalProperties": false
     },
     "maxItems": 20000,
     "description": "문서 순서대로 문단·표 칸 블록 — 표 칸은 table{id,row,col}(같은 id 칸이 한 표). 결과 지적은 block·offset·length. text·file_path 와 셋 중 하나"
    },
    "munche": {
     "type": "boolean",
     "description": "개조식 문체 검수(서술형 종결·당위·수사·항목 길이)"
    },
    "slop": {
     "type": "boolean",
     "description": "윤문 검수(생성형 AI 문체 흔적)"
    },
    "logic": {
     "type": "boolean",
     "description": "구성 검수(보고서·계획서 논리 구조)"
    },
    "numbers": {
     "type": "boolean",
     "description": "본문 수치 ↔ 표 수치 대조(확인 목록)"
    },
    "budget": {
     "type": "boolean",
     "description": "예산 문서 검수 — 산출근거 곱셈 검산, 표 합계 재계산·합계 행 위치(머리행 바로 아래), 외화(원화 먼저·환율 기준), 증감 기준(본예산/최종예산)"
    },
    "gate": {
     "type": "boolean",
     "description": "결재 전 게이트 — 표기법·문체 error 와 윤문·구성 지적이 있으면 summary.ok=false"
    },
    "preset": {
     "type": "string",
     "description": "게이트 범위를 맞출 프리셋(보고서·계획서·개조식 등, 한글 별칭 가능)"
    }
   },
   "additionalProperties": false,
   "$schema": "http://json-schema.org/draft-07/schema#"
  }
 }
];

const byName = Object.fromEntries(OFFICIAL_TOOLS.map(t => [t.name, t]));
const officialParseProps = byName.parse_document.inputSchema.properties;

/* 파싱 옵션 스키마: 공식 parse_document 에 같은 키가 있으면 그 정의, 없으면 우리 정의 */
function parseProp(key) {
  if (officialParseProps[key]) return officialParseProps[key];
  if (key === "images") return IMAGES_PROPERTY;
  return PARSE_OPTION_PROPERTIES[key];
}

const PARSE_KEYS = PARSE_OPTION_FLAGS.map(([key]) => key).filter(key => key !== "ocr_lines");
const PARSE_EXTRAS = {
  parse_document: ["pages", "images", "layout_tables", "classify_tables", "inline_images", "password_file", "ocr_lines",
    "memos", "qr_codes", "drop_blank_images", "html_cell_links", "image_format", "image_placement"],
  parse_pages: ["ocr", "table_format", ...PARSE_KEYS],
  parse_table: ["ocr", ...PARSE_KEYS],
  parse_chunks: ["ocr", ...PARSE_KEYS],
  parse_metadata: ["table_format", ...PARSE_KEYS]
};

const UNIQUE_TOOLS = [
  {
    name: "health",
    description: "Check connectivity and health of the @@BRAND@@ central Kordoc service.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "validate_hwpx",
    description:
      "@@BRAND@@ only (not in the official kordoc-mcp). Validate the structure of an HWPX file through "
      + "the central Kordoc service.",
    inputSchema: {
      type: "object",
      properties: { file_path: { type: "string" } },
      required: ["file_path"],
      additionalProperties: false
    }
  }
];

const tools = [
  ...UNIQUE_TOOLS,
  ...OFFICIAL_TOOLS.map(t => {
    const { $schema, ...schema } = t.inputSchema;
    const properties = { ...schema.properties };
    for (const key of PARSE_EXTRAS[t.name] || []) {
      if (!(key in properties)) properties[key] = parseProp(key);
    }
    // 공식 정의의 좁은 enum(ocr_rec: handwriting · ocr_det: mobile|server)을 API 1.11.0 상위집합으로 덮어쓴다
    for (const key of ["ocr_rec", "ocr_det"]) if (key in properties) properties[key] = PARSE_OPTION_PROPERTIES[key];
    return { name: t.name, description: t.description, inputSchema: { ...schema, properties } };
  })
];

/* ───────── 도우미 ───────── */

function ocrArg(value) {
  if (value === undefined || value === null) return "false";
  if (value === true || value === "true") return "true";
  if (value === false || value === "false") return "false";
  if (value === "force") return "force";
  throw new Error('ocr must be true, false or "force"');
}

async function withTemp(fn) {
  const dir = await mkdtemp(join(tmpdir(), "kordoc-mcp-"));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function tempFile(dir, name, content) {
  const path = join(dir, name);
  await writeFile(path, typeof content === "string" ? content : JSON.stringify(content), { mode: 0o600 });
  return path;
}

function requireString(value, label) {
  if (typeof value !== "string" || value === "") throw new Error(`${label} is required`);
  return value;
}

/* 공식 generate_document 필드 중 파일·경로 성격이 아닌 것은 «그대로(snake_case)» options JSON 으로 중앙 래퍼에 보낸다
   (중앙 래퍼가 공식 kordoc-mcp generate_document 를 그대로 실행한다). */
const GENERATE_FILE_KEYS = ["markdown", "output_path", "profile_path", "template_path", "image_dir"];
const GENERATE_OPTION_KEYS = Object.keys(byName.generate_document.inputSchema.properties)
  .filter(key => !GENERATE_FILE_KEYS.includes(key));

/* 마크다운의 ![](파일) 참조 중 image_dir 에 있는 파일을 헬퍼에 넘긴다(래퍼는 이미지 최대 8개, 하위 폴더 불가) */
async function imagesFromDir(markdown, dir) {
  const root = resolve(requireString(dir, "image_dir"));
  const names = new Set();
  for (const match of markdown.matchAll(/!\[[^\]]*\]\(([^)\s]+)/g)) {
    const ref = match[1];
    if (/^[a-z][a-z0-9+.-]*:/i.test(ref)) continue;
    if (ref.includes("/") || ref.includes("\\")) {
      throw new Error(`image reference must be a plain file name in image_dir: ${ref}`);
    }
    names.add(ref);
  }
  const paths = [];
  for (const name of names) paths.push(await requireReadableFile(join(root, name), `image ${name}`));
  return paths;
}

/* ───────── 서버 ───────── */

const server = new Server(
  { name: "@@PFX@@-kordoc", version: "0.2.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

const handlers = {
  health: async () => okText(await runHelper(["health"])),

  validate_hwpx: async input =>
    okText(await runHelper(["validate", await requireReadableFile(input.file_path)])),

  detect_format: async input =>
    okText(await runHelper(["detect", await requireReadableFile(input.file_path)])),

  parse_document: async (input, tmp) => {
    const file = await requireReadableFile(input.file_path);
    const args = ["parse", file];
    const opts = { ...input };

    if (opts.keep_layout_tables === true) {
      if (opts.layout_tables && opts.layout_tables !== "keep") {
        throw new Error("keep_layout_tables=true conflicts with layout_tables");
      }
      opts.layout_tables = "keep";
    }
    if (typeof opts.password === "string" && opts.password !== "") {
      if (opts.password_file) throw new Error("give password or password_file, not both");
      opts.password_file = await tempFile(tmp, "password", opts.password);
    }

    pushFlag(args, "--ocr", ocrArg(opts.ocr));
    pushFlag(args, "--include-blocks", boolArg(opts.include_blocks, true) ? "true" : "false");
    pushFlag(args, "--include-field-placeholders", boolArg(opts.include_field_placeholders, false) ? "true" : "false");
    pushFlag(args, "--plain", boolArg(opts.plain, false) ? "true" : "false");
    pushFlag(args, "--html-tables", boolArg(opts.html_tables, false) ? "true" : "false");
    pushTableFormat(args, opts);
    pushParseOptions(args, opts);
    return okText(await runHelper(args));
  },

  parse_metadata: async input => {
    const args = ["metadata", await requireReadableFile(input.file_path)];
    pushTableFormat(args, input);
    pushParseOptions(args, input);
    return okText(await runHelper(args));
  },

  parse_pages: async input => {
    requireString(input.pages, "pages");
    const args = ["parse-pages", await requireReadableFile(input.file_path)];
    pushFlag(args, "--ocr", ocrArg(input.ocr));
    pushTableFormat(args, input);
    pushParseOptions(args, input);
    return okText(await runHelper(args));
  },

  parse_table: async input => {
    const index = input.table_index;
    if (!Number.isInteger(index) || index < 0) throw new Error("table_index must be an integer >= 0");
    const args = ["parse-table", await requireReadableFile(input.file_path)];
    pushFlag(args, "--ocr", ocrArg(input.ocr));
    pushFlag(args, "--images", boolArg(input.images, true) ? "true" : "false");
    pushParseOptions(args, input, ["images"]);
    const result = await runHelper(args);
    const list = Array.isArray(result) ? result : result?.tables;
    if (!Array.isArray(list)) throw new Error("unexpected parse-table output: no tables list");
    if (index >= list.length) throw new Error(`table_index ${index} is out of range (${list.length} tables)`);
    return okText(list[index]);
  },

  parse_chunks: async input => {
    const args = ["parse-chunks", await requireReadableFile(input.file_path)];
    pushFlag(args, "--ocr", ocrArg(input.ocr));
    pushFlag(args, "--granularity", input.granularity || "section");
    if (boolArg(input.include_table_cells)) args.push("--include-table-cells");
    pushParseOptions(args, input);
    return okText(await runHelper(args));
  },

  parse_form: async input =>
    okText(await runHelper(["form-parse", await requireReadableFile(input.file_path)])),

  compare_documents: async input => {
    const a = await requireReadableFile(input.file_path_a, "file_path_a");
    const b = await requireReadableFile(input.file_path_b, "file_path_b");
    return okText(await runHelper(["compare", a, b, "--ocr", ocrArg(input.ocr)]));
  },

  fill_form: async (input, tmp) => {
    if (input.fields !== undefined) {
      throw new Error(
        "inline fields are not accepted (values would stay in the conversation log): "
        + "write the JSON object to a file and pass fields_file"
      );
    }
    if (!!input.file_path === !!input.template) {
      throw new Error("exactly one of file_path or template is required");
    }
    const values = await requireReadableFile(input.fields_file, "fields_file");
    const args = ["fill"];
    if (input.file_path) args.push(await requireReadableFile(input.file_path));
    else args.push("--template", input.template);
    args.push("--values", values);

    if (input.formats !== undefined) {
      args.push("--formats", await tempFile(tmp, "formats.json", input.formats));
    }
    if (boolArg(input.require_unique)) args.push("--require-unique");
    if (input.mask_values !== false) args.push("--mask-values");

    const outputFormat = input.output_format || "hwpx-preserve";
    args.push("--format", outputFormat);
    if (outputFormat === "markdown") {
      if (input.output_path) throw new Error("output_path must not be used when output_format is markdown");
    } else {
      args.push("-o", await requireOutputPath(input.output_path));
    }
    return okText(await runHelper(args));
  },

  place_seal: async input => {
    const file = await requireReadableFile(input.file_path);
    const image = await requireReadableFile(input.image_path, "image_path");
    const output = await requireOutputPath(input.output_path);
    const args = ["seal-native", file, "--image", image, "-o", output];
    pushFlag(args, "--anchor", input.anchor || "(인)");
    pushFlag(args, "--occurrence", String(input.occurrence !== undefined ? input.occurrence : 0));
    pushFlag(args, "--mode", input.mode || "auto");
    for (const [key, flag] of [["size_mm", "--size-mm"], ["dx_mm", "--dx-mm"], ["dy_mm", "--dy-mm"]]) {
      if (input[key] !== undefined) pushFlag(args, flag, String(input[key]));
    }
    return okText(await runHelper(args));
  },

  patch_document: async (input, tmp) => {
    const file = await requireReadableFile(input.file_path);
    const output = await requireOutputPath(input.output_path);
    const markdown = await tempFile(tmp, "edited.md", requireString(input.edited_markdown, "edited_markdown"));
    const args = ["patch-native", file, "--markdown", markdown, "-o", output];
    if (input.structure === false) args.push("--no-structure");
    return okText(await runHelper(args));
  },

  redact_document: async (input, tmp) => {
    const file = await requireReadableFile(input.file_path);
    const args = ["redact", file];
    if (input.rules !== undefined) args.push("--rules", await tempFile(tmp, "rules.json", input.rules));
    pushFlag(args, "--mask-char", input.mask_char);
    if (boolArg(input.dry_run, false)) args.push("--dry-run");
    else args.push("-o", await requireOutputPath(input.output_path));
    return okText(await runHelper(args));
  },

  render_document: async (input, tmp) => {
    const file = await requireReadableFile(input.file_path);
    const format = input.format || "png";
    const raster = format === "png" || format === "jpeg";
    if (!raster && !input.output_path) throw new Error(`output_path is required for format ${format}`);

    const inline = !input.output_path;
    const output = inline ? join(tmp, format === "png" ? "render.png" : "render.jpg") : await requireOutputPath(input.output_path);
    const args = ["render-native", file, "-o", output, "--format", format];
    pushFlag(args, "--pages", input.pages);
    if (input.max_width_px !== undefined) pushFlag(args, "--max-width-px", String(input.max_width_px));
    for (const text of Array.isArray(input.highlights) ? input.highlights : []) args.push("--highlight", text);
    pushFlag(args, "--reflow-mode", input.reflow_mode);
    const result = await runHelper(args);
    if (!inline) return okText(result);

    const mimeType = format === "png" ? "image/png" : "image/jpeg";
    const names = (await readdir(tmp)).filter(n => n.startsWith("render")).sort().slice(0, 8);
    const content = [{ type: "text", text: JSON.stringify({ ...(typeof result === "object" ? result : { result }), files: names.length }) }];
    for (const n of names) content.push({ type: "image", data: (await readFile(join(tmp, n))).toString("base64"), mimeType });
    return { content };
  },

  crop_regions: async input => {
    const file = await requireReadableFile(input.file_path);
    const args = ["crop-regions", file];
    for (const target of Array.isArray(input.target) ? input.target : ["table"]) args.push("--target", target);
    pushFlag(args, "--format", input.format || "png");
    pushFlag(args, "--pages", input.pages);
    if (input.padding_pt !== undefined) pushFlag(args, "--padding-pt", String(input.padding_pt));
    args.push("--output-dir", resolve(requireString(input.output_dir, "output_dir")));
    return okText(await runHelper(args));
  },

  extract_tables: async input => {
    const file = await requireReadableFile(input.file_path);
    const args = ["extract-tables", file];
    pushFlag(args, "--visual", input.visual || "none");
    pushFlag(args, "--format", input.format || "png");
    if (input.padding_pt !== undefined) pushFlag(args, "--padding-pt", String(input.padding_pt));
    if (boolArg(input.cells)) args.push("--cells");
    if (input.output_dir) args.push("--output-dir", resolve(input.output_dir));
    return okText(await runHelper(args));
  },

  extract_profile: async input =>
    okText(await runHelper([
      "profile-extract",
      await requireReadableFile(input.hwpx_path, "hwpx_path"),
      "-o",
      await requireOutputPath(input.output_path)
    ])),

  generate_document: async (input, tmp) => {
    const text = requireString(input.markdown, "markdown");
    const markdown = await tempFile(tmp, "doc.md", text);
    const args = ["generate-hwpx-advanced", markdown, "-o", await requireOutputPath(input.output_path)];

    const options = {};
    for (const key of GENERATE_OPTION_KEYS) if (input[key] !== undefined) options[key] = input[key];
    if (Object.keys(options).length > 0) args.push("--options", await tempFile(tmp, "options.json", options));

    if (input.profile_path) args.push("--profile", await requireReadableFile(input.profile_path, "profile_path"));
    if (input.template_path) args.push("--template", await requireReadableFile(input.template_path, "template_path"));
    if (input.image_dir) for (const image of await imagesFromDir(text, input.image_dir)) args.push("--image", image);
    return okText(await runHelper(args));
  },

  lint_document: async (input, tmp) => {
    const sources = [input.text, input.file_path, input.blocks].filter(v => v !== undefined).length;
    if (sources !== 1) throw new Error("exactly one of text, file_path or blocks is required");

    const args = ["lint-full"];
    if (input.file_path) args.push("--file", await requireReadableFile(input.file_path));
    else if (input.text !== undefined) args.push("--text-file", await tempFile(tmp, "text.md", input.text));
    else args.push("--blocks", await tempFile(tmp, "blocks.json", input.blocks));
    for (const key of ["munche", "slop", "logic", "numbers", "budget", "gate"]) {
      if (input[key] !== undefined) args.push(`--${key}`, boolArg(input[key]) ? "true" : "false");
    }
    pushFlag(args, "--preset", input.preset);
    return okText(await runHelper(args));
  }
};

server.setRequestHandler(CallToolRequestSchema, async request => {
  try {
    const handler = handlers[request.params.name];
    if (!handler) return errorText(`unknown tool: ${request.params.name}`);
    return await withTemp(tmp => handler(request.params.arguments || {}, tmp));
  } catch (error) {
    return errorText(error instanceof Error ? error.message : String(error));
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
