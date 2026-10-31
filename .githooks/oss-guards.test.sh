#!/usr/bin/env bash
# oss-guards.test.sh — tests for oss-public.sh and the staged scope of
# name-guard.sh and instruction-guard.sh, in a throw-away git repo:
#   1. oss-public.sh keeps exact and prefix entries, drops the rest
#   2. without .ossallowlist every path counts as public (fail closed)
#   3. instruction-guard: internal CLAUDE.md passes with a note,
#      lib/CLAUDE.md blocks
#   4. name-guard staged: an internal line passes with a note, a public
#      line blocks
#   5. name-guard tree (CI): public file blocks, internal file passes
#   6. name-guard file: a name in a commit message blocks
#   7. guards run from a directory outside the repo (core.hooksPath of
#      another checkout) still find oss-public.sh
# Run: bash .githooks/oss-guards.test.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oss-guards.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
ok() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1"
  failures=$((failures + 1))
}
expect_rc() { # <want> <label> <cmd...>
  local want="$1" label="$2" rc=0
  shift 2
  "$@" >"$WORK/out" 2>&1 || rc=$?
  if [ "$rc" = "$want" ]; then ok "$label"; else fail "$label (rc=$rc)" && sed 's/^/       /' "$WORK/out"; fi
}

# A product name the guard knows, kept encoded so this file stays clean.
NAME="$(printf 'V2lzcHIgRmxvdw==' | base64 --decode 2>/dev/null || printf 'V2lzcHIgRmxvdw==' | base64 -D)"

REPO="$WORK/repo"
mkdir -p "$REPO/.githooks" "$REPO/lib" "$REPO/notes"
cp "$HOOKS/oss-public.sh" "$HOOKS/name-guard.sh" "$HOOKS/instruction-guard.sh" "$REPO/.githooks/"
cd "$REPO" || exit 1
git init -q
gc() { git -c user.name=test -c user.email=test commit -q --no-verify "$@"; }
printf '%s\n' '# public paths' 'lib/' 'README.md' '.githooks/' > .ossallowlist
echo clean > README.md
echo clean > lib/a.dart
gc --allow-empty -m init
git add -A && gc -m base

# 1 + 2
got="$(printf '%s\n' lib/a.dart lib README.md README.md.bak notes/x.md | .githooks/oss-public.sh | tr '\n' ' ')"
if [ "$got" = "lib/a.dart README.md " ]; then ok "oss-public keeps only allowlisted paths"; else fail "oss-public: got '$got'"; fi
mv .ossallowlist "$WORK/allow"
got="$(printf '%s\n' notes/x.md | .githooks/oss-public.sh)"
if [ "$got" = "notes/x.md" ]; then ok "no allowlist: every path is public"; else fail "no allowlist: got '$got'"; fi
mv "$WORK/allow" .ossallowlist

# 3
echo internal > CLAUDE.md
git add CLAUDE.md
expect_rc 0 "instruction-guard: internal CLAUDE.md passes" .githooks/instruction-guard.sh staged
if grep -q "note" "$WORK/out"; then ok "instruction-guard: internal CLAUDE.md gets a note"; else fail "instruction-guard: no note"; fi
gc -m "internal instructions"
echo internal > lib/CLAUDE.md
git add lib/CLAUDE.md
expect_rc 1 "instruction-guard: lib/CLAUDE.md blocks" .githooks/instruction-guard.sh staged
git rm -q --cached lib/CLAUDE.md && rm lib/CLAUDE.md

# 4
echo "compare with $NAME" > notes/research.md
git add notes/research.md
expect_rc 0 "name-guard staged: internal staged line passes" .githooks/name-guard.sh staged
if grep -q "note" "$WORK/out"; then ok "name-guard staged: internal hit gets a note"; else fail "name-guard staged: no note"; fi
gc -m "research note"
echo "// like $NAME" >> lib/a.dart
git add lib/a.dart
expect_rc 1 "name-guard staged: public staged line blocks" .githooks/name-guard.sh staged

# 5
gc -m "public change"
expect_rc 1 "name-guard tree: name in a public file blocks" .githooks/name-guard.sh tree HEAD
git -c user.name=test -c user.email=test revert --no-edit HEAD >/dev/null
expect_rc 0 "name-guard tree: name in an internal file passes" .githooks/name-guard.sh tree HEAD

# 6
printf 'inspired by %s\n' "$NAME" > "$WORK/msg"
expect_rc 1 "name-guard file: name in a commit message blocks" .githooks/name-guard.sh file "$WORK/msg"

# 7
mkdir -p "$WORK/hooks"
cp .githooks/oss-public.sh .githooks/name-guard.sh .githooks/instruction-guard.sh "$WORK/hooks/"
mv .githooks "$WORK/repo-hooks"
echo "// $NAME" >> lib/a.dart
git add lib/a.dart
expect_rc 1 "guards outside the repo find their helpers (name-guard)" "$WORK/hooks/name-guard.sh" staged
git restore --staged lib/a.dart && git checkout -q -- lib/a.dart
expect_rc 0 "guards outside the repo find their helpers (instruction-guard)" "$WORK/hooks/instruction-guard.sh" staged
mv "$WORK/repo-hooks" .githooks

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
