#!/usr/bin/env bash
#
# WhisPaste — Doc-Gate (Schutzschicht für öffentliche Inhalte)
#
# Deterministische, rein lokale Prüfung (kein LLM, kein Netz → Free-Tier-konform).
# Läuft in pre-commit (MODE=staged) und pre-push (MODE=head). Erzwingt die
# mechanischen Invarianten für ALLES, was ins öffentliche Repo gelangt:
#
#   1. Keine Infra-/Secret-Leaks — generische Marker (private IPs ausser in Tests,
#      lokale Pfade, Private-Key-/Access-Key-Muster) PLUS eine projektspezifische,
#      NICHT eingecheckte Blockliste (.githooks/leak-blocklist.local, gitignored).
#   2. Öffentliche GitHub-Markdown (README/SECURITY/CHANGELOG) ist Englisch.
#   3. Keine Security-Werbung (Guardrail), keine falsche Identität, keine Platzhalter.
#   4. Pflichtdateien vorhanden + nicht leer; die lokale Blockliste bleibt ungetrackt.
#
# Bash-3.2-kompatibel (macOS /bin/bash) — kein mapfile/readarray.
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
MODE="${1:-staged}"

fail=0
err(){ echo "  ✗ $1" >&2; fail=1; }

# --- Generische Infra-/Secret-Marker (provider-agnostisch) ---
HARD_RE='/Users/[A-Za-z]|/home/[a-z][a-z0-9_-]*/|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'
IP_RE='192\.168\.[0-9]|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]'
# Generic secret patterns (keys, tokens, passwords in code)
KEY_RE='(API_KEY|SECRET_KEY|SERVICE_ROLE_KEY|ACCESS_KEY)\s*[:=]\s*["\x27][A-Za-z0-9_-]{16,}'

# --- Projektspezifische Blockliste (NICHT eingecheckt, gitignored) ---
LOCAL_BLOCK="$ROOT/.githooks/leak-blocklist.local"
LOCAL_RE=""
if [ -f "$LOCAL_BLOCK" ]; then
  LOCAL_RE="$(grep -vE '^[[:space:]]*(#|$)' "$LOCAL_BLOCK" | paste -sd '|' - || true)"
fi

# --- Englisch-Pflicht-Dateien (öffentliche GitHub-Markdown) ---
ENGLISH_FILES="README.md SECURITY.md CHANGELOG.md CONTRIBUTING.md CODE_OF_CONDUCT.md"
GERMAN_RE='(^|[^[:alpha:]])(und|oder|nicht|werden|wurde|eine|einen|keine|sind|auch|dass|wird|diese|sich|wenn|gehört|über|für)([^[:alpha:]]|$)'

