#!/usr/bin/env bash
# Public-Docs-QS für WhisPaste — deterministisch, 0 Token. Hält die öffentlich
# sichtbaren Artefakte konsistent zum Repo-Stand und zu den maschinenlesbaren
# Single-Sources:
#   - README.md            (GitHub-Frontpage)
#   - CHANGELOG.md         (Versions-Quelle, auf der Website gerendert)
#   - website/            (Marketing-Site, DE + EN)
#   - website/src/data/platforms.ts      (SSoT Plattform/Store-Metadaten)
#   - website/src/data/brand-glossary.ts (SSoT Anti-Vokabular / kanonische Sprache)
#
#   docs-attest.sh check     Struktur- & Konsistenz-Invarianten (immer erfüllen).
#   docs-attest.sh attest    BEWUSSTE Bestätigung vor dem Push: alle Artefakte sind
#                            aufbaukonform UND inhaltlich aktuell -> stempelt HEAD
#                            nach .docs-attest.
#   docs-attest.sh attested  Gibt den zuletzt attestierten Commit aus (oder leer).
#
# Genutzt vom .githooks/pre-push (Schranke), der CI (qa) und dem Flutter-Test-Gate.
#
# Konzept inspiriert von loam.dev (tool/docs-attest.sh), aber vollständig auf
# WhisPastes Realität zugeschnitten: Desktop-App statt pub.dev-Paket, Stores/
# Plattformen statt CLI-Commands, DE-primär + EN-Mirror-i18n.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
CHANGELOG="$ROOT/CHANGELOG.md"
PUBSPEC="$ROOT/pubspec.yaml"
WEB="$ROOT/website"
WEBSRC="$WEB/src"
PLATFORMS="$WEBSRC/data/platforms.ts"
GLOSSARY="$WEBSRC/data/brand-glossary.ts"
SPEC="$ROOT/docs/public-docs-spec.md"   # interne QS-Spec, bewusst gitignored
ATTEST="$ROOT/.docs-attest"
PAGES="$WEBSRC/pages"

fail=0
note() { echo "  ✗ $1"; fail=1; }

# --- README -----------------------------------------------------------------
check_readme() {
  [ -f "$README" ] || { note "README.md fehlt"; return; }

  # (a) Pflicht-Marker aus der Spec (Single Source für den Aufbau). Spec ist
  #     gitignored -> in CI/Fresh-Clone abwesend -> Marker-Check überspringen.
  local markers=""
  [ -f "$SPEC" ] && markers="$(awk '/<!-- required:start -->/{f=1;next} /<!-- required:end -->/{f=0} f' "$SPEC" \
                            | sed '/^[[:space:]]*$/d')"
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    grep -qF -- "$m" "$README" || note "README fehlt Pflicht-Marker: $m"
  done <<< "$markers"

  # (b) Lokale relative Bild-/Link-Pfade existieren. GitHub-relative Web-Links
  #     (../../…), Anker (#…) und absolute URLs werden übersprungen.
  local refs; refs="$( { grep -oE 'src="[^"]+"' "$README" | sed -E 's/src="([^"]+)"/\1/';
                         grep -oE '\]\([^)]+\)' "$README" | sed -E 's/\]\(([^)]+)\)/\1/'; } \
                       | sort -u || true )"
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$r" in http://*|https://*|mailto:*|\#*|../*|/*) continue ;; esac
    r="${r%%#*}"; r="${r%%\?*}"; [ -z "$r" ] && continue
    # %20 -> Leerzeichen (README nutzt URL-kodierte Pfade).
    r="$(printf '%s' "$r" | sed 's/%20/ /g')"
    [ -e "$ROOT/$r" ] || note "README verweist auf fehlenden lokalen Pfad: $r"
  done <<< "$refs"

}

# Öffentliche Prosa-Artefakte jenseits der Website — getrackt, nicht-gitignored:
# Root-READMEs/Policies + die Store-Listing-Texte unter store/. Anti-Vokabular und
# Removed-Features gelten hier genauso. CHANGELOG.md ist BEWUSST ausgenommen:
# historische „… entfernt"-Notizen (z. B. „Groq removed") sind dort legitim.
public_docs() {
  local f
  for f in "$README" "$ROOT/SECURITY.md" "$ROOT/CONTRIBUTING.md"; do
    [ -f "$f" ] && echo "$f"
  done
  [ -d "$ROOT/store" ] && find "$ROOT/store" -name '*.md' -type f 2>/dev/null
}

