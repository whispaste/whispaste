#!/usr/bin/env bash
#
# WhisPaste Sprachdienst-Diagnose (macOS)
#
# Liest die WhisPaste-Sprachdienst-Umgebung aus und erstellt einen Debug-Report:
# App-Bundle, whisper-server-Binary, Modell, dylib-Abhängigkeiten, Quarantäne-/
# Signatur-Status und einen echten Modell-Ladetest. Das macOS-Pendant zu
# tools/whispaste-diagnose.ps1.
#
# Per Doppelklick (Finder öffnet ein Terminal) oder per CLI ausführbar:
#   bash whispaste-diagnose-macos.command [--no-run-test] [--no-pause] [--out-file PATH]
#
set -uo pipefail

NO_RUN_TEST=0
NO_PAUSE=0
OUT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --no-run-test) NO_RUN_TEST=1 ;;
    --no-pause)    NO_PAUSE=1 ;;
    --out-file)    OUT_FILE="${2:-}"; shift ;;
    --out-file=*)  OUT_FILE="${1#*=}" ;;
    *) echo "Unbekannte Option: $1" >&2 ;;
  esac
  shift
done

# Default-Report-Pfad auf dem Schreibtisch mit Zeitstempel.
if [ -z "$OUT_FILE" ]; then
  OUT_FILE="$HOME/Desktop/WhisPaste-Diagnose_$(date +%Y%m%d_%H%M%S).txt"
fi

# Report gleichzeitig in Datei und auf die Konsole schreiben.
exec > >(tee "$OUT_FILE") 2>&1

line() { printf '%s\n' "$*"; }
section() { printf '\n=== %s ===\n' "$*"; }

line "WhisPaste Sprachdienst-Diagnose (macOS)"
line "Erstellt: $(date '+%Y-%m-%d %H:%M:%S')"
line "Report:   $OUT_FILE"

# --- System ----------------------------------------------------------------
section "System"
line "macOS:        $(sw_vers -productVersion 2>/dev/null) (Build $(sw_vers -buildVersion 2>/dev/null))"
line "Architektur:  $(uname -m)"

# --- App-Bundle ------------------------------------------------------------
section "WhisPaste-App"
APP=""
for candidate in \
  "/Applications/whispaste.app" \
  "/Applications/WhisPaste.app" \
  "$HOME/Applications/whispaste.app" \
  "$HOME/Applications/WhisPaste.app"; do
  if [ -d "$candidate" ]; then APP="$candidate"; break; fi
done

if [ -n "$APP" ]; then
  line "Bundle:       $APP"
  PLIST="$APP/Contents/Info.plist"
  if [ -f "$PLIST" ]; then
    VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)
    line "Version:      ${VER:-(unbekannt)}"
  fi
else
  line "Bundle:       (WhisPaste.app nicht in /Applications gefunden)"
fi

