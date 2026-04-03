Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });

  const webhookURL = Deno.env.get("CRASH_DISCORD_WEBHOOK_URL");
  if (!webhookURL) return new Response(JSON.stringify({ error: "no webhook" }), { status: 500 });

  const match = webhookURL.match(/\/webhooks\/(\d+)\/([A-Za-z0-9_-]+)/);
  if (!match) return new Response(JSON.stringify({ error: "bad url" }), { status: 500 });
  const [, whId, whToken] = match;

  // Get channel info
  const whResp = await fetch("https://discord.com/api/v10/webhooks/" + whId + "/" + whToken);
  const whInfo = await whResp.json();
  const channelId = whInfo.channel_id;

  const url = new URL(req.url);
  const action = url.searchParams.get("action") || "info";

  // Authenticate admin actions (fix, delete) via API key
  const requiresAuth = action === "fix" || action === "delete";
  if (requiresAuth) {
    const apiKey = req.headers.get("x-api-key") || url.searchParams.get("apiKey");
    const adminKey = Deno.env.get("ADMIN_API_KEY");
    if (!adminKey || !apiKey || apiKey !== adminKey) {
      return new Response(JSON.stringify({ error: "forbidden" }), { status: 403, headers: { "content-type": "application/json" } });
    }
  }

  if (action === "info") {
    return new Response(JSON.stringify({
      webhook_id: whId,
      channel_id: channelId,
      guild_id: whInfo.guild_id,
      webhook_name: whInfo.name
    }), { headers: { "content-type": "application/json" } });
  }

  if (action === "list") {
    // Try fetching messages via webhook (undocumented, probably fails)
    // Use bot token if available, otherwise try webhook
    const limit = url.searchParams.get("limit") || "50";
    
    // Attempt 1: Use webhook token to list messages (experimental)
    const msgs = await fetch(
      "https://discord.com/api/v10/channels/" + channelId + "/messages?limit=" + limit,
      { headers: { "Authorization": "Bot " + whToken } }
    );
    
    if (msgs.ok) {
      const data = await msgs.json();
      return new Response(JSON.stringify({ source: "bot", messages: data }), { headers: { "content-type": "application/json" } });
    }
    
    // Attempt 2: webhook token as bearer
    const msgs2 = await fetch(
      "https://discord.com/api/v10/channels/" + channelId + "/messages?limit=" + limit,
      { headers: { "Authorization": "Bearer " + whToken } }
    );
    if (msgs2.ok) {
      const data2 = await msgs2.json();
      return new Response(JSON.stringify({ source: "bearer", messages: data2 }), { headers: { "content-type": "application/json" } });
    }

    return new Response(JSON.stringify({
      error: "cannot_list_messages",
      channel_id: channelId,
      bot_status: msgs.status,
      bearer_status: msgs2.status,
      hint: "Need Discord Bot token to list channel messages. Webhook tokens cannot list."
    }), { status: 403, headers: { "content-type": "application/json" } });
  }

  if (action === "delete") {
    const msgId = url.searchParams.get("message_id");
    if (!msgId) return new Response(JSON.stringify({ error: "missing message_id" }), { status: 400 });
    
    const del = await fetch(
      "https://discord.com/api/v10/webhooks/" + whId + "/" + whToken + "/messages/" + msgId,
      { method: "DELETE" }
    );
    return new Response(JSON.stringify({ deleted: del.ok, status: del.status, message_id: msgId }), { headers: { "content-type": "application/json" } });
  }

  if (action === "fix") {
    const hash = url.searchParams.get("hash");
    const version = url.searchParams.get("version");
    if (!hash || !version) {
      return new Response(JSON.stringify({ error: "missing hash or version" }), { status: 400, headers: { "content-type": "application/json" } });
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseURL || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: "not configured" }), { status: 500 });
    }

    const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
    const supabase = createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Mark all reports with this hash as fixed
    const { data, error } = await supabase
      .from("crash_report_events")
      .update({ fixed_in_version: version, dismissed: true })
      .eq("message_hash", hash)
      .select("id");

    if (error) {
      return new Response(JSON.stringify({ error: "update_failed", detail: error.message }), { status: 500, headers: { "content-type": "application/json" } });
    }

    return new Response(JSON.stringify({
      action: "fixed",
      hash,
      version,
      updated_count: data?.length || 0
    }), { headers: { "content-type": "application/json" } });
  }

  // ── Automated Discord cleanup: delete messages for dismissed/fixed crashes ──
  // action=cleanup — Removes Discord messages for dismissed/old crash reports
  //                  and marks them as cleaned. Respects Discord rate limits.
  // Optional: retention_days (default 30) — also clean feedback messages older than this
  if (action === "cleanup") {
    const apiKey = req.headers.get("x-api-key") || url.searchParams.get("apiKey");
    const adminKey = Deno.env.get("ADMIN_API_KEY");
    if (!adminKey || !apiKey || apiKey !== adminKey) {
      return new Response(JSON.stringify({ error: "forbidden" }), { status: 403, headers: { "content-type": "application/json" } });
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseURL || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: "not configured" }), { status: 500 });
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

    return new Response(JSON.stringify({
      action: "cleanup",
      crashes_cleaned: crashesCleaned,
      feedback_cleaned: feedbackCleaned,
      errors: errors.length > 0 ? errors : undefined,
      retention_days: retentionDays,
    }), { headers: { "content-type": "application/json" } });
  }

  return new Response(JSON.stringify({ error: "unknown action", actions: ["info", "list", "delete", "fix", "cleanup"] }), { status: 400 });
});
