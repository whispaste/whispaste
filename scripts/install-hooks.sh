#!/bin/bash
# Install WhisPaste git hooks from scripts/git-hooks/ into .git/hooks/
# Run once after cloning: bash scripts/install-hooks.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="$REPO_ROOT/scripts/git-hooks"
HOOKS_DEST="$REPO_ROOT/.git/hooks"

for hook in "$HOOKS_SRC"/*; do
  name="$(basename "$hook")"
  dest="$HOOKS_DEST/$name"
  cp "$hook" "$dest"
  chmod +x "$dest"
  echo "  ✓ Installed: .git/hooks/$name"
done

echo ""
echo "Git hooks installed. Pre-commit will now check:"
echo "  • Protected/internal files not staged"
echo "  • .gitignore PROTECTED section not weakened"
echo "  • No secrets in staged files"
echo "  • flutter analyze (when .dart or pubspec.yaml staged)"
echo "  • Website build (when website/ files staged)"
