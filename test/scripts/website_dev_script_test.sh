#!/usr/bin/env bash
# Regression test for website/scripts/dev.sh, the command Playwright's
# webServer runs locally (`npm run dev -- --host 127.0.0.1 --port N`):
#  1. a cold start must honour the caller's --host/--port, or Playwright
#     polls 127.0.0.1:N while astro listens on localhost:4321 and the
#     webServer times out after 120s;
#  2. the self-daemonized astro dev server it started must stop when the
#     script is terminated, or every test run leaves an orphan (PPID 1).
# Needs website/node_modules (npm ci). Skips if a shared dev server is
# already running there, since dev.sh then attaches to it by design.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WEB="$ROOT/website"

if [ ! -d "$WEB/node_modules/astro" ]; then
  echo "SKIP: website/node_modules missing (run npm ci in website/)"
  exit 0
fi
if (cd "$WEB" && npx astro dev status 2>&1) | grep -qi "running at"; then
  echo "SKIP: a dev server is already running in website/"
  exit 0
fi

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
LOG="$(mktemp)"
bash "$WEB/scripts/dev.sh" --host 127.0.0.1 --port "$PORT" >"$LOG" 2>&1 &
DEV_PID=$!
cleanup() {
  kill "$DEV_PID" 2>/dev/null || true
  (cd "$WEB" && npx astro dev stop >/dev/null 2>&1) || true
  rm -f "$LOG"
}
trap cleanup EXIT

up=""
for _ in $(seq 1 60); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/"; then up=1; break; fi
  sleep 1
done
if [ -z "$up" ]; then
  echo "FAIL: dev.sh did not serve on 127.0.0.1:$PORT within 60s (--host/--port ignored?)"
  cat "$LOG"
  exit 1
fi

kill -TERM "$DEV_PID"
wait "$DEV_PID" 2>/dev/null || true
for _ in $(seq 1 15); do
  if ! (cd "$WEB" && npx astro dev status 2>&1) | grep -qi "running at"; then
    echo "PASS: dev.sh honours --host/--port and stops its daemon on SIGTERM"
    exit 0
  fi
  sleep 1
done
echo "FAIL: astro dev daemon still running after dev.sh got SIGTERM"
exit 1
