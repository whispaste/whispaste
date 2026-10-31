-- Replay fix for 20260414, not part of the chain: on a fresh database the views
-- from 20260404 still depend on crash_report_events, so its DROP TABLE in
-- 20260414 fails. Production had them removed before; 20260513 drops them
-- with IF EXISTS anyway.
DROP VIEW IF EXISTS public.crash_patterns;
DROP VIEW IF EXISTS public.crash_daily_summary;
