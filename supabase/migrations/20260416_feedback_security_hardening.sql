-- Migration: Feedback Security Hardening
--
-- Addresses three HIGH-risk attack vectors identified in security analysis:
--
--   P1 (Storage Exhaustion)  — global row cap: max 10,000 rows
--   P2 (IP Rate-Limiting)    — populate ip_hash from PostgREST request headers;
--                              add trigger: max 5 submissions per IP per 24 hours
--   P3 (CRON Archival)       — delete rows older than 90 days (daily, 04:00 UTC)
--   +  Char-limit reduction  — feedback_text: 2,000 → 1,000 characters
--
-- Trigger execution order (alphabetical by trigger name):
--   1. trg_feedback_cap_check        ('c') — global row cap
--   2. trg_feedback_enforce_defaults ('e') — sets id, timestamps, ip_hash
--   3. trg_feedback_ip_rate_limit    ('i') — IP rate limit  (5/IP/24h)
--   4. trg_feedback_rate_limit       ('r') — device rate limit (3/device/24h)

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Reduce feedback_text limit: 2,000 → 1,000 chars
--    Update the RLS INSERT policy (defense-in-depth together with maxLength
--    enforced in the Flutter UI via TextField.maxLength = 1000).
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "anon_can_insert_feedback" ON public.user_feedback;

CREATE POLICY "anon_can_insert_feedback"
  ON public.user_feedback
  FOR INSERT TO anon
  WITH CHECK (
    rating >= 1 AND rating <= 5
    AND (feedback_text IS NULL OR length(feedback_text) <= 1000)
    AND app_version IS NOT NULL AND length(app_version) <= 20
    AND device_id_hash IS NOT NULL AND length(device_id_hash) = 12
    AND category IS NOT NULL AND category IN ('bug', 'feature', 'general', 'ai')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. P1: Global row cap — max 10,000 rows
--    Uses EXISTS OFFSET 9999 LIMIT 1 (O(1) via index seek) rather than
--    COUNT(*) (full table scan under MVCC). Trigger name 'c' runs FIRST.
--
--    Note: This check is a soft cap — concurrent inserts can race past it if
--    submitted simultaneously. That is an accepted tradeoff for a low-volume
--    feedback form; we don't need advisory locks here.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_feedback_global_cap()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_feedback OFFSET 9999 LIMIT 1) THEN
    RAISE EXCEPTION 'storage_cap_reached: feedback storage limit exceeded'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_feedback_cap_check ON public.user_feedback;
CREATE TRIGGER trg_feedback_cap_check
  BEFORE INSERT ON public.user_feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.check_feedback_global_cap();

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. P2a: Populate ip_hash from PostgREST request headers
--    Replaces enforce_feedback_defaults() with an extended version that
--    reads the x-forwarded-for header and populates ip_hash.
--
--    Security: always use the LAST xff entry (appended by Supabase's edge
--    proxy — not client-controlled). The first entry is client-provided.
--
--    Trigger name 'e' runs AFTER 'c' (cap) and BEFORE 'i' (IP rate limit).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_feedback_defaults()
RETURNS TRIGGER AS $$
DECLARE
  headers_raw text;
  xff         text;
  ip_parts    text[];
  last_ip     text;
BEGIN
  -- Force server-side columns regardless of what the client sent.
  NEW.id                   := gen_random_uuid();
  NEW.received_at          := now();
  NEW.discord_message_id   := NULL;
  NEW.status               := 'new';
  NEW.approved_for_display := false;

  -- Populate ip_hash from the LAST x-forwarded-for entry.
  -- Falls back to NULL on any error (e.g., direct DB access, missing header).
  BEGIN
    headers_raw := current_setting('request.headers', true);
    IF headers_raw IS NOT NULL AND headers_raw <> '' THEN
      xff := (headers_raw::json)->>'x-forwarded-for';
      IF xff IS NOT NULL AND xff <> '' THEN
        ip_parts := string_to_array(xff, ',');
        last_ip  := trim(ip_parts[array_length(ip_parts, 1)]);
        IF last_ip <> '' THEN
          NEW.ip_hash := encode(sha256(last_ip::bytea), 'hex');
        ELSE
          NEW.ip_hash := NULL;
        END IF;
      ELSE
        NEW.ip_hash := NULL;
      END IF;
    ELSE
      NEW.ip_hash := NULL;
    END IF;
  EXCEPTION WHEN invalid_text_representation THEN
    -- headers_raw is not valid JSON (e.g., malformed header value from proxy).
    -- Any other exception propagates normally and causes the insert to fail.
    NEW.ip_hash := NULL;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- trg_feedback_enforce_defaults already exists (created in 20260413).
-- The function is replaced in-place; no need to recreate the trigger.

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. P2b: IP rate-limiting trigger — max 5 submissions per IP per 24 hours
--    Runs AFTER trg_feedback_enforce_defaults sets ip_hash ('e' < 'i').
--    If ip_hash is NULL (non-PostgREST access), skips the check silently.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_feedback_ip_rate_limit()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.ip_hash IS NOT NULL AND (
    SELECT count(*)
    FROM   public.user_feedback
    WHERE  ip_hash    = NEW.ip_hash
    AND    received_at > now() - interval '24 hours'
  ) >= 5 THEN
    RAISE EXCEPTION 'rate_limited: max 5 feedback submissions per IP per 24 hours'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_feedback_ip_rate_limit ON public.user_feedback;
CREATE TRIGGER trg_feedback_ip_rate_limit
  BEFORE INSERT ON public.user_feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.check_feedback_ip_rate_limit();

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. P3: Daily CRON archival — delete rows older than 90 days
--    Uses pg_cron (already enabled, see 20260406_discord_cleanup_cron.sql).
--    Runs daily at 04:00 UTC — 1 hour after the Discord cleanup job (03:00).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'feedback-archival-daily') THEN
    PERFORM cron.unschedule('feedback-archival-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'feedback-archival-daily',
  '0 4 * * *',
  $$DELETE FROM public.user_feedback WHERE received_at < now() - interval '90 days';$$
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Index for IP rate-limit query
--    Partial index (WHERE ip_hash IS NOT NULL) — only rows with a hash are
--    ever queried by check_feedback_ip_rate_limit. Keeps the index lean.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_feedback_ip_hash_received
  ON public.user_feedback (ip_hash, received_at DESC)
  WHERE ip_hash IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Trigger ordering assertion
--    Guards against future migrations accidentally changing trigger names
--    and breaking the alphabetical execution order that this file depends on.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  ASSERT (
    SELECT count(*)
    FROM pg_trigger
    WHERE tgrelid = 'public.user_feedback'::regclass
    AND tgname IN (
      'trg_feedback_cap_check',
      'trg_feedback_enforce_defaults',
      'trg_feedback_ip_rate_limit',
      'trg_feedback_rate_limit'
    )
  ) = 4,
  'user_feedback trigger set mismatch — check trigger names; alphabetical ordering c→e→i→r must be preserved';
END $$;
