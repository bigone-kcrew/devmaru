"""devmaru_render: 템플릿 트리(@@토큰@@) → 설치용 트리. devmaru-install 과 export-kit/render.py 가 같이 쓴다."""
import os, re, shutil, subprocess, sys

PFX_RE = re.compile(r"[a-z][a-z0-9]{1,11}")
RESERVED = {"root", "admin", "sudo", "docker", "ubuntu", "dev", "user", "users", "system", "caddy", "ssh", "web", "app", "api", "db", "n8n", "mcp", "bin", "etc", "opt", "srv", "var", "tmp", "home", "snap", "lib", "usr"}
HOST_LABELS = "FILES N8N API MCP SKILLS STATUS UPTIME COCKPIT SSH SMB ADMIN".split()
TOK = re.compile(r"@@([A-Z0-9_]+)@@")

def check_prefix(p):
    if not PFX_RE.fullmatch(p or ""): return "접두어는 소문자로 시작하는 소문자·숫자 2~12자여야 합니다"
    if p in RESERVED: return f"'{p}' 는 예약어라 쓸 수 없습니다"
    return None

def values(v):
    """v: dict(PFX BRAND DOMAIN PORTAL_LABEL ADMIN_CIDRS GID ADMIN_USER TZ SERVER_IP SFTP_BIND [<LABEL>_HOST])"""
    o = {"PFX": v["PFX"], "PFX_UP": v["PFX"].upper(), "BRAND": v["BRAND"], "DOMAIN": v["DOMAIN"],
         "PORTAL_HOST": f"{v.get('PORTAL_LABEL', 'portal')}.{v['DOMAIN']}", "ADMIN_CIDRS": v.get("ADMIN_CIDRS", "127.0.0.1/32"),
         "GID": str(v.get("GID", 1001)), "ADMIN_USER": v.get("ADMIN_USER", "admin"), "TZ": v.get("TZ", "UTC"),
         "SERVER_IP": v.get("SERVER_IP", "0.0.0.0"), "SFTP_BIND": v.get("SFTP_BIND", "0.0.0.0"), "SSH_PORT": str(v.get("SSH_PORT", 22))}
    for l in HOST_LABELS: o[l + "_HOST"] = v.get(l + "_HOST") or f"{l.lower()}.{v['DOMAIN']}"
    return o

def render_tree(tree, out, vals, check=True):
    sub = lambda t: TOK.sub(lambda m: vals.get(m.group(1), m.group(0)), t)
    if os.path.exists(out): shutil.rmtree(out)
    for root, _, files in os.walk(tree):
        for f in files:
            sp = os.path.join(root, f); rel = os.path.relpath(sp, tree)
            if rel == "links.list": continue
            dp = os.path.join(out, sub(rel)); os.makedirs(os.path.dirname(dp), exist_ok=True)
            d = open(sp, "rb").read()
            try: d = sub(d.decode()).encode()
            except UnicodeDecodeError: pass
            open(dp, "wb").write(d); shutil.copymode(sp, dp)
    ll = os.path.join(tree, "links.list")
    if os.path.exists(ll):
        for line in open(ll):
            n, t = line.rstrip("\n").split("\t"); dp = os.path.join(out, sub(n)); os.makedirs(os.path.dirname(dp), exist_ok=True)
            os.symlink(sub(t), dp)
    left, bad = [], []
    for root, _, files in os.walk(out):
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p): continue
            try: txt = open(p, encoding="utf-8").read()
            except Exception: continue
            m = TOK.findall(txt)
            if m: left.append((os.path.relpath(p, out), sorted(set(m))))
            if not check: continue
            head = txt.split("\n", 1)[0]
            if (head.startswith("#!") and "bash" in head) or p.endswith(".sh"):
                r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
                if r.returncode: bad.append((os.path.relpath(p, out), r.stderr.strip()[:120]))
            elif (head.startswith("#!") and "python" in head) or p.endswith(".py"):
                try: compile(txt, p, "exec")
                except SyntaxError as e: bad.append((os.path.relpath(p, out), str(e)[:120]))
    return left, bad
