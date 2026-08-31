-- Extend user_feedback to also hold curated store reviews (Mac App Store,
-- Microsoft Store), synced by tools/testimonials/sync-store-reviews.py,
-- alongside the existing in-app feedback form. Both flow through the same
-- approval/curation pipeline (approved_for_display, curated_text) added in
-- earlier migrations — no change there. Store reviews get the exact same
-- anonymous treatment as in-app feedback: no reviewer name or country is
-- ever stored or displayed, only rating + text.

ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'in_app'
    CHECK (source IN ('in_app', 'mas', 'microsoft_store')),
  ADD COLUMN IF NOT EXISTS source_ref text;

COMMENT ON COLUMN public.user_feedback.source IS
  'Origin of this row: in_app (existing feedback form, via anon INSERT), '
  'mas (Mac App Store customer review), microsoft_store (Microsoft Store '
  'review). Both store sources are written by tools/testimonials/'
  'sync-store-reviews.py via the Supabase Management API, not by anon.';

COMMENT ON COLUMN public.user_feedback.source_ref IS
  'External review identifier (Apple review id, or a content hash for '
  'Microsoft Store reviews which expose no stable id) — used to '
  'de-duplicate repeated sync runs. NULL for in_app rows.';

-- Store reviews carry no device/app-version telemetry — relax the two
-- columns the in-app anon INSERT policy still requires NOT NULL for.
ALTER TABLE public.user_feedback ALTER COLUMN device_id_hash DROP NOT NULL;
ALTER TABLE public.user_feedback ALTER COLUMN app_version DROP NOT NULL;

-- De-dup guard: a re-run of the sync script must not insert the same store
-- review twice. Partial + on source_ref so in_app rows (source_ref NULL)
-- are never compared against each other.
CREATE UNIQUE INDEX IF NOT EXISTS idx_feedback_source_ref
  ON public.user_feedback (source, source_ref)
  WHERE source_ref IS NOT NULL;
