#!/usr/bin/env bash
# Stage one composition in one theme as a standalone HyperFrames project so the
# CLI can lint, check, snapshot and render it. Source of truth stays in
# compositions/; the theme CSS comes from themes/ (built from the tokens).
#   usage: scripts/stage.sh <composition-id> <theme>   e.g. m1-welcome marine
# GEOMETRY=1 also injects scripts/geometry-check.js (stage dir gets a -geo suffix),
# so `hyperframes validate` fails on any containment, centring or ring violation.
# Writes .stage/<id>-<theme>/index.html (gsap path rewritten to the local package).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
id="${1:?composition id, e.g. m1-welcome}"
theme="${2:?theme: hell, dunkel or marine}"
src="$here/compositions/$id.html"
css="$here/themes/$theme.css"
suffix=""
[ "${GEOMETRY:-0}" = "1" ] && suffix="-geo"
dst="$here/.stage/$id-$theme$suffix"
geo="$here/scripts/geometry-check.js"
[ -f "$src" ] || { echo "no such composition: $src" >&2; exit 1; }
[ -f "$css" ] || { echo "no such theme: $css (run scripts/build-themes.mjs)" >&2; exit 1; }
mkdir -p "$dst"
python3 - "$src" "$css" "$dst/index.html" "${GEOMETRY:-0}" "$geo" <<'PY'
import sys
src, css, out, geometry, geo = sys.argv[1:6]
html = open(src).read().replace("../node_modules/", "node_modules/")
assert html.count("/*WP_THEME*/") == 1, "composition must carry one /*WP_THEME*/ marker"
html = html.replace("/*WP_THEME*/", open(css).read().strip())
if geometry == "1":
    html = html.replace("</body>", "<script>\n" + open(geo).read() + "\n</script>\n</body>")
open(out, "w").write(html)
PY
[ -e "$dst/node_modules" ] || ln -s "$here/node_modules" "$dst/node_modules"
echo "$dst"
