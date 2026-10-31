-- Assertions after 20261021110000 (anon INSERT narrowed to the app's columns).
-- Rolled back at the end, so no row reaches later checks.
BEGIN;

-- 1. Every column of user_feedback: anon may INSERT it exactly when the app
--    sends it. No table-level INSERT is left behind.
CREATE TEMP TABLE g_check (name text, ok boolean);

INSERT INTO g_check
SELECT 'anon has no table-level INSERT on user_feedback',
       NOT has_table_privilege('anon', 'public.user_feedback', 'INSERT');

INSERT INTO g_check
SELECT 'anon INSERT on ' || a.attname || ' is ' || (a.attname = ANY (allowed))::text,
       has_column_privilege('anon', 'public.user_feedback', a.attname, 'INSERT')
         = (a.attname = ANY (allowed))
  FROM pg_attribute a,
       (SELECT ARRAY['rating', 'feedback_text', 'category', 'app_version',
                     'device_id_hash', 'locale', 'contact_email',
                     'contact_locale', 'publish_consent',
                     'consent_text_version', 'withdraw_token_hash']::text[]
               AS allowed) s
 WHERE a.attrelid = 'public.user_feedback'::regclass
   AND a.attnum > 0 AND NOT a.attisdropped;

-- 2. The app's real submit payload, sent as anon, is accepted and stamped.
SET SESSION AUTHORIZATION anon;
INSERT INTO public.user_feedback
  (rating, feedback_text, category, app_version, device_id_hash, locale,
   contact_email, contact_locale, publish_consent, consent_text_version,
   withdraw_token_hash)
VALUES
  (5, 'app payload quote', 'general', '1.4.0', 'abcdef012345', 'de',
   'user@example.org', 'de', true, 'feedback-quote-v2', repeat('a', 64));
RESET SESSION AUTHORIZATION;

INSERT INTO g_check
SELECT 'app payload is stored, consent stamped, not approved',
       consent_at IS NOT NULL AND publish_consent
       AND NOT approved_for_display AND source = 'in_app'
  FROM public.user_feedback WHERE feedback_text = 'app payload quote';

-- 3. Columns the client must not set are refused with insufficient_privilege.
DO $$
DECLARE
  probe record;
BEGIN
  SET SESSION AUTHORIZATION anon;
  FOR probe IN
    SELECT * FROM (VALUES
      ('approved_for_display', 'true'),
      ('source', 'mas'),
      ('source_ref', 'forged-ref'),
      ('curated_text', 'forged quote'),
      ('status', 'approved'),
      ('received_at', '2020-01-01'),
      ('id', '00000000-0000-0000-0000-000000000001'),
      ('ip_hash', 'deadbeef'),
      ('consent_at', '2020-01-01'),
      ('withdrawn_at', '2020-01-01')
    ) AS t(col, val)
  LOOP
    BEGIN
      EXECUTE format(
        'INSERT INTO public.user_feedback
           (rating, feedback_text, app_version, device_id_hash, category, %I)
         VALUES (4, ''probe'', ''1.4.0'', ''abcdef012345'', ''general'', %L)',
        probe.col, probe.val);
      RAISE EXCEPTION 'anon INSERT on % was accepted', probe.col;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END LOOP;
  RESET SESSION AUTHORIZATION;
END
$$;

SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name FROM g_check;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM g_check WHERE ok IS NOT TRUE) THEN
    RAISE EXCEPTION 'feedback insert grants: % check(s) failed',
      (SELECT count(*) FROM g_check WHERE ok IS NOT TRUE);
  END IF;
  RAISE NOTICE 'feedback insert grants: all checks passed';
END
$$;

ROLLBACK;
