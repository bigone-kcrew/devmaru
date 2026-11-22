#!/usr/bin/env bash
# mig-images.sh — 도커 이미지 이관: docker save | zstd | ssh → 신 서버 ~RUSER/<접두어>-images-stage/ , 신 서버에서 load + 이미지 ID 대조.
#   (구) sudo bash mig-images.sh plan [--extra 이미지:태그]...          컨테이너(docker ps -a)가 쓰는 이미지 + --extra, 크기, 제외된 태그 이미지(읽기 전용)
#   (구) sudo bash mig-images.sh send --apply [--extra 이미지:태그]...  한 번의 docker save 로 묶어(겹치는 레이어는 한 번만) 보내고 sha256 대조
#   (신) bash mig-images.sh load <archive.tar.zst> [--apply]            sha256·매니페스트 확인(읽기 전용) / --apply: docker load + ID 검증
# 회원의 루트리스 도커 이미지는 DOCKER_HOST=unix:///run/user/<uid>/docker.sock 를 붙여 plan·send 한다.
# ID 검증: 도커 엔진·이미지 저장소 종류(루트 vs 루트리스, 기존 저장소 vs containerd 저장소)에 따라 «이미지 ID» 가
#   config 해시일 수도, OCI 매니페스트(인덱스) 해시일 수도 있다. 그래서 저장 tar 의 manifest.json 에 적힌 Config 해시와도 비교한다.
#   일치 = 구 ID == 신 ID · 일치(config) = 신 ID 또는 구 ID 가 tar 의 Config 해시와 같음 · 확인 필요 = 셋 다 다름(아래 안내).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
hum(){ numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"; }
# 저장 tar 의 manifest.json → «태그<TAB>config 해시(sha256:…)» (Config 는 «<hex>.json» 또는 «blobs/sha256/<hex>»)
tar_configs(){ zstd -dc "$1" | tar -xOf - manifest.json | python3 -c '
import json,re,sys
for m in json.load(sys.stdin):
    h=re.search(r"[0-9a-f]{64}",m.get("Config","")); h="sha256:"+h.group(0) if h else "-"
    for t in m.get("RepoTags") or []: print(t+"\t"+h)'; }

run(){
load_conf; STAGE="$PFX-images-stage"
CMD=${1:-}; shift || true; APPLY=0; EXTRA=(); A=""
[ "$CMD" = load ] && { A=${1:-}; shift || true; }
while [ $# -gt 0 ]; do case "$1" in --apply) APPLY=1;; --extra) [ -n "${2:-}" ] || fail "--extra 에 이미지:태그"; EXTRA+=("$2"); shift;; *) fail "알 수 없는 옵션: $1";; esac; shift; done
case "$CMD" in plan|send|load) ;; *) fail "사용법: $0 plan|send [--apply] [--extra 이미지:태그] | load <archive> [--apply]";; esac
command -v docker >/dev/null || fail "docker 없음"; command -v zstd >/dev/null || fail "zstd 없음(apt install zstd)"

if [ "$CMD" = load ]; then
  [ -f "$A" ] || fail "archive 파일 없음: ${A:-<인자 없음>}"; B=${A%.tar.zst}; MF=$B.manifest.tsv; SF=$B.sha256
  [ -f "$MF" ] && [ -f "$SF" ] || fail "archive 옆에 매니페스트·sha256 파일이 없다($MF, $SF)"
  want=$(cut -d' ' -f1 "$SF"); got=$(sha256sum "$A" | cut -d' ' -f1); [ "$want" = "$got" ] || fail "sha256 불일치(기대 ${want:0:12} / 실제 ${got:0:12}) — archive 손상"
  CF=$(mktemp); trap 'rm -f "$CF"' EXIT; tar_configs "$A" > "$CF" || fail "archive 의 manifest.json 을 읽지 못했다"
  say "sha256 일치(${got:0:12}) · 이미지 $(wc -l < "$MF")개:"; awk -F'\t' '{printf "  %-48s 구 ID %s\n",$1,substr($2,8,12)}' "$MF"
  [ $APPLY = 1 ] || { say "(확인만 — 적재: $0 load $A --apply)"; return 0; }
  say "== docker load"; zstd -dc "$A" | docker load >/dev/null || fail "docker load 실패"
  bad=0; say "== 이미지 ID 대조"
  while IFS=$'\t' read -r tag id _; do
    cfg=$(awk -F'\t' -v t="$tag" '$1==t{print $2; exit}' "$CF")
    now=$(docker image inspect --format '{{.Id}}' "$tag" 2>/dev/null) || { say "  없음       $tag"; bad=1; continue; }
    if [ "$now" = "$id" ]; then say "  일치       $tag"
    elif [ -n "$cfg" ] && { [ "$now" = "$cfg" ] || [ "$id" = "$cfg" ]; }; then say "  일치(config) $tag — 엔진마다 ID 표기가 다르다(구 ${id:7:12} / 신 ${now:7:12} / config ${cfg:7:12})"
    else say "  확인 필요  $tag (구 ${id:7:12} / 신 ${now:7:12} / tar config ${cfg:7:12})"; bad=1; fi
  done < "$MF"
  [ $bad = 0 ] && { say "전부 일치"; return 0; }
  say "확인 필요 항목: 두 엔진이 모두 매니페스트 해시로 ID 를 보이면 셋이 다를 수 있다 — 양쪽에서 «docker image inspect --format '{{json .RootFS.Layers}}' <태그>» 를 비교하세요"
  return 1
fi

TAGS=(); UNTAGGED=()
while IFS= read -r t; do [ -n "$t" ] || continue
  if [[ "$t" =~ ^(sha256:)?[0-9a-f]{12,64}$ ]]; then UNTAGGED+=("$t"); else TAGS+=("$t"); fi
done < <({ docker ps -a --format '{{.Image}}'; printf '%s\n' "${EXTRA[@]}"; } | sort -u)
[ ${#TAGS[@]} -gt 0 ] || fail "보낼 이미지가 없다"
MF=$(mktemp); SHAF=$(mktemp); trap 'rm -f "$MF" "$SHAF"' EXIT; MISSING=0; TOTAL=0
say "== 선택된 이미지 ${#TAGS[@]}개(컨테이너가 쓰는 것 + --extra)"
for t in "${TAGS[@]}"; do
  id=$(docker image inspect --format '{{.Id}}' "$t" 2>/dev/null) && sz=$(docker image inspect --format '{{.Size}}' "$t" 2>/dev/null) || { say "  없음: $t"; MISSING=1; continue; }
  printf '%s\t%s\t%s\n' "$t" "$id" "$sz" >> "$MF"; TOTAL=$((TOTAL+sz)); printf '  %-48s %-14s %s\n' "$t" "${id:7:12}" "$(hum "$sz")"
done
say "  크기 합(레이어 중복 포함 상한): $(hum $TOTAL)"
[ ${#UNTAGGED[@]} = 0 ] || say "  주의: 태그 없는 이미지를 쓰는 컨테이너가 있다(${UNTAGGED[*]}) — 이름이 없어 제외. docker tag 로 이름을 붙이고 --extra"
say "== 제외된 태그 이미지(컨테이너가 쓰지 않음 — 필요하면 --extra)"
EXC=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | sort -u | grep -vxF -f <(printf '%s\n' "${TAGS[@]}") || true)
[ -n "$EXC" ] && printf '%s\n' "$EXC" | sed 's/^/  /' || say "  (없음)"
[ $MISSING = 0 ] || fail "없는 이미지가 있다 — 이름 확인"
if [ "$CMD" = plan ] || [ $APPLY = 0 ]; then say; say "(계획만 — 보내기: $0 send --apply)"; return 0; fi

guard_direction
NAME=images-$(date +%Y%m%d-%H%M%S); remote "mkdir -p $STAGE" || fail "신 서버 $STAGE 생성 실패"
say; say "== 전송: docker save | zstd | ssh → 신 서버 ~$RUSER/$STAGE/$NAME.tar.zst"
docker save "${TAGS[@]}" | zstd -T0 -3 -q | tee >(sha256sum | cut -d' ' -f1 > "$SHAF") | remote "cat > $STAGE/$NAME.tar.zst"
rc=("${PIPESTATUS[@]}"); [ "${rc[0]}" = 0 ] && [ "${rc[1]}" = 0 ] && [ "${rc[3]}" = 0 ] || fail "전송 실패(save=${rc[0]} zstd=${rc[1]} 원격=${rc[3]})"
for _ in $(seq 1 40); do [ -s "$SHAF" ] && break; sleep 0.5; done; L=$(cat "$SHAF"); [ -n "$L" ] || fail "로컬 해시를 얻지 못했다"
R=$(remote "sha256sum $STAGE/$NAME.tar.zst" | cut -d' ' -f1); [ "$L" = "$R" ] || fail "해시 불일치(로컬 ${L:0:12} / 원격 ${R:0:12}) — 받은 파일을 쓰지 말 것"
remote "cat > $STAGE/$NAME.manifest.tsv" < "$MF"; echo "$L  $NAME.tar.zst" | remote "cat > $STAGE/$NAME.sha256"
say "OK: 해시 일치(${L:0:12}). 신 서버에서: bash mig-images.sh load ~$RUSER/$STAGE/$NAME.tar.zst --apply"
}
run "$@"; exit $?
