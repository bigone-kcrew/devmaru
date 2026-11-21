import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const BASE_URL =
  process.env.CRAWL4AI_API_URL ??
  "http://crawl4ai-api:3431";

const server = new Server(
  {
    name: "@@PFX@@-crawl4ai",
    version: "0.2.0",
  },
  {
    capabilities: {
      tools: {},
    },
  },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "crawl4ai_health",
      description:
        "Check the @@BRAND@@ central Crawl4AI API health.",
      inputSchema: {
        type: "object",
        properties: {},
        additionalProperties: false,
      },
    },
    {
      name: "crawl4ai_crawl",
      description:
        "Crawl one or more known public HTTP/HTTPS URLs using the @@BRAND@@ central Crawl4AI service and return Markdown. Use when the target URLs are already known.",
      inputSchema: {
        type: "object",
        properties: {
          urls: {
            type: "array",
            minItems: 1,
            maxItems: 5,
            items: {
              type: "string",
              minLength: 1,
            },
          },
        },
        required: ["urls"],
        additionalProperties: false,
      },
    },
    {
      name: "crawl4ai_site",
      description:
        "Explore and crawl pages within one public website, following same-site internal links and returning Markdown. Use when the user wants pages discovered within a specific site. This is site traversal, not internet-wide search.",
      inputSchema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            minLength: 1,
          },
          max_depth: {
            type: "integer",
            minimum: 0,
            maximum: 5,
            default: 1,
          },
          max_pages: {
            type: ["integer", "null"],
            minimum: 1,
            maximum: 500,
            default: null,
          },
          query: {
            type: ["string", "null"],
            maxLength: 200,
            default: null,
          },
        },
        required: ["url"],
        additionalProperties: false,
      },
    },
  ],
}));

function validateHttpUrl(url) {
  return (
    typeof url === "string" &&
    (url.startsWith("https://") || url.startsWith("http://"))
  );
}

async function readJson(response) {
  const text = await response.text();

  try {
    return JSON.parse(text);
  } catch {
    return {
      detail: text,
    };
  }
}

/* 한 페이지가 Agent 컨텍스트를 삼키지 못하게 한다. 2026-09-21 실측: 한국어 위키
   한 쪽이 481,322자였고 상한이 없었다. 환경변수로 조정한다. */
const MAX_MARKDOWN_CHARS = Number(process.env.CRAWL4AI_MAX_MARKDOWN_CHARS ?? 200000);
const MAX_TOTAL_CHARS = Number(process.env.CRAWL4AI_MAX_TOTAL_CHARS ?? 400000);

/* 전문을 회원 컨테이너에 남긴다. 잘라내면 내용이 사라지지만, 파일로 두면
   Agent 가 필요한 부분만 다시 읽을 수 있다. 실패해도 수집 자체는 계속된다 --
   저장은 편의이지 수집의 전제가 아니다. */
const SPILL_DIR = path.join(os.homedir(), ".@@PFX@@", "crawl4ai");
const SPILL_KEEP = Number(process.env.CRAWL4AI_SPILL_KEEP ?? 20);

function spillToFile(text, label) {
  try {
    fs.mkdirSync(SPILL_DIR, { recursive: true, mode: 0o700 });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const slug = String(label).replace(/[^A-Za-z0-9.-]+/g, "-").slice(0, 40);
    const file = path.join(SPILL_DIR, `${stamp}-${slug}.md`);
    fs.writeFileSync(file, text, { mode: 0o600 });

    /* 오래된 것부터 지운다. 수집 기록이 무한정 쌓이면 그것도 문제다. */
    const kept = fs
      .readdirSync(SPILL_DIR)
      .filter((n) => n.endsWith(".md"))
      .sort();
    for (const name of kept.slice(0, Math.max(0, kept.length - SPILL_KEEP))) {
      fs.unlinkSync(path.join(SPILL_DIR, name));
    }
    return file;
  } catch {
    return null;
  }
}

