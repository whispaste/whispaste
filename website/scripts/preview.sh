#!/usr/bin/env bash
# `npm run preview` entrypoint. Astro's CLI self-daemonizes `astro preview`
# unconditionally as of astro 7.2+ (introduced somewhere between 7.1.3 and
# 7.2.8, unavoidable at any version carrying the required Critical-CVE fix):
# the start command always returns immediately with the server already
# running in the background, instead of blocking in the foreground. A caller
# that expects a blocking foreground process (Playwright's webServer, most
# notably) then sees the process "exit early" and fails, even though the
# server is up and healthy. Mirrors scripts/dev.sh's fix for the same issue.
set -euo pipefail
cd "$(dirname "$0")/.."

# Unlike scripts/dev.sh (which deliberately reuses an already-running dev
# server shared across agents/terminals on a fixed port), preview is started
# fresh per invocation with a caller-chosen port (e.g. CI's PLAYWRIGHT_PORT).
# Reusing a stale server left running on a different port would make the
# caller wait on the wrong port and time out, so always stop any leftover
# instance first instead of attaching to it.
npx astro preview stop >/dev/null 2>&1 || true

npx astro preview "$@"
exec npx astro preview logs --follow
