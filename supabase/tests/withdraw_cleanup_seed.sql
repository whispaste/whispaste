-- Rows in place before 20261020110000: one live quote with consent, one
-- quote withdrawn under the old RPC (still approved, hash kept), and one
-- approved store review that no withdrawal may touch.

INSERT INTO public.user_feedback
  (rating, feedback_text, app_version, device_id_hash, source,
   publish_consent, consent_text_version, withdraw_token_hash, received_at)
VALUES
  (5, 'live quote', '1.4.0', 'dev-live', 'in_app', true, 'feedback-quote-v1',
   encode(sha256(convert_to('live-secret-0123456789', 'UTF8')), 'hex'),
   now() - interval '10 days'),
  (5, 'old withdrawn quote', '1.4.0', 'dev-old', 'in_app', true,
   'feedback-quote-v1',
   encode(sha256(convert_to('old-secret-0123456789', 'UTF8')), 'hex'),
   now() - interval '200 days'),
  (5, 'store review', '1.4.0', 'dev-store', 'mas', false, NULL, NULL,
   now() - interval '200 days');

-- Curation by the operator.
UPDATE public.user_feedback SET approved_for_display = true;

-- Withdrawal under the old RPC: consent off, approval and hash kept.
SET ROLE anon;
SELECT public.withdraw_feedback_publish_consent('old-secret-0123456789');
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.user_feedback
     WHERE device_id_hash = 'dev-old' AND withdrawn_at IS NOT NULL
       AND approved_for_display AND withdraw_token_hash IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'seed: the old RPC should leave approval and hash';
  END IF;
END $$;
