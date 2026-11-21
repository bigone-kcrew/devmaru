#!/usr/bin/env bash
# 릴리스 tarball + sha256 만들기. 사용: ./release.sh [출력 디렉터리]
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; V=$(cat "$H/VERSION"); OUT="${1:-$H}"; N="devmaru-kit-$V"
mkdir -p "$OUT"; W=$(mktemp -d)/$N; mkdir -p "$W"
cp -a "$H"/{bin,lib,stages,config,docs,windows,tree,install.sh,VERSION,LICENSE,README.md,THIRD_PARTY.md,AGENTS.md,CLAUDE.md,CHANGELOG.md} "$W/"
tar -C "$(dirname "$W")" --owner=0 --group=0 -czf "$OUT/$N.tar.gz" "$N"; ( cd "$OUT" && sha256sum "$N.tar.gz" > "$N.tar.gz.sha256" )
ls -la "$OUT/$N.tar.gz"*