# Anti-Vokabular über ALLE öffentlichen Prosa-Artefakte (README, SECURITY, Store-
# Listings). Nur ABSOLUT verbotene Begriffe — kontrastiv-erlaubte bleiben dem
# nuancierten seo-audit-Skill + dem Soft-Drift-Check überlassen (0 False-Positives).
check_antivocab() {
  local abs; abs="$(absolute_antivocab_terms)"
  [ -z "$abs" ] && return 0
  local f t
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      if grep -qiF -- "$t" "$f"; then note "Anti-Vokabular \"$t\" in ${f#$ROOT/}"; fi
    done <<< "$abs"
  done <<< "$(public_docs)"
}

# Extrahiert aus brand-glossary.ts die `term`-Werte, deren Eintrag NICHT
# `contrastiveAllowed: true` trägt. Quelle = maschinenlesbarer §7-Spiegel.
absolute_antivocab_terms() {
  [ -f "$GLOSSARY" ] || return 0
  perl -0777 -ne 'while(/\{\s*term:\s*"([^"]+)"(.*?)\}/sg){ my($t,$rest)=($1,$2); print "$t\n" unless $rest =~ /contrastiveAllowed:\s*true/ }' "$GLOSSARY"
}

# --- Versions-Sync ----------------------------------------------------------
# pubspec `version` ist die EINE Quelle. CHANGELOG-Top darf nicht hinterherhinken
# (genau die Drift, die sonst still auf die Website/GitHub-Release-Page landet).
check_version_sync() {
  [ -f "$PUBSPEC" ] || { note "pubspec.yaml fehlt"; return; }
  local ver
  ver="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?[[:space:]]*$/\1/p' "$PUBSPEC" | head -1)"
  [ -z "$ver" ] && { note "pubspec.yaml: keine semver version gefunden"; return; }

  if [ -f "$CHANGELOG" ]; then
    local clver
    clver="$(grep -m1 -oE '^##[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' "$CHANGELOG" | sed -E 's/^##[[:space:]]+//')"
    [ "$clver" = "$ver" ] || note "CHANGELOG-Top ($clver) ≠ pubspec version ($ver)"
  else
    note "CHANGELOG.md fehlt"
  fi
}

