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

  return new Response(JSON.stringify({ error: "unknown action", actions: ["info", "list", "delete"] }), { status: 400 });
});
