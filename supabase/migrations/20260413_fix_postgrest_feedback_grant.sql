-- Fix: PostgREST needs table-level INSERT, not just column-level.
-- Column-level GRANT causes 42501 because PostgREST checks table-level first.

-- Grant table-level INSERT to anon
GRANT INSERT ON public.user_feedback TO anon;

-- Trigger to force server-side defaults and prevent client-side spoofing
CREATE OR REPLACE FUNCTION public.enforce_feedback_defaults()
RETURNS TRIGGER AS $$
BEGIN
  -- Force server-side columns regardless of what the client sent
  NEW.id := gen_random_uuid();
  NEW.received_at := now();
  NEW.ip_hash := NULL;
  NEW.discord_message_id := NULL;
  NEW.status := 'new';
  NEW.approved_for_display := false;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run BEFORE INSERT, BEFORE the rate-limit trigger
DROP TRIGGER IF EXISTS trg_feedback_enforce_defaults ON public.user_feedback;
CREATE TRIGGER trg_feedback_enforce_defaults
  BEFORE INSERT ON public.user_feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_feedback_defaults();