# --- Datenverzeichnis + whisper-server -------------------------------------
section "Sprachdienst"
DATA="$HOME/Library/Application Support/WhisPaste"
# App-Store-Builds laufen sandboxed in einem Container.
if [ ! -d "$DATA" ]; then
  for c in "$HOME"/Library/Containers/*/Data/Library/Application\ Support/WhisPaste; do
    if [ -d "$c" ]; then DATA="$c"; break; fi
  done
fi
STT_DIR="$DATA/models/stt"
line "Datenordner:  $DATA"
line "STT-Ordner:   $STT_DIR"

# whisper-server: zuerst im App-Bundle (Helpers), dann im STT-Ordner.
SERVER=""
if [ -n "$APP" ] && [ -x "$APP/Contents/Helpers/whisper-server" ]; then
  SERVER="$APP/Contents/Helpers/whisper-server"
elif [ -x "$STT_DIR/whisper-server" ]; then
  SERVER="$STT_DIR/whisper-server"
fi

if [ -n "$SERVER" ]; then
  line "Binary:       $SERVER"
else
  line "Binary:       (whisper-server nicht gefunden)"
fi

# .server-info.json (aktiver Backend)
INFO="$STT_DIR/.server-info.json"
if [ -f "$INFO" ]; then
  BACKEND=$(grep -o '"backend"[^,}]*' "$INFO" 2>/dev/null | head -1)
  line "Server-Info:  ${BACKEND:-vorhanden}"
fi

# Modell: größtes ggml-*.bin im STT-Ordner.
MODEL=""
if [ -d "$STT_DIR" ]; then
  MODEL=$(find "$STT_DIR" -maxdepth 1 -name 'ggml-*.bin' -type f \
    -exec stat -f '%z %N' {} + 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi
if [ -n "$MODEL" ]; then
  line "Modell:       $(basename "$MODEL") ($(du -h "$MODEL" 2>/dev/null | cut -f1))"
else
  line "Modell:       (kein ggml-*.bin gefunden)"
fi

# Dateien im STT-Ordner
if [ -d "$STT_DIR" ]; then
  section "Dateien im STT-Ordner"
  ls -la "$STT_DIR" 2>/dev/null
fi

# --- Signatur / Quarantäne (macOS-Failure-Modes) ---------------------------
if [ -n "$SERVER" ]; then
  section "Binary-Status"
  QUAR=$(xattr -p com.apple.quarantine "$SERVER" 2>/dev/null)
  if [ -n "$QUAR" ]; then
    line "Quarantäne:   JA ($QUAR) — Gatekeeper kann den Start blockieren."
  else
    line "Quarantäne:   nein"
  fi
  line "Signatur:"
  codesign -dv "$SERVER" 2>&1 | sed 's/^/  /'
  line "Gatekeeper:"
  spctl -a -vv -t execute "$SERVER" 2>&1 | sed 's/^/  /'

  section "dylib-Abhängigkeiten (otool -L)"
  otool -L "$SERVER" 2>/dev/null | sed 's/^/  /'
fi

# --- Echter Modell-Ladetest -------------------------------------------------
if [ "$NO_RUN_TEST" -eq 0 ] && [ -n "$SERVER" ] && [ -n "$MODEL" ]; then
  section "Modell-Ladetest"
  line "Starte whisper-server mit --no-gpu (max. 12 s)…"
  PORT=$(( (RANDOM % 20000) + 40000 ))
  ERR=$(mktemp)
  WORKDIR=$(dirname "$SERVER")
  ( cd "$WORKDIR" && "$SERVER" --model "$MODEL" --host 127.0.0.1 --port "$PORT" \
      --threads 4 --no-timestamps --no-gpu >/dev/null 2>"$ERR" ) &
  PID=$!
  for _ in $(seq 1 12); do
    sleep 1
    if ! kill -0 "$PID" 2>/dev/null; then break; fi
  done
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
    line "Ergebnis:     OK — Server lädt das Modell (blieb stabil)."
  else
    wait "$PID" 2>/dev/null
    CODE=$?
    line "Ergebnis:     FEHLER — Server beendet mit Exit-Code $CODE."
    if [ -s "$ERR" ]; then
      line "stderr (letzte Zeilen):"
      tail -n 8 "$ERR" | sed 's/^/  /'
    fi
  fi
  rm -f "$ERR"
elif [ "$NO_RUN_TEST" -eq 0 ]; then
  section "Modell-Ladetest"
  line "Übersprungen: Binary oder Modell nicht gefunden."
fi

# --- Log-Tail --------------------------------------------------------------
LOG="$DATA/logs/whispaste.log"
if [ -f "$LOG" ]; then
  section "Letzte 40 Logzeilen"
  tail -n 40 "$LOG"
fi

line ""
line "Fertig. Bitte sende die Datei $OUT_FILE an den Support."

if [ "$NO_PAUSE" -eq 0 ]; then
  line ""
  read -r -p "Zum Schließen Enter drücken… " _
fi
