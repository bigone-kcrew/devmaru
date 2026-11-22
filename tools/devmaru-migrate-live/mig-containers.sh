#!/usr/bin/env bash
# mig-containers.sh — compose 가 아니라 «docker run» 으로 직접 만든 컨테이너의 설정을 «다시 만드는 스크립트» 로 export 한다. 구 서버에서(docker 그룹 또는 root):
#   bash mig-containers.sh export <컨테이너>...   → $MIG_CONT_DIR(기본 ~/<접두어>-mig-containers, 700)/<이름>.sh(700) · <이름>.env(600)
#   bash mig-containers.sh show                   만든 스크립트를 보여 준다(환경변수 값은 .env 에만 있어 출력되지 않는다)
# 신 서버: 데이터 최종 동기화 뒤 <이름>.sh 를 실행 → «docker run -d»(만들고 바로 시작). 끝나면 .env 를 지운다.
# 옮기는 것: 이미지·재시작 정책·사용자(user)·네트워크(첫 번째 + connect)·바인드/이름 있는 볼륨·포트·이미지에 없는 환경변수·entrypoint/cmd 차이.
# compose 가 만든 컨테이너(com.docker.compose.project 라벨)는 건너뛴다 — compose 파일은 그룹 전송으로 옮긴다. 익명 볼륨은 새로 만든다.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
run(){
load_conf; OUT=${MIG_CONT_DIR:-$HOME/$PFX-mig-containers}
CMD=${1:-}; shift || true
case "$CMD" in
export)
  [ $# -gt 0 ] || fail "컨테이너 이름을 적으세요: $0 export <이름>..."
  command -v docker >/dev/null || fail "docker 없음"; umask 077; mkdir -p "$OUT" && chmod 700 "$OUT"
  for c in "$@"; do
    docker inspect "$c" >/dev/null 2>&1 || fail "컨테이너 없음: $c"
    img=$(docker inspect --format '{{.Config.Image}}' "$c")
    CI=$(docker inspect "$c") II=$(docker image inspect "$img" 2>/dev/null || echo '[{"Config":{}}]') OUTDIR="$OUT" NAME="$c" python3 - <<'PY' || fail "스크립트 생성 실패: $c"
import json, os, re, shlex, sys
j = json.loads(os.environ["CI"])[0]; img = (json.loads(os.environ["II"])[0].get("Config") or {})
name, out = os.environ["NAME"], os.environ["OUTDIR"]
c, hc = j["Config"], j["HostConfig"]
if (c.get("Labels") or {}).get("com.docker.compose.project"):
    print("  %s: compose 가 관리하는 컨테이너 — 건너뜀" % name); sys.exit(0)
nets = list((j.get("NetworkSettings") or {}).get("Networks") or {})
args = ["docker", "run", "-d", "--name", name, "--restart", hc["RestartPolicy"]["Name"] or "no"]
if c.get("User"): args += ["--user", c["User"]]
args += ["--network", nets[0] if nets else "bridge"]
for m in j.get("Mounts", []):
    if m["Type"] == "bind": args += ["-v", "%s:%s%s" % (m["Source"], m["Destination"], "" if m.get("RW", True) else ":ro")]
    elif m["Type"] == "volume" and not re.fullmatch(r"[0-9a-f]{64}", m.get("Name", "")): args += ["-v", "%s:%s" % (m["Name"], m["Destination"])]
for cport, binds in (hc.get("PortBindings") or {}).items():
    for b in binds or []: args += ["-p", "%s%s:%s" % (b["HostIp"] + ":" if b.get("HostIp") else "", b["HostPort"], cport)]
env = [e for e in (c.get("Env") or []) if e not in set(img.get("Env") or []) and not e.startswith("PATH=")]
if env:
    p = os.path.join(out, name + ".env")
    with open(os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f: f.write("\n".join(env) + "\n")
    args += ["--env-file", "@ENVFILE@"]
ent, cmd = c.get("Entrypoint"), c.get("Cmd")
if ent and ent != img.get("Entrypoint"): args += ["--entrypoint", ent[0]]
args.append(c["Image"])
if ent and ent != img.get("Entrypoint"): args += ent[1:]
if cmd and cmd != img.get("Cmd"): args += cmd
q = lambda a: '"$(dirname "$0")/%s.env"' % name if a == "@ENVFILE@" else shlex.quote(a)
lines = ["#!/usr/bin/env bash", "# mig-containers.sh 가 구 서버에서 생성 — 신 서버에서 데이터 최종 동기화 뒤 실행(만들고 바로 시작한다).", "set -euo pipefail",
         " ".join(q(a) for a in args)] + ["docker network connect %s %s" % (shlex.quote(n), shlex.quote(name)) for n in nets[1:]]
p = os.path.join(out, name + ".sh")
with open(os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o700), "w") as f: f.write("\n".join(lines) + "\n")
print("  %s: 이미지=%s 네트워크=%s 환경변수 %d개 → %s" % (name, c["Image"], ",".join(nets) or "-", len(env), p))
PY
  done
  say "완료. .env 에는 비밀이 들어 있을 수 있다(600) — 신 서버로 옮겨 쓴 뒤 지우세요.";;
show)
  [ -d "$OUT" ] || fail "$OUT 없음 — export 먼저"
  for f in "$OUT"/*.sh; do [ -f "$f" ] || continue; say "== $(basename "$f")"; sed -n '4,$p' "$f"; done;;
*) fail "사용법: $0 export <이름>... | show";;
esac
}
run "$@"; exit $?
