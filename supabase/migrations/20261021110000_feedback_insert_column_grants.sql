-- Narrows the anon INSERT on user_feedback to the columns the app writes.
--
-- 20260717 gave anon a table-level INSERT, so every column was writable. The
-- row-level policy and the triggers constrain values, but not which columns
-- a client may set: a column-level grant is checked before any trigger runs.
-- This migration removes the table-level INSERT and keeps exactly the columns
-- that FeedbackPayload.toJson() sends (lib/services/feedback_submission_service.dart):
--
--   rating, feedback_text, category, app_version, device_id_hash, locale,
--   contact_email, contact_locale, publish_consent, consent_text_version,
--   withdraw_token_hash
--
-- publish_consent and consent_text_version had no column grant before; the
-- app sent them only because the table-level grant covered them, so they are
-- granted explicitly here. Server-side fields (id, received_at, source,
-- source_ref, curated_text, status, approved_for_display, ip_hash, consent_at,
-- withdrawn_at) are not granted: the triggers set them as the definer.
--
-- Additive: no column, policy or view changes. Authenticated has no INSERT
-- privilege on user_feedback already (privileges_assert), so the revoke is a
-- no-op there and only makes the intent explicit.

REVOKE INSERT ON public.user_feedback FROM anon, authenticated;

GRANT INSERT (
  rating, feedback_text, category, app_version, device_id_hash, locale,
  contact_email, contact_locale, publish_consent, consent_text_version,
  withdraw_token_hash
) ON public.user_feedback TO anon;
