-- Assertions after 20261020110000 (run as the superuser, RPC calls as anon).

CREATE TEMP TABLE t_check (name text, ok boolean);

-- Backfill: the row withdrawn earlier lost approval and hash.
INSERT INTO t_check
SELECT 'backfill clears approval and hash',
       NOT approved_for_display AND withdraw_token_hash IS NULL
  FROM public.user_feedback WHERE device_id_hash = 'dev-old';

-- The live quote is public before the withdrawal.
INSERT INTO t_check
SELECT 'live quote is public', EXISTS (
  SELECT 1 FROM public.public_testimonials WHERE text = 'live quote');

SET ROLE anon;
SELECT public.withdraw_feedback_publish_consent('live-secret-0123456789');
RESET ROLE;

CREATE TEMP TABLE t_first AS
SELECT withdrawn_at FROM public.user_feedback WHERE device_id_hash = 'dev-live';

INSERT INTO t_check
SELECT 'withdrawal clears consent, approval and hash',
       NOT publish_consent AND NOT approved_for_display
       AND withdraw_token_hash IS NULL AND withdrawn_at IS NOT NULL
  FROM public.user_feedback WHERE device_id_hash = 'dev-live';

-- Second call (client retry): no error, nothing changes.
SET ROLE anon;
SELECT public.withdraw_feedback_publish_consent('live-secret-0123456789');
-- Unknown and malformed tokens are silent no-ops as well.
SELECT public.withdraw_feedback_publish_consent('unknown-secret-0123456789');
SELECT public.withdraw_feedback_publish_consent('short');
SELECT public.withdraw_feedback_publish_consent(NULL);
RESET ROLE;

INSERT INTO t_check
SELECT 'second call keeps the first withdrawal time',
       f.withdrawn_at = u.withdrawn_at
  FROM t_first f, public.user_feedback u WHERE u.device_id_hash = 'dev-live';

INSERT INTO t_check
SELECT 'withdrawn quote is not public', NOT EXISTS (
  SELECT 1 FROM public.public_testimonials
   WHERE text IN ('live quote', 'old withdrawn quote'));

INSERT INTO t_check
SELECT 'store review untouched and public',
       approved_for_display AND EXISTS (
         SELECT 1 FROM public.public_testimonials WHERE text = 'store review')
  FROM public.user_feedback WHERE device_id_hash = 'dev-store';

-- anon still cannot read the table.
INSERT INTO t_check
SELECT 'anon has no SELECT on user_feedback',
       NOT has_table_privilege('anon', 'public.user_feedback', 'SELECT');

-- Run the archival cron command as recorded by the migrations.
DO $$
DECLARE cmd text;
BEGIN
  SELECT command INTO STRICT cmd FROM cron.job
   WHERE jobname = 'feedback-archival-daily';
  EXECUTE cmd;
END $$;

INSERT INTO t_check
SELECT 'cron deletes the old withdrawn row', NOT EXISTS (
  SELECT 1 FROM public.user_feedback WHERE device_id_hash = 'dev-old');
INSERT INTO t_check
SELECT 'cron keeps the recent withdrawn row until day 90', EXISTS (
  SELECT 1 FROM public.user_feedback WHERE device_id_hash = 'dev-live');
INSERT INTO t_check
SELECT 'cron keeps the approved store review', EXISTS (
  SELECT 1 FROM public.user_feedback WHERE device_id_hash = 'dev-store');

-- At day 90 the recent row goes too.
UPDATE public.user_feedback SET received_at = now() - interval '91 days'
 WHERE device_id_hash = 'dev-live';
DO $$
DECLARE cmd text;
BEGIN
  SELECT command INTO STRICT cmd FROM cron.job
   WHERE jobname = 'feedback-archival-daily';
  EXECUTE cmd;
END $$;
INSERT INTO t_check
SELECT 'cron deletes the withdrawn row after 90 days', NOT EXISTS (
  SELECT 1 FROM public.user_feedback WHERE device_id_hash = 'dev-live');

SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name FROM t_check;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM t_check WHERE ok IS NOT TRUE) THEN
    RAISE EXCEPTION 'withdraw cleanup: % check(s) failed',
      (SELECT count(*) FROM t_check WHERE ok IS NOT TRUE);
  END IF;
END $$;