/* 자른 사실을 본문 안에 남긴다. 잘린 줄 모르면 Agent 는 없는 내용을 추론한다. */
function clamp(text, limit, what, label) {
  if (typeof text !== "string" || text.length <= limit) {
    return text ?? "";
  }
  const kept = text.slice(0, limit);
  const file = spillToFile(text, label ?? what);
  const where = file
    ? `전문은 ${file} 에 저장했습니다. 필요한 부분은 그 파일을 읽으세요.`
    : `전문 저장에 실패했습니다. 더 좁은 URL을 주거나 crawl4ai_site의 query로 ` +
      `필요한 페이지만 고르세요.`;
  return `${kept}\n\n[...이어짐] ${what} 전체 ${text.length.toLocaleString()}자 중 ` +
    `앞 ${limit.toLocaleString()}자입니다. ${where}`;
}

function markdownFromResult(result) {
  let host = "page";
  try {
    host = new URL(result?.url ?? "").hostname || "page";
  } catch {
    /* url 이 없거나 깨졌어도 저장은 되어야 한다 */
  }
  return clamp(
    result?.markdown?.raw_markdown ??
      result?.markdown?.markdown_with_citations ??
      "",
    MAX_MARKDOWN_CHARS,
    "이 페이지",
    host,
  );
}

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  if (name === "crawl4ai_health") {
    try {
      const response = await fetch(`${BASE_URL}/health`);
      const payload = await readJson(response);

      if (!response.ok) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(payload, null, 2),
            },
          ],
          isError: true,
        };
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(payload, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Crawl4AI API health error: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  }

  if (name === "crawl4ai_crawl") {
    const urls = args.urls;

    if (!Array.isArray(urls) || urls.length < 1 || urls.length > 5) {
      return {
        content: [
          {
            type: "text",
            text: "urls must contain between 1 and 5 URLs",
          },
        ],
        isError: true,
      };
    }

    for (const url of urls) {
      if (!validateHttpUrl(url)) {
        return {
          content: [
            {
              type: "text",
              text: `Only http:// and https:// URLs are allowed: ${url}`,
            },
          ],
          isError: true,
        };
      }
    }

    try {
      const response = await fetch(`${BASE_URL}/crawl`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ urls }),
      });

      const payload = await readJson(response);

      if (!response.ok || !payload.success) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(payload, null, 2),
            },
          ],
          isError: true,
        };
      }

      const output = payload.results
        .map((result) => {
          return [
            `URL: ${result.url}`,
            `HTTP: ${result.status_code}`,
            "",
            markdownFromResult(result),
          ].join("\n");
        })
        .join("\n\n---\n\n");

      return {
        content: [
          {
            type: "text",
            text: clamp(output, MAX_TOTAL_CHARS, "이번 수집", "crawl"),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Crawl4AI crawl error: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  }

  if (name === "crawl4ai_site") {
    const url = args.url;

    if (!validateHttpUrl(url)) {
      return {
        content: [
          {
            type: "text",
            text: `Only http:// and https:// URLs are allowed: ${url}`,
          },
        ],
        isError: true,
      };
    }

    const body = { url };

    if (Number.isInteger(args.max_depth)) {
      body.max_depth = args.max_depth;
    }

    if (Number.isInteger(args.max_pages)) {
      body.max_pages = args.max_pages;
    }

    if (
      typeof args.query === "string" &&
      args.query.trim().length > 0
    ) {
      body.query = args.query.trim();
    }

    try {
      const response = await fetch(`${BASE_URL}/crawl/site`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      const payload = await readJson(response);

      if (!response.ok || !payload.success) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(payload, null, 2),
            },
          ],
          isError: true,
        };
      }

      const header = [
        `Seed: ${payload.seed_url}`,
        `Pages crawled: ${payload.pages_crawled}`,
        `Max depth: ${payload.max_depth}`,
        `Requested page limit: ${payload.max_pages_requested ?? "none"}`,
        `Timed out: ${payload.timed_out}`,
        `Queue remaining: ${payload.queue_remaining}`,
      ].join("\n");

      const pages = payload.results
        .map((result, index) => {
          return [
            `# Page ${index + 1}`,
            `URL: ${result.url}`,
            `HTTP: ${result.status_code}`,
            "",
            markdownFromResult(result),
          ].join("\n");
        })
        .join("\n\n---\n\n");

      return {
        content: [
          {
            type: "text",
            text: clamp(`${header}\n\n${pages}`, MAX_TOTAL_CHARS, "이번 사이트 수집", "site"),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Crawl4AI site crawl error: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  }

  return {
    content: [
      {
        type: "text",
        text: `Unknown tool: ${name}`,
      },
    ],
    isError: true,
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);
