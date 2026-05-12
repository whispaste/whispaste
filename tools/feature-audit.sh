#!/usr/bin/env bash
# tools/feature-audit.sh — static feature-claim audit
#
# Verifies that every feature card in Features.astro and every claim in
# README's Key Features section maps to at least one file or directory
# in lib/. Exits 1 on any unmatched claim; exits 0 when all claims are
# satisfied. Run from the repository root:
#
#   bash tools/feature-audit.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/lib"
FAIL=0

check() {
  local label="$1"
  local pattern="$2"   # glob or path relative to lib/
  if find "$LIB" -path "$LIB/$pattern" -print -quit 2>/dev/null | grep -q .; then
    echo "  OK  $label"
  else
    echo "  FAIL  $label  (no match for lib/$pattern)"
    FAIL=1
  fi
}

echo "=== Feature audit ==="
echo ""
echo "-- Features.astro core cards --"
check "Global Hotkey"     "services/hotkey_service.dart"
check "Auto-Paste"        "services/desktop_paste*"
check "Voice Snippets"    "features/replacements*"
check "Privacy First"     "services/transcription*"

echo ""
echo "-- Features.astro power cards --"
check "Dashboard"         "features/history*"
check "Recording Overlay" "services/floating_overlay*"
check "Command Palette"   "widgets/command_palette.dart"
check "VAD & Export"      "features/history/data/export_service.dart"

echo ""
echo "-- README Key Features claims --"
check "Global hotkey"           "services/hotkey_service.dart"
check "Auto-paste"              "services/desktop_paste*"
check "Voice Activity Detection" "services/transcription*"
check "Recording overlay"       "services/floating_overlay*"
check "Floating record button"  "services/floating_button*"
check "Cloud STT (OpenAI)"      "services/transcription*"
check "Local Whisper STT"       "services/transcription*"
check "Voice Snippets"          "features/replacements*"
check "Command palette"         "widgets/command_palette.dart"
check "Full-text search"        "features/history*"
check "Analytics dashboard"     "features/analytics*"
check "Export"                  "features/history/data/export_service.dart"
check "Auto-update"             "services/update_service.dart"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All feature claims verified. Audit passed."
  exit 0
else
  echo "One or more feature claims could not be verified. Fix the claims or add the missing implementation."
  exit 1
fi
