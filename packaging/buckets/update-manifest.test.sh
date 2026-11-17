#!/usr/bin/env bash
# Runs the shell step of update-manifest.yml locally against a fake gh and a local bare repo
# that plays the bucket on GitHub: first run commits, rerun is a no-op, a draft or a tampered
# asset is refused, the tap gets the cask. Run: bash packaging/buckets/update-manifest.test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# The step's script, exactly as the workflow runs it.
python3 -I - "$HERE/update-manifest.yml" "$T/step.sh" <<'PY'
import re, sys, textwrap
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"\n        run: \|\n((?:          .*\n|\n)+)", text)
open(sys.argv[2], "w").write(textwrap.dedent(m.group(1)))
PY

# Published release v9.9.9 of whispaste/whispaste: assets, SHA256SUMS, templates at the tag.
mkdir -p "$T/rel" "$T/bin"
printf 'win' > "$T/rel/WhisPaste-9.9.9-windows-x64.zip"
printf 'mac' > "$T/rel/WhisPaste-9.9.9-macos-arm64.zip"
(cd "$T/rel" && { echo "# release v9.9.9 sha abc"; shasum -a 256 WhisPaste-*; } > SHA256SUMS)
echo "false false" > "$T/state"

cat > "$T/bin/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$T/gh.log"
case "\$1 \$2" in
  "release view")
    if [[ "\$3" == --repo ]]; then echo v9.9.9; else cat "$T/state"; fi ;;
  "release download")
    args="\$*"; dir="\${args##* -D }"
    cp "$T/rel/SHA256SUMS" "$T/rel/"WhisPaste-9.9.9-* "\$dir/" ;;
  "api repos/whispaste/whispaste/contents/packaging/scoop/whispaste.json?ref=v9.9.9") cat "$ROOT/packaging/scoop/whispaste.json" ;;
  "api repos/whispaste/whispaste/contents/packaging/homebrew/whispaste.rb?ref=v9.9.9") cat "$ROOT/packaging/homebrew/whispaste.rb" ;;
  "api repos/whispaste/whispaste/contents/packaging/buckets/render_manifest.py?ref=v9.9.9") cat "$HERE/render_manifest.py" ;;
  *) echo "unexpected gh call: \$*" >&2; exit 9 ;;
esac
GH
chmod +x "$T/bin/gh"

# A bucket repo: bare "GitHub" remote plus the checkout the workflow works in.
setup_repo() { # <name> <manifest path> <old content file>
  git init -q -b main "$T/$1-seed"
  mkdir -p "$T/$1-seed/.github/scripts" "$T/$1-seed/$(dirname "$2")"
  cp "$HERE/render_manifest.py" "$T/$1-seed/.github/scripts/"
  cp "$3" "$T/$1-seed/$2"
  git -C "$T/$1-seed" add .
  git -C "$T/$1-seed" commit -q -m seed
  git clone -q --bare "$T/$1-seed" "$T/$1.git"
  git clone -q "$T/$1.git" "$T/$1"
}
step() { # <repo dir> <repo name> [tag]
  (cd "$T/$1" && PATH="$T/bin:$PATH" GH_TOKEN=x TAG_INPUT="${3:-}" SRC=whispaste/whispaste \
    GITHUB_REPOSITORY="whispaste/$2" RUNNER_TEMP="$(mktemp -d "$T/runner.XXXX")" \
    GITHUB_STEP_SUMMARY="$T/summary" bash "$T/step.sh")
}

python3 -I "$HERE/render_manifest.py" render scoop --template "$ROOT/packaging/scoop/whispaste.json" \
  --version 9.9.8 --sha256 "$(printf '1%.0s' {1..64})" --out "$T/old.json" >/dev/null
setup_repo scoop-bucket bucket/whispaste.json "$T/old.json"

# 1. Latest release (empty tag): the bucket gets 9.9.9 with the hash of the real asset.
step scoop-bucket scoop-bucket >/dev/null
want="$(shasum -a 256 "$T/rel/WhisPaste-9.9.9-windows-x64.zip" | cut -d' ' -f1)"
git -C "$T/scoop-bucket.git" show main:bucket/whispaste.json > "$T/pushed.json"
[[ "$(python3 -I "$HERE/render_manifest.py" fields scoop "$T/pushed.json")" == "9.9.9 $want" ]] || fail "bucket not bumped"
[[ "$(git -C "$T/scoop-bucket.git" log -1 --format=%s main)" == "chore: bump whispaste to 9.9.9" ]] || fail "commit message"
grep -q 'whispaste.json bumped to 9.9.9' "$T/summary" || fail "no step summary"

# 2. Rerun with the explicit tag: no new commit.
before="$(git -C "$T/scoop-bucket.git" rev-parse main)"
out="$(step scoop-bucket scoop-bucket v9.9.9)"
grep -q 'already up to date' <<< "$out" || fail "rerun not reported as no-op: $out"
[[ "$(git -C "$T/scoop-bucket.git" rev-parse main)" == "$before" ]] || fail "rerun committed"

# 3. Not a stable tag, or a draft: refused, nothing pushed.
if step scoop-bucket scoop-bucket 'v9.9.9;rm' >/dev/null 2>&1; then fail "odd tag accepted"; fi
echo "true false" > "$T/state"
if step scoop-bucket scoop-bucket v9.9.9 >/dev/null 2>&1; then fail "draft accepted"; fi
echo "false false" > "$T/state"

# 4. Asset differs from SHA256SUMS: refused, the bucket keeps its state.
git -C "$T/scoop-bucket" reset -q --hard HEAD~1
git -C "$T/scoop-bucket" push -q -f origin HEAD:main
printf 'tampered' >> "$T/rel/WhisPaste-9.9.9-windows-x64.zip"
if step scoop-bucket scoop-bucket v9.9.9 >/dev/null 2>&1; then fail "tampered asset accepted"; fi
[[ "$(git -C "$T/scoop-bucket.git" log -1 --format=%s main)" == seed ]] || fail "tampered asset pushed"
printf 'win' > "$T/rel/WhisPaste-9.9.9-windows-x64.zip"

# 5. The tap: same file, the repo name picks the cask.
python3 -I "$HERE/render_manifest.py" render homebrew --template "$ROOT/packaging/homebrew/whispaste.rb" \
  --version 9.9.8 --sha256 "$(printf '2%.0s' {1..64})" --out "$T/old.rb" >/dev/null
setup_repo homebrew-tap Casks/whispaste.rb "$T/old.rb"
step homebrew-tap homebrew-tap v9.9.9 >/dev/null
want="$(shasum -a 256 "$T/rel/WhisPaste-9.9.9-macos-arm64.zip" | cut -d' ' -f1)"
git -C "$T/homebrew-tap.git" show main:Casks/whispaste.rb > "$T/pushed.rb"
[[ "$(python3 -I "$HERE/render_manifest.py" fields homebrew "$T/pushed.rb")" == "9.9.9 $want" ]] || fail "tap not bumped"

echo "update-manifest.test.sh: ok"
