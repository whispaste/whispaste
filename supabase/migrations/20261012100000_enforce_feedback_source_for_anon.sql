-- Security hardening: anon INSERTs must not set provenance or curation fields.
--
-- The anon role holds a table-level INSERT grant on public.user_feedback (see
-- 20260717_add_feedback_contact_email.sql), and the RLS INSERT policy does not
-- constrain `source`, `source_ref` or `curated_text`. Without this trigger an
-- anon client could:
--   - send source = 'mas' / 'microsoft_store' with a crafted source_ref, which
--     occupies the de-dup slot of idx_feedback_source_ref so that a real store
--     review import is silently skipped on the next sync run;
--   - pre-fill curated_text, which public_testimonials displays in preference
--     to feedback_text.
--
-- Fix: for every caller except the trusted 'postgres' role (Management API,
-- migrations, tools/testimonials/sync-store-reviews.py), force the in-app
-- defaults: source = 'in_app', source_ref = NULL, curated_text = NULL. The
-- in-app client never sends these columns (see FeedbackPayload.toJson in
-- lib/services/feedback_submission_service.dart), so legitimate inserts keep
-- working unchanged.
--
-- Same session_user convention as 20260905134500_trust_service_role_received_at
-- (the function is SECURITY DEFINER, so current_user is always the owner).
-- The function body below is the complete previous version plus the new block.

create or replace function public.enforce_feedback_defaults()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  headers_raw text;
  xff         text;
  ip_parts    text[];
  last_ip     text;
begin
  -- Always generate a fresh UUID so callers cannot control the PK.
  new.id := gen_random_uuid();

  -- Only the trusted service role (Management API / migrations) may supply
  -- its own received_at (e.g. backfilling a store review's real submission
  -- date). Every other caller (anon/authenticated via PostgREST) is always
  -- stamped with the real insert time, since RLS does not constrain this
  -- column and a client-supplied value cannot be trusted there.
  if session_user <> 'postgres' or new.received_at is null then
    new.received_at := now();
  end if;

  -- Only the trusted service role may set provenance and curation fields.
  -- Anything else is forced back to the in-app defaults.
  if session_user <> 'postgres' then
    new.source       := 'in_app';
    new.source_ref   := null;
    new.curated_text := null;
  end if;

  -- Extract real client IP from PostgREST forwarded headers when present.
  headers_raw := current_setting('request.headers', true);
  if headers_raw is not null and headers_raw <> '' then
    begin
      xff := (headers_raw::json) ->> 'x-forwarded-for';
      if xff is not null and xff <> '' then
        ip_parts := string_to_array(xff, ',');
        last_ip  := trim(ip_parts[array_length(ip_parts, 1)]);
        if last_ip is not null and last_ip <> '' then
          new.ip_hash := encode(sha256(last_ip::bytea), 'hex');
        end if;
      end if;
    exception when others then
      -- Malformed header: silently ignore, keep caller-supplied ip_hash if any.
      null;
    end;
  end if;

  -- Force safe defaults for moderation fields.
  new.approved_for_display := false;
  new.status               := 'received';

  return new;
end;
$function$;
