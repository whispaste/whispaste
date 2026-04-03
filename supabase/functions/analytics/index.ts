// Analytics Edge Function — Admin-only crash & feedback statistics.
// Auth: ADMIN_API_KEY via x-api-key header or apiKey query param.
//
// Endpoints:
//   GET ?type=overview   — high-level counts + trends
//   GET ?type=crashes    — crash pattern aggregation
//   GET ?type=feedback   — feedback summary + ratings
//
// OWASP: A01 (auth gated), A05 (parameterized queries), A06 (rate limit via
//        Supabase edge, payload limits), A10 (no stack traces leaked).

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
        const [crashes, feedback, patterns] = await Promise.all([
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

        const { data: avgRating } = await sb.rpc("get_avg_rating", {
          p_since: since,
        }).maybeSingle();

        // Fallback if RPC doesn't exist — raw query
        let avg = avgRating?.avg_rating;
        if (avg === undefined) {
          const { data: fb } = await sb
            .from("user_feedback")
            .select("rating")
            .gte("received_at", since);
          if (fb && fb.length > 0) {
            avg = (
              fb.reduce((s: number, r: { rating: number }) => s + r.rating, 0) /
              fb.length
            ).toFixed(2);
          }
        }

        return json({
          period_days: days,
          crashes: {
            total: crashes.count || 0,
            active: patterns.count || 0,
          },
          feedback: {
            total: feedback.count || 0,
            avg_rating: avg ? parseFloat(String(avg)) : null,
          },
        });
      }

      // ── Crash patterns ─────────────────────────────────────────────
      case "crashes": {
        const { data: daily } = await sb
          .from("crash_daily_summary")
          .select("*")
          .gte("day", since.slice(0, 10))
          .order("day", { ascending: false })
          .limit(days);

        const { data: topPatterns } = await sb
          .from("crash_patterns")
          .select("*")
          .order("occurrence_count", { ascending: false })
          .limit(20);

        return json({
          period_days: days,
          daily: daily || [],
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
            "id, received_at, rating, feedback_text, app_version, approved_for_display"
          )
          .gte("received_at", since)
          .order("received_at", { ascending: false })
          .limit(50);

        const { data: ratingDist } = await sb
          .from("user_feedback")
          .select("rating")
          .gte("received_at", since);

        // Compute rating distribution
        const dist: Record<string, number> = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
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
        return err("unknown type — use overview, crashes, or feedback", 400);
    }
  } catch (e) {
    // OWASP A10: never leak internals to client
    console.error("analytics error:", e);
    return err("internal_error", 500);
  }
});
