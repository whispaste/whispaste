// Analytics Edge Function — Admin-only feedback statistics.
// Auth: ADMIN_API_KEY via x-api-key header only (query param removed for OWASP A02).
//
// Endpoints:
//   GET ?type=overview       — high-level counts + trends
//   GET ?type=feedback       — feedback summary + ratings + recent entries
//   GET ?type=crashes        — stub (crash data migrated to Sentry after v1.1.x)
//   GET ?type=crash-detail   — stub (see above)
//   GET ?type=versions       — stub (see above)
//
// Security: A01 (auth gated), A02 (header-only auth), A05 (parameterized queries),
//           A10 (no internals leaked).
//
// Note: crash_report_events, crash_patterns, crash_daily_summary tables were
// dropped in migration 20260414 when crash reporting moved to Sentry.
// The crash-* endpoints now return empty stubs with a migration_note field.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "x-api-key, content-type",
  "content-type": "application/json",
  "x-content-type-options": "nosniff",
  "cache-control": "no-store",
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

  // ── Auth — header only, no query param (OWASP A02) ─────────────
  const apiKey = req.headers.get("x-api-key");
  const adminKey = Deno.env.get("ADMIN_API_KEY");
  if (!adminKey || !apiKey || apiKey !== adminKey) {
    return err("forbidden", 403);
  }

  // ── Supabase client ──────────────────────────────────────────────
  const url = new URL(req.url);
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

  // Crash-related endpoints return a stub — crash data lives in Sentry.
  // Tables crash_report_events / crash_patterns / crash_daily_summary were
  // dropped in migration 20260414.
  const CRASH_STUB = {
    migration_note:
      "Crash data was migrated to Sentry (https://sentry.io) in v1.1.x. " +
      "Use Sentry dashboards or API for crash analytics.",
  };

  try {
    switch (type) {
      // ── Overview ───────────────────────────────────────────────────
      case "overview": {
        const [feedbackTotal, feedbackPeriod] = await Promise.all([
          sb
            .from("user_feedback")
            .select("id", { count: "exact", head: true }),
          sb
            .from("user_feedback")
            .select("id", { count: "exact", head: true })
            .gte("received_at", since),
        ]);

        // Compute average rating for the period
        const { data: ratingRows } = await sb
          .from("user_feedback")
          .select("rating")
          .gte("received_at", since);

        let avgRating: number | null = null;
        if (ratingRows && ratingRows.length > 0) {
          const sum = ratingRows.reduce(
            (s: number, r: { rating: number }) => s + r.rating,
            0,
          );
          avgRating = parseFloat((sum / ratingRows.length).toFixed(2));
        }

        return json({
          period_days: days,
          feedback: {
            total_all_time: feedbackTotal.count || 0,
            total_period: feedbackPeriod.count || 0,
            avg_rating: avgRating,
          },
          crashes: CRASH_STUB,
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

      // ── Crash stubs (data lives in Sentry) ────────────────────────
      case "crashes":
        return json({ period_days: days, ...CRASH_STUB, data: [] });

      case "crash-detail":
        return json({ ...CRASH_STUB, events: [] });

      case "versions":
        return json({ period_days: days, ...CRASH_STUB, versions: [] });

      default:
        return err(
          "unknown type — use overview, feedback, crashes, crash-detail, or versions",
          400,
        );
    }
  } catch (e) {
    // OWASP A10: never leak internals to client
    console.error("analytics error:", e);
    return err("internal_error", 500);
  }
});
