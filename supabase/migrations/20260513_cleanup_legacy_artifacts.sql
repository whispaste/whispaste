-- Cleanup of stale artifacts left over from retired features.
--
-- Three groups of dead state are removed here:
--
--   1. crash_patterns / crash_daily_summary views (from 20260404).
--      Both selected FROM public.crash_report_events, which was dropped in
--      20260414. The DROP TABLE in that migration lacked CASCADE; the views
--      were removed out-of-band on the deployed instance. Dropping them
--      explicitly here makes a fresh-from-scratch migration run reproducible.
--
--   2. user_feedback.user_agent column. Referenced by enforce_feedback_defaults
--      (20260421) but never added by any ALTER TABLE in this repo, and never
--      written by the Flutter client. The trigger's user-agent block (plus
--      the unused raw_ua variable) was orphaned code — the column gets
--      dropped and the trigger function is rewritten without it.
--
--   3. user_feedback.discord_message_id / .discord_cleaned_at columns.
--      Vestiges of the Discord crash-relay pipeline retired with the Sentry
--      migration (20260411–20260414). Nothing reads or writes them anymore.

-- ─── 1. Drop orphaned analytics views ──────────────────────────────
DROP VIEW IF EXISTS public.crash_patterns;
DROP VIEW IF EXISTS public.crash_daily_summary;

-- ─── 2. Rewrite enforce_feedback_defaults without user_agent ───────
CREATE OR REPLACE FUNCTION public.enforce_feedback_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  headers_raw text;
  xff         text;
  ip_parts    text[];
  last_ip     text;
BEGIN
  -- Always generate a fresh UUID so callers cannot control the PK.
  NEW.id          := gen_random_uuid();
  NEW.received_at := now();

  -- Extract real client IP from PostgREST forwarded headers when present.
  headers_raw := current_setting('request.headers', true);
  IF headers_raw IS NOT NULL AND headers_raw <> '' THEN
    BEGIN
      xff := (headers_raw::json) ->> 'x-forwarded-for';
      IF xff IS NOT NULL AND xff <> '' THEN
        ip_parts := string_to_array(xff, ',');
        last_ip  := trim(ip_parts[array_length(ip_parts, 1)]);
        IF last_ip IS NOT NULL AND last_ip <> '' THEN
          NEW.ip_hash := encode(sha256(last_ip::bytea), 'hex');
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Malformed header: silently ignore, keep caller-supplied ip_hash if any.
      NULL;
    END;
  END IF;

  -- Force safe defaults for moderation fields.
  NEW.approved_for_display := false;
  NEW.status               := 'received';

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_feedback_defaults() IS
  'Trigger: overwrite id/received_at, extract ip_hash from forwarded headers, force safe moderation defaults.';

-- ─── 3. Drop dead columns on user_feedback ─────────────────────────
ALTER TABLE public.user_feedback DROP COLUMN IF EXISTS user_agent;
ALTER TABLE public.user_feedback DROP COLUMN IF EXISTS discord_message_id;
ALTER TABLE public.user_feedback DROP COLUMN IF EXISTS discord_cleaned_at;
