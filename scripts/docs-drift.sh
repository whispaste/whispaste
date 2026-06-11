#!/usr/bin/env bash
# docs-drift.sh — WEICHE Semantik-Drift-Prüfung für WhisPastes öffentliche Docs.
# Gegenstück zum deterministischen scripts/docs-attest.sh.
#
# docs-attest.sh ist der HARTE Gate (Struktur, version-sync, Plattform/Store-SSoT,
# Anti-Vokabular) — deterministisch, 0 Token, läuft in Hooks + CI + Flutter-Test.
# Es ist blind für SEMANTISCHE Veralterung: Prosa/Beispiele, die altes Verhalten
# beschreiben, ausgelieferte Features unterschlagen oder auf einer alten Version
# einfrieren.
#
# Dieses Skript stellt die IMPLEMENTIERUNGS-Ground-Truth (aus Code/Daten abgeleitet)
# plus die öffentlich sichtbaren Docs zusammen und lässt ein LLM genau diese Drift
# flaggen. ADVISORY und NICHT-BLOCKIEREND — niemals in einen Git-Hook verdrahten
# (ein LLM ist nicht-deterministisch und kostet Token). Vor einem Release laufen
# lassen oder nach nennenswerter Feature-Arbeit.
#
#   docs-drift.sh            Ground-Truth + Doc-Bündel + fertiger Review-Prompt
#   docs-drift.sh --print    (lesen, an ein LLM pipen oder einem Agenten geben).
#   docs-drift.sh --llm      Über die `claude`-CLI — nutzt die eingeloggte
#                            Subscription-Session (lokal) bzw. den
#                            CLAUDE_CODE_OAUTH_TOKEN (CI). KEIN Pay-per-Token-API.
#
# Auth-Modell (bewusst, Free-Tier-/Subscription-Disziplin):
#   - Lokal: die eingeloggte `claude`-CLI-Session (OAuth/Subscription).
#   - CI: dieselbe CLI + CLAUDE_CODE_OAUTH_TOKEN-Secret (`claude setup-token`).
#   Es gibt KEINEN ANTHROPIC_API_KEY-/curl-Pfad mehr — kein API-Billing.
#
# Free-Tier-safe: begrenzt, billiges Modell (Haiku), zur Release-Zeit — nicht pro Push.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"
PLATFORMS="$ROOT/website/src/data/platforms.ts"
GLOSSARY="$ROOT/website/src/data/brand-glossary.ts"
MODEL="${WHISPASTE_DRIFT_MODEL:-claude-haiku-4-5-20251001}"  # billig per Default

# --- 1. Ground truth (deterministisch, 0 Token) -----------------------------
version="$(sed -nE 's/^version:[[:space:]]*([0-9][^[:space:]]*).*/\1/p' "$PUBSPEC" | head -1)"

# Plattform/Store-Fakten aus der SSoT (platforms.ts) ableiten.
platform_facts="$(perl -0777 -ne '
  print "  - MS Store Product ID: $1\n" if /MS_STORE_PRODUCT_ID = .([0-9a-z]+)./;
  print "  - macOS arch label: $1\n"    if /archLabel: \x27([^\x27]+)\x27/;
  while (/(\w+):\s*\{[^}]*?hasStoreListing:\s*(true|false)/sg) { print "  - $1 hasStoreListing: $2\n" }
' "$PLATFORMS" 2>/dev/null || true)"

