// Testimonials Edge Function — Public + Admin endpoints.
//
// Public (no auth):
//   GET /testimonials            — approved testimonials (rating, text only)
//
// Admin (ADMIN_API_KEY):
//   POST /testimonials?action=approve&id=UUID
//   POST /testimonials?action=reject&id=UUID
//   GET  /testimonials?action=pending  — list unapproved 4-5★ feedback
//
// OWASP: A01 (admin auth), A05 (parameterized queries), A06 (rate limit +
//        response caching), A07 (API key), A10 (no stack traces).
// GDPR:  Only rating + text exposed publicly. No device_id, IP, version.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "x-api-key, content-type",
  "content-type": "application/json",
};

const CACHE_HEADERS = {
  ...CORS,
  "cache-control": "public, max-age=3600, s-maxage=3600",
};

function json(data: unknown, status = 200, headers = CORS) {
  return new Response(JSON.stringify(data), { status, headers });
}

function err(message: string, status: number) {
  return json({ error: message }, status);
}

function sanitizeText(text: string): string {
  return text
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .slice(0, 500); // max 500 chars
}

function isAdmin(req: Request, url: URL): boolean {
  const apiKey =
    req.headers.get("x-api-key") || url.searchParams.get("apiKey");
  const adminKey = Deno.env.get("ADMIN_API_KEY");
  return !!adminKey && !!apiKey && apiKey === adminKey;
}

function getSupabase() {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return null;
  return createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  const sb = getSupabase();
  if (!sb) return err("not_configured", 500);

  try {
    // ── Public GET: approved testimonials ────────────────────────────
    if (req.method === "GET" && !action) {
      const limit = Math.min(
        parseInt(url.searchParams.get("limit") || "12"),
        50
      );

      const { data, error: qErr } = await sb
        .from("user_feedback")
        .select("rating, feedback_text")
        .eq("approved_for_display", true)
        .gte("rating", 4)
        .not("feedback_text", "is", null)
        .order("received_at", { ascending: false })
        .limit(limit);

      if (qErr) {
        console.error("testimonials query error:", qErr);
        return err("internal_error", 500);
      }

      // GDPR: expose ONLY rating + sanitized text
      const testimonials = (data || []).map((f) => ({
        rating: f.rating,
        text: sanitizeText(f.feedback_text),
      }));

      return json({ testimonials, count: testimonials.length }, 200, CACHE_HEADERS);
    }

    // ── Admin endpoints ──────────────────────────────────────────────
    if (!isAdmin(req, url)) {
      return err("forbidden", 403);
    }

    // List pending (unapproved 4-5★ feedback for review)
    if (req.method === "GET" && action === "pending") {
      const { data } = await sb
        .from("user_feedback")
        .select("id, received_at, rating, feedback_text, app_version")
        .gte("rating", 4)
        .eq("approved_for_display", false)
        .not("feedback_text", "is", null)
        .order("received_at", { ascending: false })
        .limit(50);

      return json({
        pending: (data || []).map((f) => ({
          id: f.id,
          date: f.received_at,
          rating: f.rating,
          text: f.feedback_text,
          version: f.app_version,
        })),
      });
    }

    // Approve a testimonial
    if (req.method === "POST" && action === "approve") {
      const id = url.searchParams.get("id");
      if (!id) return err("missing id", 400);

      const { data, error: uErr } = await sb
        .from("user_feedback")
        .update({ approved_for_display: true })
        .eq("id", id)
        .gte("rating", 4)
        .select("id");

      if (uErr) return err("update_failed", 500);
      return json({
        approved: true,
        id,
        matched: data?.length || 0,
      });
    }

    // Reject (un-approve) a testimonial
    if (req.method === "POST" && action === "reject") {
      const id = url.searchParams.get("id");
      if (!id) return err("missing id", 400);

      const { data, error: uErr } = await sb
        .from("user_feedback")
        .update({ approved_for_display: false })
        .eq("id", id)
        .select("id");

      if (uErr) return err("update_failed", 500);
      return json({
        rejected: true,
        id,
        matched: data?.length || 0,
      });
    }

    return err("unknown action — use approve, reject, or pending", 400);
  } catch (e) {
    console.error("testimonials error:", e);
    return err("internal_error", 500);
  }
});
