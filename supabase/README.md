# Supabase

Schema, policies and cron jobs for the feedback backend live in
`migrations/`. Migrations are additive only and are applied by the
maintainer.

## Runbook

- **Quote consent withdrawn by e-mail:** the mail carries a withdrawal
  reference, the `withdraw_token_hash` of the row. For the row whose
  `withdraw_token_hash` equals that reference, set
  `approved_for_display = false`, `publish_consent = false`,
  `withdrawn_at = coalesce(withdrawn_at, now())` and
  `withdraw_token_hash = NULL`, the same as the in-app withdrawal RPC does.
  Without a reference, find the row by the feedback date in the mail. The
  daily archival cron deletes the row at the latest 90 days after it was
  received.
- **Withdrawal e-mail retention:** delete the e-mail from the mailbox at the
  latest 90 days after it arrived, the same period as the feedback entry. It
  is kept only as evidence that the withdrawal was carried out (privacy
  policy §16, storage limitation under Art. 5(1)(e) GDPR).

## Tests

`tests/run_withdraw_cleanup.sh` applies the whole migration chain to a
throwaway local Postgres 16 (native, e.g. `brew install postgresql@16`; no
service, no Docker) and checks the consent withdrawal (approval and hash
cleared, idempotent retries, backfill of earlier withdrawals, the public
view, the archival cron) and the privileges and RLS policies of the API
roles. It never touches a Supabase project and is not part of CI.

    bash supabase/tests/run_withdraw_cleanup.sh [target-migration.sql]

The target defaults to the newest migration; the script aborts if newer
files exist, if `pg_ctl` is missing or if Postgres is not version 16.
`MIGRATIONS_DIR` points it at another folder, for example a deliberately
broken copy to prove that a check fails.

What is stubbed (`tests/supabase_stubs.sql`): the roles `anon`,
`authenticated` and `service_role` with Supabase's default privileges on
`public`, the `auth` helpers, and `pg_cron`, Vault and `pg_net`. `pg_cron`
only records jobs; the test runs the archival job's command itself via
`EXECUTE`, as the test's superuser; real `pg_cron` runs it as the job's
owner (`postgres` or `supabase_admin`), which the test does not reproduce.
`tests/fixtures/replay_fix_*.sql` repair historic migrations that cannot
replay on a fresh database and run right before them.

The stubs simulate Supabase's standard privileges. A real project can differ,
for example after grants made in the dashboard, so check its privileges
before applying a migration: `\dp public.*` and `\df+` in `psql`, or
`has_function_privilege('anon', 'public.<function>(<args>)', 'EXECUTE')`
and `has_table_privilege(...)` against the project.
