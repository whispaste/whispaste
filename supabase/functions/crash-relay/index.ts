import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_BODY_BYTES = 32_000;
const MAX_REPORTS_PER_HOUR = 20;
const DEDUP_WINDOW_MS = 60 * 60 * 1000;
const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

type CrashReport = {
  id: string;
  timestamp: number;
  type: string;
  severity: string;
  message: string;
  stack_trace?: string;
  process_name?: string;
  app_version: string;
  build_commit?: string;
  go_version: string;
  os: string;
  arch: string;
  device_id: string;
  gpu: string;
  local_stt: boolean;
  smart_mode: boolean;
  config_snapshot?: string;
  hash: string;
};

type CrashPayload = {
  report: CrashReport;
  embed: {
    title: string;
    description: string;
    color?: number;
    fields?: Array<{ name: string; value: string; inline?: boolean }>;
    footer?: { text?: string };
  };
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS_HEADERS },
  });
}

function requireString(value: unknown, name: string, max = 1024): string {
  if (typeof value !== "string") throw new Error(`${name} must be a string`);
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${name} is required`);
  if (trimmed.length > max) throw new Error(`${name} is too long`);
  return trimmed;
}

function optionalString(value: unknown, name: string, max = 1024): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return requireString(value, name, max);
}

function requireBoolean(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") throw new Error(`${name} must be a boolean`);
  return value;
}

function requireNumber(value: unknown, name: string): number {
  if (typeof value !== "number" || Number.isNaN(value)) throw new Error(`${name} must be a number`);
  return value;
}

function sanitizeEmbed(payload: CrashPayload["embed"]) {
  const fields = Array.isArray(payload.fields) ? payload.fields.slice(0, 12).map((field) => ({
    name: requireString(field?.name, "embed.fields.name", 128),
    value: requireString(field?.value, "embed.fields.value", 1024),
    inline: Boolean(field?.inline),
  })) : [];

  return {
    title: requireString(payload.title, "embed.title", 256),
    description: requireString(payload.description, "embed.description", 1024),
    color: typeof payload.color === "number" ? payload.color : 16711680,
    fields,
    footer: payload.footer?.text ? { text: requireString(payload.footer.text, "embed.footer.text", 256) } : undefined,
  };
}

function sanitizeReport(report: CrashPayload["report"]): CrashReport {
  return {
    id: requireString(report.id, "report.id", 80),
    timestamp: requireNumber(report.timestamp, "report.timestamp"),
    type: requireString(report.type, "report.type", 64),
    severity: requireString(report.severity, "report.severity", 64),
    message: requireString(report.message, "report.message", 1024),
    stack_trace: optionalString(report.stack_trace, "report.stack_trace", 2048),
    process_name: optionalString(report.process_name, "report.process_name", 128),
    app_version: requireString(report.app_version || "dev", "report.app_version", 64),
    build_commit: optionalString(report.build_commit, "report.build_commit", 64),
    go_version: requireString(report.go_version, "report.go_version", 64),
    os: requireString(report.os, "report.os", 32),
    arch: requireString(report.arch, "report.arch", 32),
    device_id: requireString(report.device_id, "report.device_id", 64),
    gpu: requireString(report.gpu || "auto", "report.gpu", 64),
    local_stt: requireBoolean(report.local_stt, "report.local_stt"),
    smart_mode: requireBoolean(report.smart_mode, "report.smart_mode"),
    config_snapshot: optionalString(report.config_snapshot, "report.config_snapshot", 1024),
    hash: requireString(report.hash, "report.hash", 64),
  };
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const webhookURL = Deno.env.get("CRASH_DISCORD_WEBHOOK_URL");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!webhookURL || !supabaseURL || !serviceRoleKey) {
    return json({ error: "relay_not_configured" }, 500);
  }

  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return json({ error: "payload_too_large" }, 413);
  }

  let parsed: CrashPayload;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  let report: CrashReport;
  let embed: ReturnType<typeof sanitizeEmbed>;
  try {
    report = sanitizeReport(parsed.report);
    embed = sanitizeEmbed(parsed.embed);
  } catch (error) {
    return json({ error: "invalid_payload", detail: error instanceof Error ? error.message : String(error) }, 400);
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const now = new Date();
  const hourAgo = new Date(now.getTime() - DEDUP_WINDOW_MS).toISOString();
  const forwardedFor = req.headers.get("x-forwarded-for") ?? "";
  const ipHash = await sha256(forwardedFor.split(",")[0]?.trim() || "unknown");

  const { data: duplicateRows, error: duplicateError } = await supabase
    .from("crash_report_events")
    .select("id")
    .eq("message_hash", report.hash)
    .eq("device_id", report.device_id)
    .gte("received_at", hourAgo)
    .limit(1);
  if (duplicateError) return json({ error: "dedup_query_failed" }, 500);
  if (duplicateRows && duplicateRows.length > 0) {
    return json({ status: "duplicate" }, 202);
  }

  const { count, error: rateError } = await supabase
    .from("crash_report_events")
    .select("*", { count: "exact", head: true })
    .or(`device_id.eq.${report.device_id},ip_hash.eq.${ipHash}`)
    .gte("received_at", hourAgo);
  if (rateError) return json({ error: "rate_limit_query_failed" }, 500);
  if ((count ?? 0) >= MAX_REPORTS_PER_HOUR) {
    return json({ error: "rate_limited" }, 429);
  }

  const eventRow = {
    id: report.id,
    received_at: now.toISOString(),
    message_hash: report.hash,
    device_id: report.device_id,
    ip_hash: ipHash,
    app_version: report.app_version,
    status: "pending",
    payload: { report, embed },
  };
  const { error: insertError } = await supabase.from("crash_report_events").insert(eventRow);
  if (insertError) return json({ error: "event_insert_failed" }, 500);

  const discordResp = await fetch(webhookURL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ embeds: [embed], wait: true }),
  });
  if (!discordResp.ok) {
    const detail = await discordResp.text();
    await supabase
      .from("crash_report_events")
      .update({ status: "discord_failed", error_detail: detail.slice(0, 500) })
      .eq("id", report.id);
    return json({ error: "discord_post_failed", detail: detail.slice(0, 200) }, 502);
  }

  const discordBody = await discordResp.json().catch(() => null);
  await supabase
    .from("crash_report_events")
    .update({
      status: "sent",
      discord_message_id: typeof discordBody?.id === "string" ? discordBody.id : null,
    })
    .eq("id", report.id);

  return json({ status: "sent", id: report.id, discord_message_id: discordBody?.id ?? null }, 202);
});
