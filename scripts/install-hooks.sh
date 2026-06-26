#!/bin/bash
# WhisPaste — Hook-Aktivierung (einmal pro Clone)
#
# Die Hooks selbst liegen versioniert in .githooks/. Dieser Skin setzt nur
# core.hooksPath — die Hooks laufen dann direkt von dort, kein Kopieren nötig.
# Bash scripts/install-hooks.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Clean up orphan lefthook wrappers (left behind by previous tooling).
for orphan in pre-push prepare-commit-msg pre-commit commit-msg post-commit post-merge; do
  dest="$ROOT/.git/hooks/$orphan"
  if [ -f "$dest" ] && grep -q "call_lefthook" "$dest"; then
    rm "$dest"
    echo "  ✓ Removed orphan: .git/hooks/$orphan (lefthook wrapper)"
  fi
done

git config core.hooksPath .githooks
echo "WhisPaste hooks activated: core.hooksPath = $(git config core.hooksPath)"

# Remove ANY leftover pre-v2 hooks from .git/hooks/ that might shadow the
# .githooks/ ones (pre-WhisPaste-2.0 setups used .git/hooks/ directly).
for hook in pre-commit pre-push commit-msg post-checkout; do
  dest="$ROOT/.git/hooks/$hook"
  if [ -f "$dest" ]; then
    rm "$dest"
    echo "  ✓ Removed legacy .git/hooks/$hook"
  fi
done

echo ""
echo "Pre-commit checks:"
echo "  • Branch protection (no commits on main, bypass: WP_ALLOW_COMMIT_ON_MAIN=1)"
echo "  • AI-identity-guard (no bot author/committer)"
echo "  • Allowlist gate (.ossallowlist — only explicitly-listed paths are public)"
echo "  • .gitignore PROTECTED section cannot be weakened"
echo "  • Secret patterns (Supabase keys, OpenAI keys, GitHub tokens)"
echo "  • Flutter analyze + Loam ratchet gate (when .dart/pubspec.yaml staged)"
echo "  • ESLint (when website/src/ JS/TS staged)"
echo "  • cppcheck (when windows/runner/ C++ staged)"
echo "  • Website CI (when website/ staged)"
echo "  • Doc-Gate: content-level leak/identity/language checks"
echo ""
echo "Pre-push checks:"
echo "  • Allowlist gate (full HEAD tree scan — catches 'git commit --no-verify')"
echo "  • Force-push to main blocked (override: WP_ALLOW_FORCE_MAIN=1)"
echo "  • .gitignore PROTECTED section cannot be weakened in history"
echo "  • Secret patterns in push range"
echo "  • AI-Coauth-By-Trailer + bot author/committer in push range"
echo "  • Docs-attest gate (public docs must be attested for push)"
echo "  • Doc-Gate: content-level checks on entire HEAD tree"
echo "  • Loam ratchet gate"
echo "  • Semgrep SAST (JS/TS/C++)"
echo "  • OSV vulnerability scan (pubspec.lock + website/package-lock.json)"
echo "  • Website CI"
echo "  • Advisory docs-drift (non-blocking, release pushes only)"
echo ""
echo "Required tools (install once):"
echo "  brew install cppcheck semgrep osv-scanner"
echo "  cd website && npm install"
