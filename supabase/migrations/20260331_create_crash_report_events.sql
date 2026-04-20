create table if not exists public.crash_report_events (
    id text primary key,
    received_at timestamptz not null default timezone('utc', now()),
    message_hash text not null,
    device_id text not null,
    ip_hash text not null,
    app_version text not null,
    status text not null default 'pending',
    error_detail text null,
    discord_message_id text null,
    payload jsonb not null
);

create index if not exists idx_crash_report_events_received_at
    on public.crash_report_events (received_at desc);

create index if not exists idx_crash_report_events_hash_window
    on public.crash_report_events (message_hash, device_id, received_at desc);

create index if not exists idx_crash_report_events_rate_limit
    on public.crash_report_events (device_id, ip_hash, received_at desc);

revoke all on table public.crash_report_events from anon, authenticated;
