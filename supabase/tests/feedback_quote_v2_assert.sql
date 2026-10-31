-- The consent allowlist after 20261020120000: v1 and v2 are stamped with
-- consent_at, an unknown text version drops the consent. Rolled back, so the
-- rows never reach the checks that follow.
BEGIN;

DO $$
DECLARE
  v1_at timestamptz;
  v2_at timestamptz;
  bad_version text;
  bad_consent boolean;
BEGIN
  INSERT INTO public.user_feedback
    (rating, feedback_text, app_version, device_id_hash, source,
     publish_consent, consent_text_version, received_at)
  VALUES
    (4, 'v1 quote', '1.4.0', 'dev-v1', 'in_app', true, 'feedback-quote-v1', now()),
    (4, 'v2 quote', '1.4.0', 'dev-v2', 'in_app', true, 'feedback-quote-v2', now()),
    (4, 'unknown quote', '1.4.0', 'dev-x', 'in_app', true, 'feedback-quote-v9', now());

  SELECT consent_at INTO v1_at FROM public.user_feedback WHERE feedback_text = 'v1 quote';
  SELECT consent_at INTO v2_at FROM public.user_feedback WHERE feedback_text = 'v2 quote';
  SELECT consent_text_version, publish_consent INTO bad_version, bad_consent
    FROM public.user_feedback WHERE feedback_text = 'unknown quote';

  IF v1_at IS NULL THEN RAISE EXCEPTION 'v1 consent was not stamped'; END IF;
  IF v2_at IS NULL THEN RAISE EXCEPTION 'v2 consent was not stamped'; END IF;
  IF bad_version IS NOT NULL OR bad_consent IS NOT FALSE THEN
    RAISE EXCEPTION 'unknown consent version was accepted';
  END IF;
  RAISE NOTICE 'feedback-quote-v2 allowlist: all checks passed';
END
$$;

ROLLBACK;