# --- Plattform/Store-Konsistenz (WhisPaste-Kern) ----------------------------
# platforms.ts dokumentiert: „Consumers read exclusively from this file — no
# literal URLs or product IDs elsewhere." Genau diese Drift-Klasse (tote Apple-
# Links, abweichende Store-IDs, hartcodierte Download-URLs) absichern.
check_platform_store() {
  [ -f "$PLATFORMS" ] || { note "platforms.ts (SSoT) fehlt: ${PLATFORMS#$ROOT/}"; return; }

  # (A) MS-Store-Product-ID: genau einmal in platforms.ts definiert; jede weitere
  #     Stelle, die die ID literal trägt, ist Drift.
  local msid
  msid="$(sed -nE "s/.*MS_STORE_PRODUCT_ID = '([^']+)'.*/\1/p" "$PLATFORMS" | head -1)"
  if [ -n "$msid" ]; then
    local dup
    dup="$(grep -rl --include='*.astro' --include='*.ts' --include='*.js' \
             --exclude-dir=__tests__ --exclude='*.test.ts' --exclude='*.spec.ts' \
             -F "$msid" "$WEBSRC" 2>/dev/null | grep -vF "$PLATFORMS" || true)"
    if [ -n "$dup" ]; then
      note "MS-Store-Product-ID ($msid) literal außerhalb platforms.ts (SSoT verletzt):"
      echo "$dup" | sed "s|$ROOT/|    |"
    fi
  fi

  # (B) Apple App Store: macOS hat KEIN Listing (hasStoreListing:false, reviewUrl=
  #     GitHub). Ein `apps.apple.com`-Literal IRGENDWO im Quellcode ist immer ein
  #     toter/falscher Link — sowohl in der Website als auch in der Flutter-App.
  local applehits
  applehits="$(grep -rln --include='*.astro' --include='*.ts' --include='*.js' --include='*.dart' \
               --exclude-dir=__tests__ --exclude='*.test.ts' --exclude='*.spec.ts' \
               -F 'apps.apple.com' "$WEBSRC" "$ROOT/lib" 2>/dev/null || true)"
  if [ -n "$applehits" ]; then
    note "apps.apple.com-Literal gefunden (kein Mac-App-Store-Listing — toter Link):"
    echo "$applehits" | sed "s|$ROOT/|    |"
  fi

  # (C) Store-/Download-Domains dürfen außerhalb platforms.ts nicht literal stehen
  #     (Komponenten lesen die Konstanten). Geprüft: apps.microsoft.com,
  #     ms-windows-store, der GitHub-Release-Download-Basis-Pfad.
  local lit
  for lit in 'apps.microsoft.com' 'ms-windows-store://' 'releases/latest/download'; do
    local hits
    hits="$(grep -rl --include='*.astro' --include='*.ts' --include='*.js' \
              --exclude-dir=__tests__ --exclude='*.test.ts' --exclude='*.spec.ts' \
              -F "$lit" "$WEBSRC" 2>/dev/null | grep -vF "$PLATFORMS" || true)"
    if [ -n "$hits" ]; then
      note "Store-/Download-Literal \"$lit\" außerhalb platforms.ts (sollte die SSoT-Konstante nutzen):"
      echo "$hits" | sed "s|$ROOT/|    |"
    fi
  done

  # (D) macOS-Arch-Konsistenz: arm64-Build ist der einzige; kein Intel/x64-Claim
  #     für macOS in der Website-Quelle. Rekursiv über ALLE Seiten (inkl.
  #     en/, vergleich/, use-cases/) — nicht nur top-level.
  local macintel
  macintel="$(grep -rliE 'mac.{0,12}(intel|x86_64)' --include='*.astro' "$WEBSRC/pages" 2>/dev/null || true)"
  if [ -n "$macintel" ]; then
    note "macOS Intel/x86_64-Behauptung in der Website-Quelle (es gibt nur Apple-Silicon-arm64):"
    echo "$macintel" | sed "s|$ROOT/|    |"
  fi
}

# --- entfernte/nie-ausgelieferte Features (shipped-status-Drift) ------------
# §7-Anti-Vokabular: diese wurden entfernt bzw. nie ausgeliefert und dürfen in
# README/Website nicht als aktuelle Features auftauchen. (CHANGELOG bewusst
# ausgenommen — dort sind historische „… entfernt"-Notizen legitim.)
check_removed_features() {
  local terms=( 'Groq' 'Smart Mode' 'Smart-Korrektur' 'Anthropic STT' 'Gemini STT' 'Command palette' )
  local t files
  # Alle öffentlichen Prosa-Artefakte (README, SECURITY, store/*.md) + ALLE
  # Website-Seiten rekursiv (inkl. en/, vergleich/, use-cases/).
  files="$(public_docs | tr '\n' ' ')"
  [ -d "$WEBSRC/pages" ] && files="$files $(find "$WEBSRC/pages" -name '*.astro' -type f 2>/dev/null | tr '\n' ' ')"
  for t in "${terms[@]}"; do
    local hits; hits="$(grep -ilF -- "$t" $files 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      note "entferntes/nie-ausgeliefertes Feature \"$t\" in öffentlicher Doku:"
      echo "$hits" | sed "s|$ROOT/|    |"
    fi
  done

  # i18n-Text-Quellen (website/src/scripts/i18n.ts u. ä.): DAS ist die eigentliche
  # user-sichtbare Website-Sprache (die .astro-Seiten referenzieren nur Keys).
  # Historische `changelog.*`-Keys werden ausgenommen — dort sind alte Provider-
  # Nennungen legitim (Beschreibung eines vergangenen Releases).
  local i18n_files f
  i18n_files="$(git -C "$ROOT" ls-files 'website/src/**i18n*.ts' 2>/dev/null || true)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$ROOT/$f" ] || continue
    for t in "${terms[@]}"; do
      local cur
      cur="$(grep -nF -- "$t" "$ROOT/$f" 2>/dev/null | grep -v "'changelog\\." || true)"
      if [ -n "$cur" ]; then
        note "entferntes/nie-ausgeliefertes Feature \"$t\" als aktueller String in $f:"
        echo "$cur" | sed -E 's/^([0-9]+):.*/    Zeile \1/'
      fi
    done
  done <<< "$i18n_files"
}

