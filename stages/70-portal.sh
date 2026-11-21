#!/usr/bin/env bash
# 포털: 정적 페이지를 공개 경로에 둔다.
set -euo pipefail
R=$RENDERED/portal; P=/srv/$PFX/public
echo "== 포털 배치"
install -d "$P/portal/guide" "$P/skills" "$P/tools" "$P/assets"
install -m 0644 "$R/portal.html" "$P/portal/index.html"
install -m 0644 "$R/guide.html" "$P/portal/guide/index.html"
install -m 0644 "$R/skills.html" "$P/skills/index.html"
install -m 0644 "$R/tools.html" "$P/tools/index.html"
for f in "$R"/static/*; do install -m 0644 "$f" "$P/portal/$(basename "$f")"; done
[ -e "$P/skills/index.json" ] || printf '{"schema_version":1,"generated_at":"%s","core_skills":[],"skills":[]}\n' "$(date -u +%FT%TZ)" > "$P/skills/index.json"
[ -e "$P/tools/index.json" ] || echo '{"schema_version":1,"tools":[]}' > "$P/tools/index.json"
chmod -R a+rX "$P"
echo "성공: 포털 페이지 배치($P)"
echo "결과: 통과"
