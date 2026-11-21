// @@PFX@@-mcp-hub: 컨테이너당 하나. 127.0.0.1 로만 받는다.
//  (a) 원격 MCP(레지스트리에 켠 서비스): 회원 토큰 파일을 요청마다 읽어 붙여 그대로 중계한다.
//  (b) stdio MCP(memory·crawl4ai): 자식 프로세스 하나를 세션들이 공유한다. 첫 요청에 띄우고 유휴면 내린다.
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { Readable } from "node:stream";

const PORT = 18940;
const IDLE_MS = 600_000;
const CALL_MS = 300_000; // 기존 중계(CALL_TIMEOUT_MS)와 같다
const home = os.homedir();
// 원격 MCP 서비스: 관리자(root)만 쓰는 레지스트리에 적힌 https 주소로만 토큰이 간다(멤버·환경변수로 못 바꿈).
const REGISTRY = "/opt/@@PFX@@/managed-mcp/remote-services.json";
function remoteRoutes() {
  let list; try { list = JSON.parse(fs.readFileSync(REGISTRY, "utf8")).services; } catch { return {}; }
  const out = {};
  for (const s of Array.isArray(list) ? list : []) {
    if (!/^[a-z][a-z0-9-]{0,30}$/.test(s?.name ?? "") || !/^https:\/\/\S+$/.test(s?.url ?? "")) continue;
    out[`/${s.name}/mcp`] = { url: s.url, files: [`/opt/@@PFX@@/${s.name}-token`, path.join(home, ".@@PFX@@", `${s.name}-token`)] };
  }
  return out;
}

const STDIO = {
  "/memory/mcp": { cmd: "python3", args: ["/opt/@@PFX@@/managed-mcp/memory/server.py"] },
  "/crawl4ai/mcp": { cmd: "node", args: ["/opt/@@PFX@@/managed-mcp/crawl4ai/server.mjs"] },
  "/kordoc/mcp": { cmd: "node", args: ["/opt/@@PFX@@/managed-mcp/kordoc/server.mjs"], ms: 10_800_000 },   // 3시간 — kordoc-big 서버 상한과 같다(실제 한도는 kordoc-api 헬퍼 600초·중앙 서비스 600초가 먼저 걸린다)
  "/markitdown/mcp": { cmd: "node", args: ["/opt/@@PFX@@/managed-mcp/markitdown/server.mjs"], ms: 900_000 },
};
const PASS = ["accept", "content-type", "mcp-session-id", "mcp-protocol-version", "last-event-id"];
const log = (m) => process.stderr.write(`@@PFX@@-mcp-hub: ${m}\n`);
const send = (res, status, obj, headers = {}) => {
  res.writeHead(status, { "content-type": "application/json", ...headers });
  res.end(obj === undefined ? "" : JSON.stringify(obj));
};
const rpcErr = (id, code, message) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

function readToken(files) {
  for (const f of files) {
    let raw;
    try { raw = fs.readFileSync(f, "utf8").trim(); } catch { continue; }
    // 헤더 주입을 막는다: 보이는 ASCII 한 줄만 허용.
    return /^[\x21-\x7e]{16,1024}$/.test(raw) ? raw : null;
  }
  return null;
}

async function proxy(req, res, route) {
  const token = readToken(route.files);
  if (!token) return send(res, 401, rpcErr(null, -32001, "token file missing or malformed (관리자에게 문의)"));
  const headers = { authorization: `Bearer ${token}` };
  for (const h of PASS) if (req.headers[h]) headers[h] = req.headers[h];
  const ac = new AbortController();
  res.on("close", () => ac.abort());
  try {
    const hasBody = !["GET", "HEAD", "DELETE"].includes(req.method);
    const up = await fetch(route.url, { method: req.method, headers, signal: ac.signal, ...(hasBody ? { body: Readable.toWeb(req), duplex: "half" } : {}) });
    const out = {};
    for (const h of ["content-type", "mcp-session-id", "cache-control"]) if (up.headers.get(h)) out[h] = up.headers.get(h);
    res.writeHead(up.status, out);
    if (up.body) Readable.fromWeb(up.body).on("error", () => res.destroy()).pipe(res); else res.end();
  } catch (e) {
    if (!res.headersSent) send(res, 502, rpcErr(null, -32002, "upstream error: " + String(e.message).slice(0, 100)));
    else res.destroy();
  }
}

