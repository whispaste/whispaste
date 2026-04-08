const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "x-api-key, content-type",
  "content-type": "application/json",
};

// Admin responses: no CORS origin (browser-based admin requests not supported)
const SECURITY_HEADERS = {
  "content-type": "application/json",
  "x-content-type-options": "nosniff",
  "cache-control": "no-store",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: SECURITY_HEADERS });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // Auth ALL actions — header only, no query param (OWASP A02)
  const apiKey = req.headers.get("x-api-key");
  const adminKey = Deno.env.get("ADMIN_API_KEY");
  if (!adminKey || !apiKey || apiKey !== adminKey) {
    return json({ error: "forbidden" }, 403);
  }

  const webhookURL = Deno.env.get("CRASH_DISCORD_WEBHOOK_URL");
  if (!webhookURL) return json({ error: "no webhook" }, 500);

  const match = webhookURL.match(/\/webhooks\/(\d+)\/([A-Za-z0-9_-]+)/);
  if (!match) return json({ error: "bad url" }, 500);
  const [, whId, whToken] = match;

  const url = new URL(req.url);
  const action = url.searchParams.get("action") || "info";

  if (action === "info") {
    // Return only confirmation that webhook is configured, no Discord metadata
    return json({ status: "configured" });
  }

  // Fetch channel info only for actions that need it (after auth)
  const whResp = await fetch("https://discord.com/api/v10/webhooks/" + whId + "/" + whToken);
  const whInfo = await whResp.json();
  const channelId = whInfo.channel_id;

  if (action === "list") {
    const rawLimit = url.searchParams.get("limit") || "50";
    const limit = Math.min(Math.max(1, parseInt(rawLimit, 10) || 50), 100);
    
    const msgs = await fetch(
      "https://discord.com/api/v10/channels/" + channelId + "/messages?limit=" + String(limit),
      { headers: { "Authorization": "Bot " + whToken } }
    );
    
    if (msgs.ok) {
      const data = await msgs.json();
      return json({ source: "bot", messages: data });
    }

    return json({
      error: "cannot_list_messages",
      hint: "Need Discord Bot token to list channel messages."
    }, 403);
  }

  if (action === "delete") {
    const msgId = url.searchParams.get("message_id");
    if (!msgId || !/^\d{17,20}$/.test(msgId)) {
      return json({ error: "missing or invalid message_id" }, 400);
    }
    
    const del = await fetch(
      "https://discord.com/api/v10/webhooks/" + whId + "/" + whToken + "/messages/" + msgId,
      { method: "DELETE" }
    );
    return json({ deleted: del.ok, status: del.status, message_id: msgId });
  }

  if (action === "fix") {
    const hash = url.searchParams.get("hash");
    const version = url.searchParams.get("version");

    // Validate hash: must be 64-char hex string
    if (!hash || !/^[a-f0-9]{64}$/.test(hash)) {
      return json({ error: "invalid hash — must be 64-char hex" }, 400);
    }
    // Validate version: must be semver-like
    if (!version || !/^v?\d+\.\d+\.\d+/.test(version)) {
      return json({ error: "invalid version — must be semver format" }, 400);
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseURL || !serviceRoleKey) {
      return json({ error: "not configured" }, 500);
    }

    const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
    const supabase = createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Mark reports with this hash as fixed (safety cap: 500 rows)
    const { data, error } = await supabase
      .from("crash_report_events")
      .update({
        fixed_in_version: version,
        dismissed: true,
        fixed_at: new Date().toISOString(),
      })
      .eq("message_hash", hash)
      .limit(500)
      .select("id");

    if (error) {
      return json({ error: "update_failed" }, 500);
    }

    return json({
      action: "fixed",
      hash,
      version,
      updated_count: data?.length || 0
    });
  }

  // ── Automated Discord cleanup: delete messages for dismissed/fixed crashes ──
  // action=cleanup — Removes Discord messages for dismissed/old crash reports
  //                  and marks them as cleaned. Respects Discord rate limits.
  // Optional: retention_days (default 30) — also clean feedback messages older than this
  if (action === "cleanup") {
    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseURL || !serviceRoleKey) {
      return json({ error: "not configured" }, 500);
    }
    const { createClient: cc } = await import("https://esm.sh/@supabase/supabase-js@2");
    const sb = cc(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const retentionDays = parseInt(url.searchParams.get("retention_days") || "30");
    const retentionDate = new Date(Date.now() - retentionDays * 86400000).toISOString();
    const batchLimit = 50; // Discord rate limit safety

    let crashesCleaned = 0;
    let feedbackCleaned = 0;
    let errors: string[] = [];

    // 1) Clean dismissed/fixed crash reports that still have Discord messages
    const { data: crashesToClean } = await sb
      .from("crash_report_events")
      .select("id, discord_message_id")
      .eq("dismissed", true)
      .not("discord_message_id", "is", null)
      .is("discord_cleaned_at", null)
      .limit(batchLimit);

    for (const row of (crashesToClean || [])) {
      const del = await fetch(
        "https://discord.com/api/v10/webhooks/" + whId + "/" + whToken + "/messages/" + row.discord_message_id,
        { method: "DELETE" }
      );
      if (del.ok || del.status === 404) {
        await sb.from("crash_report_events")
          .update({ discord_cleaned_at: new Date().toISOString() })
          .eq("id", row.id);
        crashesCleaned++;
      } else {
        errors.push("crash:" + row.id + ":" + del.status);
      }
      // Respect Discord rate limits (~1 req/sec)
      await new Promise(r => setTimeout(r, 1100));
    }

    // 2) Clean old feedback Discord messages (beyond retention period)
    const feedbackWebhookURL = Deno.env.get("FEEDBACK_DISCORD_WEBHOOK_URL");
    if (feedbackWebhookURL) {
      const fbMatch = feedbackWebhookURL.match(/\/webhooks\/(\d+)\/([A-Za-z0-9_-]+)/);
      if (fbMatch) {
        const [, fbWhId, fbWhToken] = fbMatch;

        const { data: feedbackToClean } = await sb
          .from("user_feedback")
          .select("id, discord_message_id")
          .lt("received_at", retentionDate)
          .not("discord_message_id", "is", null)
          .is("discord_cleaned_at", null)
          .limit(batchLimit);

        for (const row of (feedbackToClean || [])) {
          const del = await fetch(
            "https://discord.com/api/v10/webhooks/" + fbWhId + "/" + fbWhToken + "/messages/" + row.discord_message_id,
            { method: "DELETE" }
          );
          if (del.ok || del.status === 404) {
            await sb.from("user_feedback")
              .update({ discord_cleaned_at: new Date().toISOString() })
              .eq("id", row.id);
            feedbackCleaned++;
          } else {
            errors.push("feedback:" + row.id + ":" + del.status);
          }
          await new Promise(r => setTimeout(r, 1100));
        }
      }
    }

    return json({
      action: "cleanup",
      crashes_cleaned: crashesCleaned,
      feedback_cleaned: feedbackCleaned,
      errors: errors.length > 0 ? errors : undefined,
      retention_days: retentionDays,
    });
  }

  return json({ error: "unknown action", actions: ["info", "list", "delete", "fix", "cleanup"] }, 400);
});
