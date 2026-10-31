-- Migration: feedback-quote-v2 (GS-051, GS-055)
--
-- The v1 consent text told users to withdraw "by writing to us". The app now
-- withdraws with one click on the feedback page (20261020110000), so v2 names
-- that instead. v1 consents stay valid: their rows keep consent_text_version =
-- 'feedback-quote-v1', and nothing is rewritten. The allowlist only grows.
--
-- Additive. No table, column or grant changes: the CHECK constraint and the
-- trigger function accept v2 next to v1. CREATE OR REPLACE keeps the function's
-- privileges from 20261020100000 and 20261020110000.

ALTER TABLE public.user_feedback
  DROP CONSTRAINT IF EXISTS user_feedback_consent_text_version_check;
ALTER TABLE public.user_feedback
  ADD CONSTRAINT user_feedback_consent_text_version_check
  CHECK (consent_text_version IS NULL
         OR consent_text_version IN ('feedback-quote-v1', 'feedback-quote-v2'));

-- Same body as 20261020100000, with v2 added to the allowlist.
CREATE OR REPLACE FUNCTION public.stamp_feedback_publish_consent()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.consent_text_version IS NOT NULL
     AND NEW.consent_text_version NOT IN ('feedback-quote-v1', 'feedback-quote-v2') THEN
    NEW.consent_text_version := NULL;
  END IF;

  NEW.withdrawn_at := NULL;

  IF NEW.publish_consent IS TRUE AND NEW.consent_text_version IS NOT NULL THEN
    NEW.consent_at := now();
  ELSE
    -- No consent without a known text version: the client cannot claim it.
    NEW.publish_consent := false;
    NEW.consent_at := NULL;
    NEW.consent_text_version := NULL;
    NEW.withdraw_token_hash := NULL;
  END IF;
  RETURN NEW;
END;
$function$;