# Kanonische Brand-Sprache (was Docs verwenden SOLLEN).
canon="$(perl -0777 -ne '
  print "  - product category: $1 (DE) / $2 (EN)\n" if /productCategoryDE = "([^"]+)".*?productCategoryEN = "([^"]+)"/s;
  print "  - action: $1 (DE) / $2 (EN)\n"           if /actionDE = "([^"]+)".*?actionEN = "([^"]+)"/s;
  print "  - output artifact: $1 (DE) / $2 (EN)\n"  if /outputArtifactDE = "([^"]+)".*?outputArtifactEN = "([^"]+)"/s;
' "$GLOSSARY" 2>/dev/null || true)"

# Öffentliche Docs, deren PROSA der Implementierung folgen muss.
INLINE_DOCS=(
  "README.md"
  "CHANGELOG.md"
)
LISTED_DOCS=(
  "website/src/pages/index.astro · website/src/pages/en/index.astro (Hero/Feature-Liste)"
  "website/src/pages/download.astro · website/src/pages/en/download.astro (Plattform-/Store-CTAs)"
  "website/src/pages/whisper-desktop.astro · …/offline-speech-to-text.astro (Feature-Beschreibungen)"
  "website/src/data/platforms.ts (Plattform/Store-SSoT)"
)

# --- 2. Review-Prompt + Bündel zusammenstellen -------------------------------
prompt="$(mktemp)"
{
  cat <<EOF
You are a documentation-drift auditor for WhisPaste (a cross-platform offline
voice-input desktop app — Windows/macOS/Linux). Below is the CURRENT
implementation ground truth (derived from code/data), then the public-facing docs.

Find prose, examples, or claims that CONTRADICT, UNDERSTATE, or OMIT what the
product actually ships now — the semantic staleness a structural linter cannot
see (e.g. a feature list still naming a removed STT provider, a version label
frozen at an old release, an App Store claim for macOS when only a GitHub DMG ships).

Rules of judgement:
- Anything a doc presents as live/available/now that contradicts the ground truth
  below is drift. Anything in the ground truth not reflected in user-facing docs is drift.
- WhisPaste has NO Mac App Store listing (macOS = GitHub arm64 DMG). Windows primary
  channel is the Microsoft Store. Linux has no binary artefact yet.
- Removed / never-shipped (must NOT appear as current features): Groq STT,
  Anthropic STT, Gemini STT, Smart Mode, command palette. Current cloud STT
  providers: OpenAI + Deepgram; plus on-device (Whisper).
- Use the canonical brand language below; flag off-vocabulary product framing
  (e.g. calling WhisPaste a "dictation tool" / "voice assistant").
- Version numbers must be consistent everywhere they appear.

Report per file:
  [SEVERITY] <relative/path> ~line — <stale claim vs reality> -> <concrete fix>
SEVERITY in {BLOCKER (contradicts shipped reality / misleads), SHOULD-FIX
(omits/understates shipped features), NIT (wording / stale version label)}.
List clean files in one line. End with a prioritized fix order. Be specific —
quote the exact stale wording and cite line numbers.

## Implementation ground truth (source of truth)
- Version being released: $version
- Platform/store facts (website/src/data/platforms.ts):
$platform_facts
- Canonical brand language (website/src/data/brand-glossary.ts):
$canon

## Also review (an agent with repo access should open these too)
EOF
  for d in "${LISTED_DOCS[@]}"; do echo "- $d"; done
  echo ""
  echo "## Inlined public docs"
  for d in "${INLINE_DOCS[@]}"; do
    [ -f "$ROOT/$d" ] || continue
    echo ""
    echo "===== FILE: $d ====="
    # CHANGELOG kann lang sein -> auf die obersten ~120 Zeilen begrenzen (neueste Releases).
    if [ "$d" = "CHANGELOG.md" ]; then head -120 "$ROOT/$d"; else cat "$ROOT/$d"; fi
  done
} > "$prompt"

case "${1:-}" in
  --llm)
    # `claude` nutzt automatisch die eingeloggte Subscription-Session bzw. den
    # CLAUDE_CODE_OAUTH_TOKEN aus der Umgebung. Kein API-Key, kein Pay-per-Token.
    if command -v claude >/dev/null 2>&1; then
      echo "→ docs-drift: Soft-Check via claude ($MODEL, Subscription) …" >&2
      claude -p "$(cat "$prompt")" --model "$MODEL"
    else
      echo "✗ docs-drift: 'claude'-CLI nicht gefunden — gebe das Bündel aus." >&2
      echo "  (Install: npm i -g @anthropic-ai/claude-code; Auth: claude setup-token)" >&2
      cat "$prompt"
    fi
    ;;
  ""|--print)
    cat "$prompt"
    ;;
  *)
    echo "usage: docs-drift.sh [--print | --llm]" >&2
    rm -f "$prompt"; exit 2
    ;;
esac
rm -f "$prompt"
