#!/usr/bin/env node

import { access, readFile, stat } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { basename, extname, isAbsolute, resolve as nodeResolve } from "node:path";

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


const BASE_URL =
  process.env.MARKITDOWN_API_URL || "http://markitdown:3410";

const MAX_FILE_MB = Number(process.env.MARKITDOWN_MAX_FILE_MB || "100");
const MAX_FILE_BYTES = MAX_FILE_MB * 1024 * 1024;

const KORDOC_FIRST = new Set([".pdf", ".hwp", ".hwpx"]);

function okText(value) {
  return {
    content: [{
      type: "text",
      text: typeof value === "string"
        ? value
        : JSON.stringify(value, null, 2)
    }]
  };
}

function errorText(message) {
  return {
    isError: true,
    content: [{
      type: "text",
      text: String(message)
    }]
  };
}

async function requireReadableFile(path) {
  if (typeof path !== "string" || path.trim() === "") {
    throw new Error("file_path is required");
  }

  const resolved = resolve(path);

  await access(resolved, fsConstants.R_OK);

  const info = await stat(resolved);

  if (!info.isFile()) {
    throw new Error("file_path must point to a regular file");
  }

  if (info.size > MAX_FILE_BYTES) {
    throw new Error(
      `file exceeds MarkItDown MCP limit of ${MAX_FILE_MB} MB`
    );
  }

  const suffix = extname(resolved).toLowerCase();

  if (KORDOC_FIRST.has(suffix)) {
    throw new Error(
      `${suffix} is Kordoc-first in @@BRAND@@; use the managed Kordoc tool instead`
    );
  }

  return resolved;
}

async function fetchJson(path) {
  const response = await fetch(`${BASE_URL}${path}`);
  const text = await response.text();

  if (!response.ok) {
    throw new Error(
      text || `MarkItDown API returned HTTP ${response.status}`
    );
  }

  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function convertFile(filePath) {
  const resolved = await requireReadableFile(filePath);
  const data = await readFile(resolved);

  const form = new FormData();
  form.append(
    "file",
    new Blob([data]),
    basename(resolved)
  );

  const response = await fetch(`${BASE_URL}/v1/convert`, {
    method: "POST",
    body: form
  });

  const text = await response.text();

  if (!response.ok) {
    throw new Error(
      text || `MarkItDown conversion returned HTTP ${response.status}`
    );
  }

  return text;
}

const tools = [
  {
    name: "markitdown_health",
    description:
      "Check connectivity and health of the @@BRAND@@ central MarkItDown service.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false
    }
  },
  {
    name: "markitdown_convert",
    description:
      "Convert a readable local file to Markdown through the @@BRAND@@ central MarkItDown service. PDF, HWP, and HWPX are intentionally Kordoc-first and rejected here.",
    inputSchema: {
      type: "object",
      properties: {
        file_path: {
          type: "string",
          description: "Readable local file path inside the member container."
        }
      },
      required: ["file_path"],
      additionalProperties: false
    }
  }
];

const server = new Server(
  {
    name: "@@PFX@@-markitdown",
    version: "0.1.0"
  },
  {
    capabilities: {
      tools: {}
    }
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

server.setRequestHandler(CallToolRequestSchema, async request => {
  const { name, arguments: args = {} } = request.params;

  try {
    switch (name) {
      case "markitdown_health":
        return okText(await fetchJson("/health"));

      case "markitdown_convert":
        return okText(await convertFile(args.file_path));

      default:
        return errorText(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return errorText(error?.message || String(error));
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
