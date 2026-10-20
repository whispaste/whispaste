-- Minimal stand-ins for what a Supabase project provides, so the migration
-- chain applies to a plain local Postgres. Only what the migrations touch.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END $$;

-- pg_cron: jobs are only recorded, never run.
CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE IF NOT EXISTS cron.job (
  jobid bigserial PRIMARY KEY,
  jobname text UNIQUE,
  schedule text,
  command text
);
CREATE TABLE IF NOT EXISTS cron.job_run_details (runid bigserial, jobid bigint);
CREATE OR REPLACE FUNCTION cron.schedule(p_name text, p_schedule text, p_command text)
RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command)
  VALUES (p_name, p_schedule, p_command)
  ON CONFLICT (jobname) DO UPDATE
    SET schedule = excluded.schedule, command = excluded.command
  RETURNING jobid;
$$;
CREATE OR REPLACE FUNCTION cron.unschedule(p_name text)
RETURNS boolean LANGUAGE sql AS $$
  WITH d AS (DELETE FROM cron.job WHERE jobname = p_name RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM d);
$$;

-- Supabase Vault and pg_net, referenced by retired cron jobs only.
CREATE SCHEMA IF NOT EXISTS vault;
CREATE TABLE IF NOT EXISTS vault.secrets (name text, secret text);
CREATE OR REPLACE VIEW vault.decrypted_secrets AS
  SELECT name, secret AS decrypted_secret FROM vault.secrets;
CREATE OR REPLACE FUNCTION vault.create_secret(p_secret text, p_name text)
RETURNS void LANGUAGE sql AS $$ INSERT INTO vault.secrets VALUES (p_name, p_secret) $$;

CREATE SCHEMA IF NOT EXISTS net;
CREATE OR REPLACE FUNCTION net.http_get(url text, headers jsonb DEFAULT '{}')
RETURNS bigint LANGUAGE sql AS $$ SELECT 0::bigint $$;

-- Provided by the Supabase platform; the migrations only revoke EXECUTE on it.
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS void LANGUAGE sql AS $$ SELECT $$;

-- Supabase grants the API roles everything on new objects in public; only
-- the REVOKEs in the migrations take it away again. Without these defaults a
-- forgotten REVOKE would go unnoticed here. Functions also keep the stock
-- Postgres EXECUTE for PUBLIC.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;

-- Supabase auth helpers, read from the PostgREST request claims.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.role', true), '')
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