# --- i18n (DE-primär + EN-Mirror) -------------------------------------------
# WhisPaste lokalisiert die Slugs (download↔download, datenschutz↔privacy,
# vergleich/…↔comparison/…). Daher kuratierte DE↔EN-Paarliste statt mechanischem
# Mirror. NEUE Route: nur hier ein Paar ergänzen.
check_i18n() {
  [ -d "$PAGES" ] || { note "website/src/pages fehlt"; return; }
  # Format je Eintrag: "<DE-relativ-zu-pages>|<EN-relativ-zu-pages>"
  local -a PAIRS=(
    "index.astro|en/index.astro"
    "download.astro|en/download.astro"
    "changelog.astro|en/changelog.astro"
    "datenschutz.astro|en/privacy.astro"
    "sponsor.astro|en/sponsor.astro"
    "impressum.astro|en/impressum.astro"
    "screenshots.astro|en/screenshots.astro"
    "offline-speech-to-text.astro|en/offline-speech-to-text.astro"
    "whisper-desktop.astro|en/whisper-desktop.astro"
    "privatsphaere-spracherkennung.astro|en/privacy-speech-recognition.astro"
    "vergleich/whispaste-vs-system-spracheingabe.astro|en/comparison/whispaste-vs-system-speech-to-text.astro"
    "vergleich/diktiersoftware-alternativen.astro|en/comparison/voice-input-tool-alternatives.astro"
    "use-cases/programmierer.astro|en/use-cases/programmer.astro"
    "use-cases/support-mitarbeiter.astro|en/use-cases/support-staff.astro"
    "use-cases/rsi.astro|en/use-cases/rsi.astro"
  )
  local pair de en
  for pair in "${PAIRS[@]}"; do
    de="${pair%%|*}"; en="${pair##*|}"
    [ -f "$PAGES/$de" ] || note "i18n: DE-Seite fehlt: src/pages/$de"
    [ -f "$PAGES/$en" ] || note "i18n: EN-Seite fehlt (Pendant zu $de): src/pages/$en"
  done
  # hreflang-Alternates müssen existieren (im Layout oder pro Seite).
  if [ -d "$WEBSRC" ] && ! grep -rqF 'hreflang' "$WEBSRC" 2>/dev/null; then
    note "i18n: kein hreflang-Alternate in der Website-Quelle gefunden"
  fi
}

cmd_check() {
  fail=0
  [ -f "$SPEC" ] || echo "  ⚠ ${SPEC#$ROOT/} nicht vorhanden (lokal/gitignored) — README-Marker-Checks übersprungen." >&2
  check_readme
  check_antivocab
  check_version_sync
  check_platform_store
  check_removed_features
  check_i18n
  [ "$fail" -eq 0 ] || { echo "Public-Docs-QS (check) fehlgeschlagen." >&2; exit 1; }
  echo "Public-Docs-QS check: ok (README+SECURITY+store · anti-vocab · version-sync · platform/store-SSoT · removed-features · i18n)"
}

cmd_attest() {
  cmd_check
  git -C "$ROOT" rev-parse HEAD > "$ATTEST"
  echo "Öffentliche Docs als aktuell & aufbaukonform bestätigt für $(cat "$ATTEST")."
  echo "Hinweis: attest = README, CHANGELOG, Website (DE+EN) und Plattform/Store-SSoT GELESEN und gegen den Repo-Stand geprüft."
}

cmd_attested() { [ -f "$ATTEST" ] && cat "$ATTEST" || true; }

case "${1:-}" in
  check)    cmd_check ;;
  attest)   cmd_attest ;;
  attested) cmd_attested ;;
  *) echo "usage: $0 {check|attest|attested}" >&2; exit 2 ;;
esac
