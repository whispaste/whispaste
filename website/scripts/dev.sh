#!/usr/bin/env bash
# `npm run dev` entrypoint. Mehrere Agenten/Terminals teilen sich diesen Port:
# statt bei "Another astro dev server is already running" hart abzubrechen,
# hängt sich dieses Skript an einen bereits laufenden Server (egal ob von
# einem Agent im Hintergrund oder von einem anderen Terminal im Vordergrund
# gestartet) an, statt ihn zu ersetzen oder zu duplizieren. Astros eigenes
# Lockfile (.astro/dev.json) erkennt dabei auch verwaiste/tote Locks selbst
# und räumt sie auf -- das muss dieses Skript nicht nachbauen.
set -euo pipefail
cd "$(dirname "$0")/.."

STATUS="$(npx astro dev status 2>&1 || true)"

if echo "$STATUS" | grep -qi "running at"; then
  echo "$STATUS"
  if echo "$STATUS" | grep -qi "background"; then
    echo
    echo "-> Dev-Server läuft bereits im Hintergrund (siehe oben). Folge seinen Logs -- Strg+C beendet nur das Mitlesen, nicht den Server:"
    exec npx astro dev logs --follow
  fi
  echo
  echo "-> Dev-Server läuft bereits im Vordergrund eines anderen Terminals/Prozesses. Dort weitermachen; hier ist nichts zu starten."
  exit 0
fi

trap 'kill 0' EXIT INT TERM
astro dev &
wait
