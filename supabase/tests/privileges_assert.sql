-- Privilege and RLS checks after the whole chain. With the Supabase default
-- privileges from supabase_stubs.sql, a migration that forgets a REVOKE
-- fails here.

CREATE TEMP TABLE p_check (name text, ok boolean);

-- anon: no table-wide read, write or delete on user_feedback.
INSERT INTO p_check
SELECT 'anon has no table-wide ' || priv || ' on user_feedback',
       NOT has_table_privilege('anon', 'public.user_feedback', priv)
  FROM unnest(ARRAY['SELECT', 'UPDATE', 'DELETE', 'TRUNCATE',
                    'REFERENCES', 'TRIGGER']) AS priv;

-- anon may read exactly the columns the testimonials view needs.
INSERT INTO p_check
SELECT 'anon SELECT on ' || col || ' is ' || allowed::text,
       has_column_privilege('anon', 'public.user_feedback', col, 'SELECT')
         = allowed
  FROM (VALUES ('rating', true), ('feedback_text', true),
               ('received_at', true), ('approved_for_display', true),
               ('contact_email', false), ('device_id_hash', false),
               ('ip_hash', false), ('withdraw_token_hash', false),
               ('curated_text', false), ('withdrawn_at', false))
       AS c(col, allowed);

-- anon may insert what the app sends, including the withdrawal hash.
INSERT INTO p_check
SELECT 'anon may INSERT ' || col,
       has_column_privilege('anon', 'public.user_feedback', col, 'INSERT')
  FROM unnest(ARRAY['rating', 'feedback_text', 'app_version',
                    'device_id_hash', 'category', 'locale', 'contact_email',
                    'contact_locale', 'withdraw_token_hash']) AS col;

-- authenticated: nothing at all on user_feedback.
INSERT INTO p_check
SELECT 'authenticated has no ' || priv || ' on any user_feedback column',
       NOT has_any_column_privilege('authenticated', 'public.user_feedback',
                                    priv)
  FROM unnest(ARRAY['SELECT', 'INSERT', 'UPDATE']) AS priv;
INSERT INTO p_check
SELECT 'authenticated has no DELETE on user_feedback',
       NOT has_table_privilege('authenticated', 'public.user_feedback',
                               'DELETE');

-- RLS on, and the policies the app relies on exist.
INSERT INTO p_check
SELECT 'RLS enabled on user_feedback', relrowsecurity
  FROM pg_class WHERE oid = 'public.user_feedback'::regclass;
INSERT INTO p_check
SELECT 'policy ' || pol || ' exists', EXISTS (
  SELECT 1 FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'user_feedback'
     AND policyname = pol)
  FROM unnest(ARRAY['anon_can_insert_feedback',
                    'anon_select_approved_feedback']) AS pol;

-- Functions: only the withdrawal RPC is callable by the API roles.
INSERT INTO p_check
SELECT 'anon may call withdraw_feedback_publish_consent',
       has_function_privilege('anon',
         'public.withdraw_feedback_publish_consent(text)', 'EXECUTE');
INSERT INTO p_check
SELECT 'authenticated may not call withdraw_feedback_publish_consent',
       NOT has_function_privilege('authenticated',
         'public.withdraw_feedback_publish_consent(text)', 'EXECUTE');
INSERT INTO p_check
SELECT role || ' may not call ' || fn,
       NOT has_function_privilege(role, 'public.' || fn || '()', 'EXECUTE')
  FROM unnest(ARRAY['check_feedback_global_cap', 'check_feedback_ip_rate_limit',
                    'check_feedback_rate_limit', 'enforce_feedback_defaults',
                    'rls_auto_enable', 'stamp_feedback_publish_consent'])
       AS fn,
       unnest(ARRAY['anon', 'authenticated']) AS role;

-- The public view stays readable for anon.
INSERT INTO p_check
SELECT 'anon may read public_testimonials',
       has_table_privilege('anon', 'public.public_testimonials', 'SELECT');

SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name FROM p_check;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM p_check WHERE ok IS NOT TRUE) THEN
    RAISE EXCEPTION 'privileges: % check(s) failed',
      (SELECT count(*) FROM p_check WHERE ok IS NOT TRUE);
  END IF;
END $$;
