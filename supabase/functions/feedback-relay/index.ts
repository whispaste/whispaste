import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_BODY_BYTES = 8_000;
const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS_HEADERS },
  });
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const webhookURL = Deno.env.get("FEEDBACK_DISCORD_WEBHOOK_URL");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!webhookURL || !supabaseURL || !serviceRoleKey) {
    return json({ error: "relay_not_configured" }, 500);
  }

  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return json({ error: "payload_too_large" }, 413);
  }

  let parsed: {
    rating: number;
    text?: string;
    app_version: string;
    device_id: string;
  };
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  // Validate
  const rating = parsed.rating;
  if (
    typeof rating !== "number" ||
    !Number.isInteger(rating) ||
    rating < 1 ||
    rating > 5
  ) {
    return json(
      { error: "invalid_rating", detail: "must be integer 1-5" },
      400,
    );
  }
  const text =
    typeof parsed.text === "string" ? parsed.text.trim().slice(0, 500) : "";
  const appVersion =
    typeof parsed.app_version === "string"
      ? parsed.app_version.trim().slice(0, 64)
      : "unknown";
  const deviceId =
    typeof parsed.device_id === "string"
      ? parsed.device_id.trim().slice(0, 64)
      : "unknown";

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Rate limit: max 1 feedback per device per 24h
  const forwardedFor = req.headers.get("x-forwarded-for") ?? "";
  const ipHash = await sha256(
    forwardedFor.split(",")[0]?.trim() || "unknown",
  );
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count } = await supabase
    .from("user_feedback")
    .select("*", { count: "exact", head: true })
    .eq("ip_hash", ipHash)
    .gte("received_at", dayAgo);
  if ((count ?? 0) >= 1) {
    return json(
      { error: "rate_limited", detail: "one feedback per 24 hours" },
      429,
    );
  }

  // Build Discord embed
  const stars = "★".repeat(rating) + "☆".repeat(5 - rating);
  const color =
    rating >= 4 ? 0x10b981 : rating >= 3 ? 0xf59e0b : 0xef4444;
  const embed = {
    title: `⭐ User Feedback: ${stars} (${rating}/5)`,
    description: text || "_No text provided_",
    color,
    fields: [
      { name: "Version", value: appVersion, inline: true },
      { name: "Device", value: deviceId.slice(0, 12), inline: true },
    ],
    footer: { text: new Date().toISOString().split("T")[0] },
  };

  // Insert into DB
  const feedbackId = crypto.randomUUID();
  const { error: insertError } = await supabase
    .from("user_feedback")
    .insert({
      id: feedbackId,
      rating,
      feedback_text: text || null,
      app_version: appVersion,
      device_id_hash: deviceId,
      ip_hash: ipHash,
      status: "pending",
    });
  if (insertError) return json({ error: "insert_failed" }, 500);

  // Post to Discord
  const discordURL = webhookURL.includes("?")
    ? `${webhookURL}&wait=true`
    : `${webhookURL}?wait=true`;
  const discordResp = await fetch(discordURL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ embeds: [embed] }),
  });

  let discordMsgId: string | null = null;
  if (discordResp.ok) {
    try {
      const body = await discordResp.json();
      discordMsgId = body.id || null;
    } catch {
      /* ignore */
    }
  }

  await supabase
    .from("user_feedback")
    .update({
      status: discordResp.ok ? "sent" : "discord_failed",
      discord_message_id: discordMsgId,
    })
    .eq("id", feedbackId);

  return json({ status: "sent", id: feedbackId }, 202);
});
