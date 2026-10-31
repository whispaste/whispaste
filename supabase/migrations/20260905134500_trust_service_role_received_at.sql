-- enforce_feedback_defaults() unconditionally stamped NEW.received_at := now()
-- on every INSERT, regardless of caller. That's the correct anti-spoofing
-- behavior for the anon in-app feedback form (its RLS WITH CHECK on
-- anon_can_insert_feedback never constrains received_at, so an anon client
-- could otherwise submit an arbitrary timestamp) - but it also silently
-- overrode the real historical submission date supplied by
-- tools/testimonials/sync-store-reviews.py, which writes via the Supabase
-- Management API (current_user = 'postgres') specifically to backfill each
-- store review's actual received_at. That collision produced the
-- 2026-09-05 incident: three months-old Microsoft Store reviews (including
-- feedback ID 2e2ff024-a7d6-49fc-b7e0-d22f986c2c34) got stamped with the
-- sync moment instead of their real posting date, then re-stamped with a
-- fresh "now()" on every subsequent sync run because the trigger fires even
-- for INSERT ... ON CONFLICT DO UPDATE (EXCLUDED reflects the BEFORE INSERT
-- trigger's overwritten value, not the caller's original one).
--
-- Fix: only force "now()" for non-service-role callers (PostgREST's anon/
-- authenticated roles). The trusted 'postgres' role (Management API,
-- migrations) may supply its own received_at. Must check session_user, not
-- current_user: this function is SECURITY DEFINER, so current_user inside
-- its body always resolves to the function owner regardless of caller -
-- session_user reflects the actual connecting role (PostgREST always
-- connects as 'authenticator', then SETs ROLE anon/authenticated).
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
