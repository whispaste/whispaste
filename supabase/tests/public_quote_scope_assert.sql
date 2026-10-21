-- Assertions after 20261021100000 (run as the superuser).
-- Only praise-like feedback and store reviews may appear as quotes: bug
-- reports (category bug) and feature wishes (category feature) never do, even
-- when a client sends publish_consent for them. Rolled back, so the rows never
-- reach the checks that follow.
BEGIN;

DO $$
DECLARE
  visible text;
BEGIN
  INSERT INTO public.user_feedback
    (rating, feedback_text, app_version, device_id_hash, source, source_ref,
     category, publish_consent, consent_text_version, approved_for_display,
     received_at)
  VALUES
    (5, 'scope praise', '1.4.0', 'scope-a', 'in_app', NULL,
     'general', true, 'feedback-quote-v2', true, now()),
    (5, 'scope bug', '1.4.0', 'scope-b', 'in_app', NULL,
     'bug', true, 'feedback-quote-v2', true, now()),
    (5, 'scope feature', '1.4.0', 'scope-c', 'in_app', NULL,
     'feature', true, 'feedback-quote-v2', true, now()),
    (5, 'scope store', '1.4.0', 'scope-d', 'mas', 'scope-store-1',
     NULL, false, NULL, true, now());

  -- The insert trigger resets approved_for_display, so the curator's
  -- approval is set afterwards, as a curator would do it.
  UPDATE public.user_feedback SET approved_for_display = true
   WHERE device_id_hash LIKE 'scope-%';

  SELECT string_agg(text, ',' ORDER BY text) INTO visible
    FROM public.public_testimonials
   WHERE text LIKE 'scope %';

  IF visible IS DISTINCT FROM 'scope praise,scope store' THEN
    RAISE EXCEPTION 'public quotes show the wrong rows: %', visible;
  END IF;
  RAISE NOTICE 'public quote scope: praise and store reviews only';
END
$$;

ROLLBACK;