list_files(){
  if [ "$MODE" = "staged" ]; then
    git diff --cached --name-only --diff-filter=ACM
  else
    git ls-tree -r --name-only HEAD
  fi
}
read_file(){ if [ "$MODE" = "staged" ]; then git show ":$1" 2>/dev/null; else git show "HEAD:$1" 2>/dev/null; fi; }
exists(){
  if [ "$MODE" = "staged" ]; then git ls-files --cached --error-unmatch "$1" >/dev/null 2>&1
  else git cat-file -e "HEAD:$1" 2>/dev/null; fi
}
is_test(){ case "$1" in test/*|*/test/*|*/__tests__/*|integration_test/*) return 0 ;; esac; return 1; }
skip_file(){
  case "$1" in
    .githooks/*) return 0 ;;
    *node_modules/*|*/dist/*|*/.astro/*|.dart_tool/*|build/*|coverage/*) return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.svg|*.webp|*.woff|*.woff2|*.ttf|*.eot|*.pdf) return 0 ;;
    *.exe|*.dll|*.so|*.dylib|*.bin|*.p12|*.keychain*) return 0 ;;
    pubspec.lock|package-lock.json|Gemfile) return 0 ;;
    # store/ + website/src/pages/de/ = deutsche Marketing-Inhalte (per Locale — kein English-Gate)
    store/de-DE/*) return 0 ;;
    website/src/pages/de/*) return 0 ;;
    website/src/pages/*.astro) return 0 ;;
  esac
  return 1
}

# 0) Die lokale Blockliste darf NIE getrackt/committet werden.
if exists ".githooks/leak-blocklist.local"; then
  err ".githooks/leak-blocklist.local ist getrackt — muss lokal/gitignored bleiben"
fi

# 1) Infra-/Secret-Leak-Scan über alle (scannbaren) Dateien
while IFS= read -r f; do
  [ -z "$f" ] && continue
  skip_file "$f" && continue
  content="$(read_file "$f")"
  [ -z "$content" ] && continue

  if printf '%s' "$content" | LC_ALL=C grep -qE "$HARD_RE"; then
    hit="$(printf '%s' "$content" | LC_ALL=C grep -nE "$HARD_RE" | head -1 | sed 's/^[[:space:]]*//; s/  */ /g' | cut -c1-100)"
    err "$f: Infra-/Secret-Leak → $hit"
  fi
  if printf '%s' "$content" | LC_ALL=C grep -qE "$KEY_RE"; then
    hit="$(printf '%s' "$content" | LC_ALL=C grep -nE "$KEY_RE" | head -1 | sed 's/^[[:space:]]*//; s/  */ /g' | cut -c1-100)"
    err "$f: Secret/Key-Pattern → $hit"
  fi
  if [ -n "$LOCAL_RE" ] && printf '%s' "$content" | LC_ALL=C grep -qiE "$LOCAL_RE"; then
    hit="$(printf '%s' "$content" | LC_ALL=C grep -niE "$LOCAL_RE" | head -1 | sed 's/^[[:space:]]*//; s/  */ /g' | cut -c1-100)"
    err "$f: Blocklisten-Treffer (Internas) → $hit"
  fi
  if ! is_test "$f"; then
    if printf '%s' "$content" | LC_ALL=C grep -qE "$IP_RE"; then
      hit="$(printf '%s' "$content" | LC_ALL=C grep -nE "$IP_RE" | head -1 | sed 's/^[[:space:]]*//; s/  */ /g' | cut -c1-100)"
      err "$f: private IP (Infra-Leak) → $hit"
    fi
  fi
done < <(list_files)

# 2) Pflichtdateien vorhanden + nicht leer
for f in README.md SECURITY.md LICENSE; do
  if ! exists "$f"; then err "Pflichtdatei fehlt: $f"; continue; fi
  if [ -z "$(read_file "$f" | tr -d '[:space:]')" ]; then err "Pflichtdatei leer: $f"; fi
done

# 3) Markdown-spezifisch: Englisch, keine Security-Werbung, Identität, Platzhalter
for f in $ENGLISH_FILES; do
  exists "$f" || continue
  c="$(read_file "$f")"
  [ -z "$c" ] && continue
  if printf '%s' "$c" | grep -qiE 'security[ -]by[ -]design|security-by-default|battle-tested|military-grade|bank-grade|hardened by design'; then
    err "$f: Security-Werbung (Guardrail: Security nicht bewerben)"
  fi
  if printf '%s' "$c" | grep -qE 'silvio-l/whispaste'; then
    err "$f: falsche Identität 'silvio-l/whispaste' (existiert nicht — erwartet silvio-l/WhisPaste oder whispaste)"
    # Note: the actual GitHub org+repo may differ; adjust to match reality
  fi
  if printf '%s' "$c" | grep -qE 'TODO|FIXME|XXX|PLACEHOLDER|LOREM IPSUM'; then
    err "$f: Platzhalter (TODO/FIXME/…) in öffentlicher Doku"
  fi
  if printf '%s' "$c" | grep -qE '<[^>]+@[^>]+>' 2>/dev/null; then
    err "$f: E-Mail-Adresse (Anzeigename <addr>) in öffentlicher Markdown"
  fi
  # German markers — public GH Markdown must be English
  if printf '%s' "$c" | LC_ALL=C grep -qE "$GERMAN_RE"; then
    err "$f: deutsche Sprachmarker — öffentliche GitHub-Markdown muss Englisch sein"
  fi
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<EOF

DOC-GATE BLOCKIERT — öffentliche Inhalte verletzen Invarianten (s.o.).
Internas/Infra-Details (Provider, Hosts, IPs, lokale Pfade) gehören NIE
ins öffentliche Repo; GitHub-Markdown bleibt Englisch und ohne Security-Werbung.
EOF
  exit 1
fi
exit 0