class Bridge {
  constructor(name, spec) { Object.assign(this, { name, spec, child: null, pending: new Map(), next: 1, idle: null, starting: null, init: null }); }
  ensure() {
    if (this.child && this.init) return Promise.resolve();
    return (this.starting ??= this.start().finally(() => { this.starting = null; }));
  }
  async start() {
    const c = spawn(this.spec.cmd, this.spec.args, { stdio: ["pipe", "pipe", "inherit"], cwd: home, env: { ...process.env, AI_MCP_HUB_CHILD: "1" } });
    this.child = c; this.init = null;
    const gone = () => {
      if (this.child !== c) return;
      this.child = null; this.init = null;
      for (const [id, done] of this.pending) done({ id, error: { code: -32003, message: `${this.name} MCP 서버가 종료되었습니다` } });
      this.pending.clear();
      log(`${this.name} 자식 종료`);
    };
    c.on("exit", gone); c.on("error", gone);
    c.stdin.on("error", () => {});
    readline.createInterface({ input: c.stdout }).on("line", (line) => {
      let m; try { m = JSON.parse(line); } catch { return; }
      if (m.id !== undefined && m.method === undefined) { const done = this.pending.get(m.id); if (done) { this.pending.delete(m.id); done(m); } }
    });
    const r = await this.rpc("initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "@@PFX@@-mcp-hub", version: "1" } }, 30_000);
    if (r.error || !this.child) { this.stop(); throw new Error(r.error?.message ?? "start failed"); }
    this.init = r.result;
    c.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    log(`${this.name} 자식 시작 pid=${c.pid}`);
  }
  rpc(method, params, ms = this.spec.ms ?? CALL_MS, meta = {}) {
    const id = this.next++; meta.id = id;
    return new Promise((resolve) => {
      const t = setTimeout(() => { this.pending.delete(id); this.cancel(id); resolve({ id, error: { code: -32004, message: `timeout ${ms / 1000}s` } }); }, ms);
      this.pending.set(id, (m) => { clearTimeout(t); resolve(m); });
      clearTimeout(this.idle);
      if (!this.child) return this.pending.get(id)?.({ id, error: { code: -32003, message: "no child" } });
      this.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    }).finally(() => { if (!this.pending.size) this.idle = setTimeout(() => this.stop(), IDLE_MS); });
  }
  cancel(id) { this.child?.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/cancelled", params: { requestId: id, reason: "client gone" } }) + "\n"); }
  stop() { clearTimeout(this.idle); const c = this.child; if (c) { this.child = null; this.init = null; c.kill("SIGTERM"); } }
}

const inflight = new Map();   // `${세션id}:${클라이언트 id}` → 자식 쪽 호출 id(취소용)
const bridges = Object.fromEntries(Object.entries(STDIO).map(([p, s]) => [p, new Bridge(p.split("/")[1], s)]));

async function bridgeReq(req, res, b) {
  if (req.method === "DELETE") return send(res, 200);
  if (req.method !== "POST") return send(res, 405, undefined, { allow: "POST, DELETE" });
  const chunks = []; for await (const c of req) chunks.push(c);
  let m; try { m = JSON.parse(Buffer.concat(chunks)); } catch { return send(res, 400, rpcErr(null, -32700, "parse error")); }
  if (Array.isArray(m) || typeof m !== "object" || !m) return send(res, 400, rpcErr(null, -32600, "batch not supported"));
  if (m.id === undefined) { // 알림은 받아두기만 한다
    if (m.method === "notifications/cancelled") { const meta = inflight.get(`${req.headers["mcp-session-id"] ?? ""}:${m.params?.requestId}`); if (meta) b.cancel(meta.id); }
    return send(res, 202);
  }
  try { await b.ensure(); } catch (e) { return send(res, 502, rpcErr(m.id, -32003, `${b.name} MCP 시작 실패: ${String(e.message).slice(0, 100)}`)); }
  if (m.method === "initialize") {
    const want = m.params?.protocolVersion ?? "";
    return send(res, 200, { jsonrpc: "2.0", id: m.id, result: { ...b.init, protocolVersion: want >= "2025-03-26" ? want : "2025-03-26" } }, { "mcp-session-id": randomUUID() }); // 세션 상태가 없어 허브가 다시 떠도 기존 id 를 그대로 받는다
  }
  if (m.method !== "tools/call") {
    const r = await b.rpc(m.method, m.params);
    return send(res, 200, { jsonrpc: "2.0", id: m.id, ...(r.error ? { error: r.error } : { result: r.result }) });
  }
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
  res.write(": start\n\n");
  const ping = setInterval(() => res.write(": ping\n\n"), 15_000);
  const meta = {}, key = `${req.headers["mcp-session-id"] ?? ""}:${m.id}`; inflight.set(key, meta);
  let done = false; res.on("close", () => { clearInterval(ping); inflight.delete(key); if (!done && meta.id) b.cancel(meta.id); });
  const r = await b.rpc(m.method, m.params, undefined, meta);
  done = true; clearInterval(ping); inflight.delete(key);
  res.end(`event: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: m.id, ...(r.error ? { error: r.error } : { result: r.result }) })}\n\n`);
}

http.createServer((req, res) => {
  if (req.headers.origin) return send(res, 403, rpcErr(null, -32000, "browser origin refused")); // DNS rebinding 방지
  const url = req.url.split("?")[0];
  if (url === "/healthz") return send(res, 200, { ok: true, routes: [...Object.keys(remoteRoutes()), ...Object.keys(STDIO)] });
  const remote = remoteRoutes()[url];
  if (remote) return void proxy(req, res, remote);
  if (bridges[url]) return void bridgeReq(req, res, bridges[url]).catch((e) => { if (!res.headersSent) send(res, 500, rpcErr(null, -32603, String(e.message).slice(0, 100))); });
  send(res, 404);
}).listen(PORT, "127.0.0.1");
process.on("SIGTERM", () => { for (const b of Object.values(bridges)) b.stop(); process.exit(0); });
