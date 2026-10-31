-- Explicit opt-in for quoting in-app feedback on the website (growth review
-- R-05), with a recorded consent and a device-held withdrawal (BIZ-63, GS-051,
-- GS-054, GS-055).
--
-- The in-app form sends publish_consent = true only when the user ticks the
-- checkbox; the default is false. Store reviews (source mas / microsoft_store)
-- are not affected and keep the curation pipeline (R-07 unchanged). Existing
-- in_app rows get publish_consent = false and stop appearing in
-- public_testimonials until they are re-confirmed.
--
-- Curation still applies: approved_for_display stays the human gate, and the
-- trigger enforce_feedback_defaults still forces it to false for anon inserts.
--
-- Consent record: the client may only request consent. The database stamps
-- consent_at, accepts only an allowlisted consent_text_version, and sets
-- withdrawn_at on withdrawal. consent_at stays as evidence.
--
-- Withdrawal: the app keeps a random 256-bit secret per consent on the device
-- and sends only its SHA-256 (withdraw_token_hash). The RPC takes the plain
-- secret, hashes it and clears the consent of the matching row. anon has no
-- SELECT and no UPDATE, so a hash or a secret cannot be read back.
--
-- No table-level change for anon beyond the existing INSERT (20260717). The
-- column grant for withdraw_token_hash is explicit; the guard test replays all
-- grants on user_feedback in file order.

ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS publish_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS consent_text_version text
    CHECK (consent_text_version IS NULL
           OR consent_text_version IN ('feedback-quote-v1')),
  ADD COLUMN IF NOT EXISTS withdraw_token_hash text
    CHECK (withdraw_token_hash IS NULL OR withdraw_token_hash ~ '^[0-9a-f]{64}$'),
  ADD COLUMN IF NOT EXISTS withdrawn_at timestamptz;

GRANT INSERT (withdraw_token_hash) ON public.user_feedback TO anon;

COMMENT ON COLUMN public.user_feedback.publish_consent IS
  'Explicit user opt-in to show this in-app feedback anonymously as a quote '
  '(growth review R-05). Required for source = in_app in public_testimonials. '
  'Not applicable to store reviews.';
COMMENT ON COLUMN public.user_feedback.withdraw_token_hash IS
  'sha256 (hex) of the device-held consent secret. Matched by '
  'withdraw_feedback_publish_consent. Never readable by anon.';
COMMENT ON COLUMN public.user_feedback.withdrawn_at IS
  'Time the publish consent was withdrawn in-app. consent_at is kept as evidence.';

-- Stamps the consent time, validates the text version and forces the consent
-- fields on insert. Anon cannot set withdrawn_at: it is forced to NULL.
-- An unknown consent_text_version is silently set to NULL instead of failing
-- the insert, so the feedback is kept but stored without consent.
CREATE OR REPLACE FUNCTION public.stamp_feedback_publish_consent()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.consent_text_version IS NOT NULL
     AND NEW.consent_text_version NOT IN ('feedback-quote-v1') THEN
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

DROP TRIGGER IF EXISTS trg_feedback_publish_consent ON public.user_feedback;
CREATE TRIGGER trg_feedback_publish_consent
  BEFORE INSERT ON public.user_feedback
  FOR EACH ROW EXECUTE FUNCTION public.stamp_feedback_publish_consent();

-- Same view definition as 20260904144233, with the consent condition added.
-- The column list is unchanged, so CREATE OR REPLACE is allowed.
CREATE OR REPLACE VIEW public.public_testimonials
WITH (security_invoker = false)
AS
SELECT
    rating,
    left(coalesce(curated_text, feedback_text), 500) AS text,
    received_at
FROM public.user_feedback
WHERE approved_for_display = true
  AND feedback_text IS NOT NULL
  AND (rating >= 4 OR curated_text IS NOT NULL)
  AND (source <> 'in_app' OR publish_consent = true);

GRANT SELECT ON public.public_testimonials TO anon;

COMMENT ON VIEW public.public_testimonials IS
    'GDPR-safe public view of approved testimonials. In-app feedback requires '
    'explicit publish_consent; store reviews keep the curation rules. Uncurated '
    'feedback needs rating >= 4; a curated_text bypasses the rating gate. No '
    'PII columns exposed.';

-- Withdraws the consent of the row whose secret hashes to withdraw_token_hash.
-- Returns nothing whether or not a row matched, so the caller cannot learn
-- whether a token exists. Any older overload is dropped first.
DROP FUNCTION IF EXISTS public.withdraw_feedback_publish_consent(text[]);
DROP FUNCTION IF EXISTS public.withdraw_feedback_publish_consent(text);

CREATE FUNCTION public.withdraw_feedback_publish_consent(p_token text)
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
         withdrawn_at = now()
   WHERE withdraw_token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND publish_consent = true;
END;
$function$;

REVOKE ALL ON FUNCTION public.withdraw_feedback_publish_consent(text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.withdraw_feedback_publish_consent(text)
  TO anon;
