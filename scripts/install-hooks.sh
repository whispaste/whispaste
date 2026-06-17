#!/bin/bash
# Install WhisPaste git hooks from scripts/git-hooks/ into .git/hooks/
# Run once after cloning: bash scripts/install-hooks.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="$REPO_ROOT/scripts/git-hooks"
HOOKS_DEST="$REPO_ROOT/.git/hooks"

# Clean up orphan lefthook wrappers (left behind by previous tooling).
# Identified by the call_lefthook marker — never delete unrelated hooks.
for orphan in pre-push prepare-commit-msg pre-commit commit-msg post-commit post-merge; do
  dest="$HOOKS_DEST/$orphan"
  if [ -f "$dest" ] && grep -q "call_lefthook" "$dest"; then
    rm "$dest"
    echo "  ✓ Removed orphan: .git/hooks/$orphan (lefthook wrapper)"
  fi
done

for hook in "$HOOKS_SRC"/*; do
  name="$(basename "$hook")"
  dest="$HOOKS_DEST/$name"
  cp "$hook" "$dest"
  chmod +x "$dest"
  echo "  ✓ Installed: .git/hooks/$name"
done

echo ""
echo "Git hooks installed."
echo ""
echo "Pre-commit will check:"
echo "  • Current branch is NOT 'main' / 'master' (bypass: WP_ALLOW_COMMIT_ON_MAIN=1)"
echo "  • Protected/internal files not staged"
echo "  • .gitignore PROTECTED section not weakened"
echo "  • No secrets in staged files"
echo "  • flutter analyze (when .dart or pubspec.yaml staged)"
echo "  • Loam ratchet gate (when .dart or pubspec.yaml staged)"
echo "  • ESLint JS/TS (when website/src/*.ts|*.js staged)"
echo "  • cppcheck C++ (when windows/runner/*.cpp|*.h staged)"
echo "  • Website build + Playwright CI tests (when website/ files staged)"
echo ""
echo "Commit-msg will enforce (solo-project contributor hygiene):"
echo "  • Strip all Co-authored-by / AI-marker trailers (Claude, Copilot, …)"
echo "  • Block bot author/committer identities (only Silvio may commit)"
echo ""
echo "Post-checkout will warn when switching to 'main' / 'master'."
echo ""
echo "Pre-push will check (per commit in push range):"
echo "  • No force-push to main (override: WP_ALLOW_FORCE_MAIN=1)"
echo "  • No protected paths in any pushed commit"
echo "  • .gitignore PROTECTED section not weakened in history"
echo "  • No secret patterns in any pushed commit"
echo "  • No bot author/committer or AI co-author trailer in any pushed commit"
echo "  • Loam ratchet gate"
echo "  • Website build + Playwright CI tests"
echo "  • Semgrep SAST (JS/TS/C++/Go — community CI rule pack)"
echo "  • OSV vulnerability scan (pubspec.lock + website/package-lock.json)"
echo ""
echo "Required tools (install once):"
echo "  brew install cppcheck semgrep osv-scanner"
echo "  cd website && npm install"
