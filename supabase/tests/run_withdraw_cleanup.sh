#!/usr/bin/env bash
# Applies the migration chain to a throwaway local Postgres 16 and checks the
# consent withdrawal (approval and hash cleared, idempotent retries, backfill,
# public view, archival cron) plus the privileges and RLS policies of the API
# roles. Never touches a Supabase project.
#
# Needs a native Postgres 16 (macOS: brew install postgresql@16; no service).
#
#   bash supabase/tests/run_withdraw_cleanup.sh [target-migration.sql]
#
# The target defaults to the withdrawal migration the seed was written for
# (20261020110000). The seed runs right before it; migrations newer than the
# target are applied after it, before the assertions. MIGRATIONS_DIR overrides
# the migrations folder, for example to prove that a broken copy fails.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "$0")" && pwd)"
migrations="${MIGRATIONS_DIR:-$here/../migrations}"

shopt -s nullglob
files=("$migrations"/*.sql)
shopt -u nullglob
if (( ${#files[@]} == 0 )); then
  echo "No migrations in $migrations" >&2
  exit 1
fi
target="${1:-20261020110000_feedback_withdraw_clears_hash.sql}"
if [[ ! -f "$migrations/$target" ]]; then
  echo "Target migration not found: $target" >&2
  exit 1
fi

pg_bin="${PG_BIN:-}"
if [[ -z "$pg_bin" ]]; then
  for candidate in /opt/homebrew/opt/postgresql@16/bin \
    /usr/local/opt/postgresql@16/bin /usr/lib/postgresql/16/bin; do
    if [[ -x "$candidate/pg_ctl" ]]; then pg_bin="$candidate"; break; fi
  done
fi
if [[ -z "$pg_bin" ]] && command -v pg_ctl >/dev/null; then
  pg_bin="$(dirname "$(command -v pg_ctl)")"
fi
if [[ -z "$pg_bin" || ! -x "$pg_bin/pg_ctl" ]]; then
  echo "pg_ctl not found. Install Postgres 16 natively" \
    "(macOS: brew install postgresql@16) or set PG_BIN." >&2
  exit 1
fi
major="$("$pg_bin/pg_ctl" --version | sed -E 's/.* ([0-9]+)(\.[0-9]+)*.*/\1/')"
if [[ "$major" != 16 ]]; then
  echo "Postgres 16 required (Supabase), found $major in $pg_bin." >&2
  exit 1
fi

data="$(mktemp -d "${TMPDIR:-/tmp}/wp-pg.XXXXXX")"
# Unix socket paths are limited to ~103 bytes, so the socket gets a short dir.
sock="$(mktemp -d /tmp/wppg.XXXXXX)"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"

cleanup() {
  # KEEP_LOG=<file> keeps the server log for debugging.
  [[ -n "${KEEP_LOG:-}" ]] && cp "$data/server.log" "$KEEP_LOG" 2>/dev/null || true
  "$pg_bin/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$data" "$sock"
}
trap cleanup EXIT INT TERM

"$pg_bin/initdb" -D "$data" -U postgres -A trust --no-locale -E UTF8 >/dev/null
"$pg_bin/pg_ctl" -D "$data" -l "$data/server.log" -w \
  -o "-p $port -k $sock -c listen_addresses=''" start >/dev/null

psql_run() {
  "$pg_bin/psql" -X -q -h "$sock" -p "$port" -U postgres -d postgres \
    -v ON_ERROR_STOP=1 "$@"
}

# Fixes for historic migrations that cannot replay on a fresh database. They
# run right before the named migration and are not part of the chain.
replay_fix() {
  case "$1" in
    20260414_drop_crash_report_events.sql)
      echo "$here/fixtures/replay_fix_crash_views.sql" ;;
  esac
}

psql_run -f "$here/supabase_stubs.sql"
for path in "${files[@]}"; do
  file="$(basename "$path")"
  # The seed holds rows written before the target, so it runs just before it.
  if [[ "$file" == "$target" ]]; then
    psql_run -f "$here/withdraw_cleanup_seed.sql" >/dev/null
  fi
  fix="$(replay_fix "$file")"
  [[ -n "$fix" ]] && psql_run -f "$fix" >/dev/null
  psql_run -f "$path" >/dev/null
done
psql_run -t -A -f "$here/privileges_assert.sql"
psql_run -t -A -f "$here/withdraw_cleanup_assert.sql"
psql_run -t -A -f "$here/feedback_quote_v2_assert.sql"
echo "withdraw cleanup and privileges: all checks passed"
