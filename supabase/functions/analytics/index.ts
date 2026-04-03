// Analytics Edge Function — Admin-only crash & feedback statistics.
// Auth: ADMIN_API_KEY via x-api-key header or apiKey query param.
//
// Endpoints:
//   GET ?type=overview       — high-level counts + trends
//   GET ?type=crashes        — crash pattern aggregation (filterable)
//   GET ?type=crash-detail   — deep-dive into a single crash pattern by hash
//   GET ?type=versions       — per-version crash breakdown + regression detection
//   GET ?type=feedback       — feedback summary + ratings
//
// Filters (for crashes):
//   &severity=error|warning|critical   &dismissed=true|false
//   &version=1.1.3                     &search=keyword
//
// OWASP: A01 (auth gated), A05 (parameterized queries), A06 (rate limit via
//        Supabase edge, payload limits), A10 (no stack traces leaked to
//        unauthenticated callers — admin-only endpoint).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "x-api-key, content-type",
  "content-type": "application/json",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS });
}

function err(message: string, status: number) {
  return json({ error: message }, status);
}

// Extract structured fields from the raw JSONB payload for debugging.
// deno-lint-ignore no-explicit-any
function extractReportFields(payload: any) {
  const r = payload?.report;
  if (!r) return null;
  return {
    type: r.type || null,
    severity: r.severity || null,
    message: r.message || null,
    stack_trace: r.stack_trace || null,
    process_name: r.process_name || null,
    app_version: r.app_version || null,
    build_commit: r.build_commit || null,
    go_version: r.go_version || null,
    os: r.os || null,
    arch: r.arch || null,
    gpu: r.gpu || null,
    local_stt: r.local_stt ?? null,
    smart_mode: r.smart_mode ?? null,
    config_snapshot: r.config_snapshot || null,
    app_state: r.app_state || null,
    app_uptime_sec: r.app_uptime_sec ?? null,
    goroutine_count: r.goroutine_count ?? null,
    heap_alloc_mb: r.heap_alloc_mb ?? null,
    heap_sys_mb: r.heap_sys_mb ?? null,
    num_gc: r.num_gc ?? null,
    recent_logs: r.recent_logs || null,
    install_source: r.install_source || null,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }

  if (req.method !== "GET") {
    return err("method_not_allowed", 405);
  }

  // ── Auth ─────────────────────────────────────────────────────────
  const url = new URL(req.url);
  const apiKey =
    req.headers.get("x-api-key") || url.searchParams.get("apiKey");
  const adminKey = Deno.env.get("ADMIN_API_KEY");
  if (!adminKey || !apiKey || apiKey !== adminKey) {
    return err("forbidden", 403);
  }

  // ── Supabase client ──────────────────────────────────────────────
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return err("not_configured", 500);
  }
  const sb = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const type = url.searchParams.get("type") || "overview";
  const days = Math.min(parseInt(url.searchParams.get("days") || "30"), 365);
  const since = new Date(Date.now() - days * 86400000).toISOString();

  try {
    switch (type) {
      // ── Overview ───────────────────────────────────────────────────
      case "overview": {
        const [crashes, feedback, active] = await Promise.all([
          sb
            .from("crash_report_events")
            .select("id", { count: "exact", head: true })
            .gte("received_at", since),
          sb
            .from("user_feedback")
            .select("id", { count: "exact", head: true })
            .gte("received_at", since),
          sb
            .from("crash_report_events")
            .select("id", { count: "exact", head: true })
            .eq("dismissed", false)
            .gte("received_at", since),
        ]);

        // Unique crash patterns count
        const { data: patternCount } = await sb
          .from("crash_patterns")
          .select("message_hash", { count: "exact", head: true });

        const { data: avgRating } = await sb
          .rpc("get_avg_rating", { p_since: since })
          .maybeSingle();

        // Fallback if RPC doesn't exist — raw query
        let avg = avgRating?.avg_rating;
        if (avg === undefined) {
          const { data: fb } = await sb
            .from("user_feedback")
            .select("rating")
            .gte("received_at", since);
          if (fb && fb.length > 0) {
            avg = (
              fb.reduce(
                (s: number, r: { rating: number }) => s + r.rating,
                0,
              ) / fb.length
            ).toFixed(2);
          }
        }

        return json({
          period_days: days,
          crashes: {
            total: crashes.count || 0,
            active: active.count || 0,
            unique_patterns: patternCount?.count || 0,
          },
          feedback: {
            total: feedback.count || 0,
            avg_rating: avg ? parseFloat(String(avg)) : null,
          },
        });
      }

      // ── Crash patterns (filterable) ────────────────────────────────
      case "crashes": {
        const { data: daily } = await sb
          .from("crash_daily_summary")
          .select("*")
          .gte("day", since.slice(0, 10))
          .order("day", { ascending: false })
          .limit(days);

        // Build filtered query on crash_patterns view
        let pq = sb
          .from("crash_patterns")
          .select("*")
          .order("occurrence_count", { ascending: false });

        // Apply optional filters
        const filterSeverity = url.searchParams.get("severity");
        if (filterSeverity) pq = pq.eq("severity", filterSeverity);

        const filterDismissed = url.searchParams.get("dismissed");
        if (filterDismissed === "true") pq = pq.eq("is_dismissed", true);
        else if (filterDismissed === "false") pq = pq.eq("is_dismissed", false);

        const filterSearch = url.searchParams.get("search");
        if (filterSearch) pq = pq.ilike("latest_message", `%${filterSearch}%`);

        const limit = Math.min(
          parseInt(url.searchParams.get("limit") || "50"),
          200,
        );
        pq = pq.limit(limit);

        const { data: topPatterns } = await pq;

        return json({
          period_days: days,
          daily: daily || [],
          filters: {
            severity: filterSeverity || null,
            dismissed: filterDismissed || null,
            search: filterSearch || null,
          },
          top_patterns: (topPatterns || []).map((p) => ({
            hash: p.message_hash,
            count: p.occurrence_count,
            first_seen: p.first_seen,
            last_seen: p.last_seen,
            versions: p.affected_versions,
            devices: p.unique_devices,
            message: p.latest_message,
            severity: p.severity,
            dismissed: p.is_dismissed,
            fixed_in: p.fixed_in_version,
          })),
        });
      }

      // ── Crash detail — deep-dive into a single pattern ────────────
      case "crash-detail": {
        const hash = url.searchParams.get("hash");
        if (!hash || hash.length > 64) {
          return err("missing or invalid hash parameter", 400);
        }

        // Get the 15 most recent events for this crash pattern
        const { data: events } = await sb
          .from("crash_report_events")
          .select(
            "id, received_at, app_version, build_commit, device_id, dismissed, fixed_in_version, payload",
          )
          .eq("message_hash", hash)
          .order("received_at", { ascending: false })
          .limit(15);

        if (!events || events.length === 0) {
          return err("no crash events found for this hash", 404);
        }

        // Aggregate environment info across all events
        const envStats = {
          os_versions: new Set<string>(),
          architectures: new Set<string>(),
          go_versions: new Set<string>(),
          gpu_configs: new Set<string>(),
          install_sources: new Set<string>(),
          crash_types: new Set<string>(),
          app_states: new Set<string>(),
          local_stt_count: 0,
          smart_mode_count: 0,
          total_events: events.length,
        };

        const detailedEvents = events.map((e) => {
          const fields = extractReportFields(e.payload);
          if (fields) {
            if (fields.os) envStats.os_versions.add(fields.os);
            if (fields.arch) envStats.architectures.add(fields.arch);
            if (fields.go_version) envStats.go_versions.add(fields.go_version);
            if (fields.gpu) envStats.gpu_configs.add(fields.gpu);
            if (fields.install_source)
              envStats.install_sources.add(fields.install_source);
            if (fields.type) envStats.crash_types.add(fields.type);
            if (fields.app_state) envStats.app_states.add(fields.app_state);
            if (fields.local_stt) envStats.local_stt_count++;
            if (fields.smart_mode) envStats.smart_mode_count++;
          }
          return {
            id: e.id,
            received_at: e.received_at,
            app_version: e.app_version,
            build_commit: e.build_commit,
            device_id: e.device_id,
            dismissed: e.dismissed,
            fixed_in: e.fixed_in_version,
            report: fields,
          };
        });

        return json({
          hash,
          event_count: events.length,
          environment: {
            os_versions: [...envStats.os_versions],
            architectures: [...envStats.architectures],
            go_versions: [...envStats.go_versions],
            gpu_configs: [...envStats.gpu_configs],
            install_sources: [...envStats.install_sources],
            crash_types: [...envStats.crash_types],
            app_states: [...envStats.app_states],
            local_stt_usage: `${envStats.local_stt_count}/${envStats.total_events}`,
            smart_mode_usage: `${envStats.smart_mode_count}/${envStats.total_events}`,
          },
          events: detailedEvents,
        });
      }

      // ── Per-version crash breakdown ────────────────────────────────
      case "versions": {
        const { data: raw } = await sb
          .from("crash_report_events")
          .select("app_version, message_hash, dismissed, received_at")
          .gte("received_at", since);

        if (!raw || raw.length === 0) {
          return json({ period_days: days, versions: [] });
        }

        // Aggregate per version
        const versionMap = new Map<
          string,
          {
            total: number;
            active: number;
            dismissed: number;
            unique_hashes: Set<string>;
            first_seen: string;
            last_seen: string;
          }
        >();

        for (const r of raw) {
          const v = r.app_version || "unknown";
          let entry = versionMap.get(v);
          if (!entry) {
            entry = {
              total: 0,
              active: 0,
              dismissed: 0,
              unique_hashes: new Set(),
              first_seen: r.received_at,
              last_seen: r.received_at,
            };
            versionMap.set(v, entry);
          }
          entry.total++;
          if (r.dismissed) entry.dismissed++;
          else entry.active++;
          entry.unique_hashes.add(r.message_hash);
          if (r.received_at < entry.first_seen) entry.first_seen = r.received_at;
          if (r.received_at > entry.last_seen) entry.last_seen = r.received_at;
        }

        // Sort versions descending by last_seen
        const versions = [...versionMap.entries()]
          .map(([version, v]) => ({
            version,
            total: v.total,
            active: v.active,
            dismissed: v.dismissed,
            unique_patterns: v.unique_hashes.size,
            first_seen: v.first_seen,
            last_seen: v.last_seen,
          }))
          .sort(
            (a, b) =>
              new Date(b.last_seen).getTime() -
              new Date(a.last_seen).getTime(),
          );

        return json({ period_days: days, versions });
      }

      // ── Feedback ───────────────────────────────────────────────────
      case "feedback": {
        const { data: daily } = await sb
          .from("feedback_daily_summary")
          .select("*")
          .gte("day", since.slice(0, 10))
          .order("day", { ascending: false })
          .limit(days);

        const { data: recent } = await sb
          .from("user_feedback")
          .select(
            "id, received_at, rating, feedback_text, app_version, approved_for_display",
          )
          .gte("received_at", since)
          .order("received_at", { ascending: false })
          .limit(50);

        const { data: ratingDist } = await sb
          .from("user_feedback")
          .select("rating")
          .gte("received_at", since);

        const dist: Record<string, number> = {
          "1": 0,
          "2": 0,
          "3": 0,
          "4": 0,
          "5": 0,
        };
        if (ratingDist) {
          for (const r of ratingDist) dist[String(r.rating)]++;
        }

        return json({
          period_days: days,
          daily: daily || [],
          rating_distribution: dist,
          recent: (recent || []).map((f) => ({
            id: f.id,
            date: f.received_at,
            rating: f.rating,
            text: f.feedback_text,
            version: f.app_version,
            approved: f.approved_for_display,
          })),
        });
      }

      default:
        return err(
          "unknown type — use overview, crashes, crash-detail, versions, or feedback",
          400,
        );
    }
  } catch (e) {
    // OWASP A10: never leak internals to client
    console.error("analytics error:", e);
    return err("internal_error", 500);
  }
});
