#!/usr/bin/env bash
# Golden 빌드 재료를 업스트림에서 받는다(저장소에는 서드파티 재료를 넣지 않는다). 버전·커밋·sha256 은 여기에 고정되어 있다.
#   사용: fetch-upstream.sh          (이 파일이 있는 디렉터리 = Golden 빌드 컨텍스트에 upstream/ · plugins/ · skills/ponytail 을 만든다)
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
say(){ echo "안내: $*"; }
ok(){ echo "성공: $*"; }
die(){ echo "실패: $*" >&2; exit 1; }
dl(){ # <URL> <파일> [sha256]
  curl -fsSL --retry 3 --retry-delay 3 -o "$2" "$1" || die "내려받기 실패: $1"
  [ -z "${3:-}" ] || echo "$3  $2" | sha256sum -c - >/dev/null || die "sha256 불일치: $2 (업스트림이 바뀌었거나 전송 오류)"; }
rec(){ # <디렉터리> <이름> <저장소> <참조> <커밋> <라이선스> [추가 줄...]
  local d=$1; shift; mkdir -p "$d"; { printf 'name=%s\nupstream=%s\nref=%s\ncommit=%s\nlicense=%s\n' "$1" "$2" "$3" "$4" "$5"; shift 5; for l in "$@"; do echo "$l"; done; } > "$d/@@PFX_UP@@-UPSTREAM.txt"; }
gh_tar(){ # <소유자/저장소> <커밋> <파일>  — GitHub 커밋 압축본
  dl "https://codeload.github.com/$1/tar.gz/$2" "$3"; }

mkdir -p upstream skills plugins/superpowers

say "ponytail (MIT)"
PT=7801d061243d7b753bad0e0b3c057cd250b11755
mkdir -p skills/ponytail
dl "https://raw.githubusercontent.com/DietrichGebert/ponytail/$PT/skills/ponytail/SKILL.md" skills/ponytail/SKILL.md 9badd22a32e19cb884e46dfa8d3aae82bb81dfa5484105b8b4f0262df823a509
rec upstream/ponytail ponytail https://github.com/DietrichGebert/ponytail v5.3.3 $PT MIT version=5.3.3 "tag=v5.3.3"
ok "ponytail"

say "archify (MIT)"
mkdir -p upstream/archify
dl https://github.com/tt-a1i/archify/releases/download/v3.2.0/archify.zip upstream/archify/archify-v3.2.0.zip 70e210265c59f24dcbdf2a502ff671104b5454e7ee7d3554aecd86bad32384f5
rec upstream/archify archify https://github.com/tt-a1i/archify v3.2.0 208acba8d412335185b2056fedf54b3405df43fb MIT
ok "archify"

say "effective-html (MIT) — 여덟 스킬(one-pager 포함)"
EH=5ce160a3e76dc1c0f9301f8a1903704ec607636a
gh_tar plannotator/effective-html $EH "$T/eh.tgz"
mkdir -p "$T/eh" upstream/effective-html
tar -xzf "$T/eh.tgz" -C "$T/eh" --strip-components=1
tar -czf upstream/effective-html/effective-html-$EH.tar.gz -C "$T/eh" skills
rec upstream/effective-html effective-html https://github.com/plannotator/effective-html HEAD $EH MIT
ok "effective-html"

say "ui-ux-pro-max (MIT) — 일곱 스킬"
UX=e59ff376a41f7ca47b7541ad5c116495cbade3ee
gh_tar nextlevelbuilder/ui-ux-pro-max-skill $UX "$T/ux.tgz"
mkdir -p "$T/ux" upstream/ui-ux-pro-max
tar -xzf "$T/ux.tgz" -C "$T/ux" --strip-components=1
tar -czf upstream/ui-ux-pro-max/ui-ux-pro-max-$UX.tar.gz -C "$T/ux" .claude/skills
rec upstream/ui-ux-pro-max ui-ux-pro-max https://github.com/nextlevelbuilder/ui-ux-pro-max-skill main $UX MIT
ok "ui-ux-pro-max"

say "agent-browser (Apache-2.0)"
AB=1cc19526f3641c8543d55aa6700e7c55b37ac356
mkdir -p upstream/agent-browser/skill
dl https://github.com/vercel-labs/agent-browser/releases/download/v0.43.0/agent-browser-linux-x64 upstream/agent-browser/agent-browser-linux-x64-v0.43.0 8e69c9fb662514c9cf36e4911e94e913742ba066e55102486350e049dd847612
gh_tar vercel-labs/agent-browser $AB "$T/ab.tgz"
mkdir -p "$T/ab"; tar -xzf "$T/ab.tgz" -C "$T/ab" --strip-components=1
tar -czf upstream/agent-browser/agent-browser-skill-data-0.43.0.tar.gz -C "$T/ab" skill-data
cp "$T/ab/skills/agent-browser/SKILL.md" upstream/agent-browser/skill/SKILL.md
rec upstream/agent-browser agent-browser https://github.com/vercel-labs/agent-browser v0.43.0 $AB Apache-2.0
ok "agent-browser"

say "superpowers 플러그인 v7.0.2 (MIT)"
SP=22f0b463e7a5e579904dd6211a520321035526f7
rm -rf plugins/superpowers/v7.0.2
git clone -q --depth 1 --branch v7.0.2 https://github.com/obra/superpowers plugins/superpowers/v7.0.2
[ "$(git -C plugins/superpowers/v7.0.2 rev-parse HEAD)" = "$SP" ] || die "superpowers 커밋 불일치"
git -C plugins/superpowers/v7.0.2 remote remove origin
rec plugins/superpowers superpowers https://github.com/obra/superpowers v7.0.2 $SP MIT
ok "superpowers"
echo "결과: 통과"
