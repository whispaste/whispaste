-- Migration: a withdrawal also drops the quote and the withdrawal hash (BIZ)
--
-- Until now a withdrawn row kept approved_for_display = true and its
-- withdraw_token_hash. The daily feedback-archival-daily cron (20260417,
-- rescheduled in 20260717) deletes only rows older than 90 days that are NOT
-- approved, so a withdrawn quote and its hash were kept for good.
--
-- Now the withdrawal RPC also clears withdraw_token_hash and sets
-- approved_for_display = false. The row then falls under the existing cron
-- and is deleted once it is older than 90 days, so at the latest 90 days
-- after the withdrawal arrived. public_testimonials already hides it twice
-- over (approved_for_display and publish_consent are both false).
--
-- Idempotent: the RPC matches by hash only. Once the hash is cleared a
-- repeated call matches nothing and still returns without error, so a client
-- retry after a lost response is confirmed like the first call. withdrawn_at
-- keeps the time of the first withdrawal. Rows withdrawn before this
-- migration are cleaned up once below.

CREATE OR REPLACE FUNCTION public.withdraw_feedback_publish_consent(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 OR length(p_token) > 200 THEN
    RETURN;
  END IF;

  UPDATE public.user_feedback
     SET publish_consent = false,
         approved_for_display = false,
         withdraw_token_hash = NULL,
         withdrawn_at = coalesce(withdrawn_at, now())
   WHERE withdraw_token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
END;
$function$;

-- Supabase grants new functions to anon and authenticated by default, so
-- revoking PUBLIC alone is not enough. Only anon (the app) calls the RPC.
REVOKE ALL ON FUNCTION public.withdraw_feedback_publish_consent(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_feedback_publish_consent(text)
  TO anon;

-- The consent trigger function from 20261020100000 is never called by a
-- client, like the other trigger functions (20260612).
REVOKE EXECUTE ON FUNCTION public.stamp_feedback_publish_consent()
  FROM PUBLIC, anon, authenticated;

UPDATE public.user_feedback
   SET approved_for_display = false,
       withdraw_token_hash = NULL
 WHERE withdrawn_at IS NOT NULL
   AND (approved_for_display IS TRUE OR withdraw_token_hash IS NOT NULL);

COMMENT ON COLUMN public.user_feedback.withdraw_token_hash IS
  'sha256 (hex) of the device-held consent secret. Matched by '
  'withdraw_feedback_publish_consent, which clears it on withdrawal. Never '
  'readable by anon.';
