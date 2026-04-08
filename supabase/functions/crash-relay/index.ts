import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function compareVersions(a: string, b: string): number {
  // Handle "dev" as always-lowest
  const aIsDev = a.toLowerCase() === "dev";
  const bIsDev = b.toLowerCase() === "dev";
  if (aIsDev && bIsDev) return 0;
  if (aIsDev) return -1;
  if (bIsDev) return 1;

  // Strip 'v' prefix and split off pre-release
  const aCore = a.replace(/^v/, '').split(/[-+]/)[0];
  const bCore = b.replace(/^v/, '').split(/[-+]/)[0];
  const aParts = aCore.split('.').map(Number);
  const bParts = bCore.split('.').map(Number);

  const len = Math.max(aParts.length, bParts.length);
  for (let i = 0; i < len; i++) {
    const av = aParts[i] || 0;
    const bv = bParts[i] || 0;
    if (av !== bv) return av > bv ? 1 : -1;
  }

  // Same numeric version — pre-release is lower than release
  const aHasPre = a.includes('-');
  const bHasPre = b.includes('-');
  if (aHasPre && !bHasPre) return -1;
  if (!aHasPre && bHasPre) return 1;
  return 0;
}

const MAX_BODY_BYTES = 32_000;
const MAX_REPORTS_PER_HOUR = 20;
const DEDUP_WINDOW_MS = 60 * 60 * 1000;
const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

const SENSITIVE_PATTERNS = [
  /["']?(api[_-]?key|token|password|authorization)["']?\s*[:=]\s*['"]?[^\s'",}]+/gi,
  /\bbearer\s+\S+/gi,
  /\bsk-[A-Za-z0-9][A-Za-z0-9_]{5,}\b/g,
  /\bgsk_[A-Za-z0-9][A-Za-z0-9_]{5,}\b/g,
  /\bsk-ant-[A-Za-z0-9_]{8,}\b/g,
  /\bAIza[0-9A-Za-z_]{10,}\b/g,
];
const VALID_SEVERITIES = new Set(["critical", "error", "warning", "info"]);
const VALID_TYPES = new Set([
  "error",
  "fatal",
  "flutter_error",
  "platform_error",
  "zone_error",
  "riverpod_error",
]);
const RECENT_LOGS_FIELD = "Recent Logs";

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
  embed?: {
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

function sanitizeUserText(value: string, max = 1024): string {
  let result = value.trim();
  for (const pattern of SENSITIVE_PATTERNS) {
    result = result.replace(pattern, "[redacted]");
  }
  result = result.replaceAll("@", "@\u200B");
  return result.slice(0, max);
}

function requireToken(value: unknown, name: string, max = 1024): string {
  if (typeof value !== "string") throw new Error(`${name} must be a string`);
  const trimmed = value.trim().replaceAll("@", "@\u200B");
  if (!trimmed) throw new Error(`${name} is required`);
  if (trimmed.length > max) throw new Error(`${name} is too long`);
  return trimmed;
}

function optionalToken(value: unknown, name: string, max = 1024): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return requireToken(value, name, max);
}

function requireString(value: unknown, name: string, max = 1024): string {
  if (typeof value !== "string") throw new Error(`${name} must be a string`);
  const sanitized = sanitizeUserText(value, max);
  if (!sanitized) throw new Error(`${name} is required`);
  return sanitized;
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

function requireSeverity(value: unknown, name: string): string {
  const token = requireToken(value, name, 64);
  if (!VALID_SEVERITIES.has(token)) {
    throw new Error(`${name} must be one of: ${Array.from(VALID_SEVERITIES).join(", ")}`);
  }
  return token;
}

function requireType(value: unknown, name: string): string {
  const token = requireToken(value, name, 64);
  if (!VALID_TYPES.has(token)) {
    throw new Error(`${name} must be one of: ${Array.from(VALID_TYPES).join(", ")}`);
  }
  return token;
}

function buildBaseEmbed(report: CrashReport) {
  const [emoji, color] = report.severity === "critical"
    ? ["🔴", 0xDC2626]
    : report.severity === "error"
    ? ["🟠", 0xE97451]
    : report.severity === "warning"
    ? ["🟡", 0xF59E0B]
    : ["ℹ️", 0x3B82F6];

  return {
    title: `${emoji} [${report.type}] ${report.severity}`,
    description: report.message,
    color,
    fields: [
      { name: "Version", value: report.app_version, inline: true },
      { name: "OS", value: `${report.os}/${report.arch}`, inline: true },
      { name: "Device", value: report.device_id.slice(0, 12), inline: true },
      ...(report.process_name
        ? [{ name: "Process", value: report.process_name, inline: true }]
        : []),
      ...(report.stack_trace
        ? [{ name: "Stack Trace", value: `\`\`\`\n${report.stack_trace.slice(0, 900)}\n\`\`\``, inline: false }]
        : []),
    ],
    footer: {
      text: `ID: ${report.id.length > 16 ? report.id.slice(0, 16) : report.id}`,
    },
  };
}

function sanitizeEmbed(payload: CrashPayload["embed"], report: CrashReport) {
  const base = buildBaseEmbed(report);
  const extraFields = Array.isArray(payload?.fields)
    ? payload.fields
        .filter((field) => typeof field?.name === "string" && field.name.trim() === RECENT_LOGS_FIELD)
        .slice(0, 1)
        .map((field) => ({
          name: RECENT_LOGS_FIELD,
          value: requireString(field?.value, "embed.fields.value", 800),
          inline: false,
        }))
    : [];

  return {
    ...base,
    fields: [...base.fields, ...extraFields],
  };
}

function sanitizeReport(report: CrashPayload["report"]): CrashReport {
  return {
    id: requireToken(report.id, "report.id", 80),
    timestamp: requireNumber(report.timestamp, "report.timestamp"),
    type: requireType(report.type, "report.type"),
    severity: requireSeverity(report.severity, "report.severity"),
    message: requireString(report.message, "report.message", 1024),
    stack_trace: optionalString(report.stack_trace, "report.stack_trace", 2048),
    process_name: optionalString(report.process_name, "report.process_name", 128),
    app_version: requireToken(report.app_version || "dev", "report.app_version", 64),
    build_commit: optionalToken(report.build_commit, "report.build_commit", 64),
    go_version: requireToken(report.go_version, "report.go_version", 64),
    os: requireToken(report.os, "report.os", 32),
    arch: requireToken(report.arch, "report.arch", 32),
    device_id: requireToken(report.device_id, "report.device_id", 64),
    gpu: requireToken(report.gpu || "auto", "report.gpu", 64),
    local_stt: requireBoolean(report.local_stt, "report.local_stt"),
    smart_mode: requireBoolean(report.smart_mode, "report.smart_mode"),
    config_snapshot: optionalString(report.config_snapshot, "report.config_snapshot", 1024),
    hash: requireToken(report.hash, "report.hash", 64),
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
    const serverHash = await sha256(`${report.message}${report.stack_trace ?? ""}`);
    report = {
      ...report,
      id: crypto.randomUUID(),
      device_id: await sha256(report.device_id),
      hash: serverHash,
    };
    embed = sanitizeEmbed(parsed.embed, report);
  } catch (error) {
    return json({ error: "invalid_payload", detail: error instanceof Error ? error.message : String(error) }, 400);
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const now = new Date();
  const hourAgo = new Date(now.getTime() - DEDUP_WINDOW_MS).toISOString();
  const forwardedFor = req.headers.get("x-forwarded-for") ?? "";
  const clientIp = forwardedFor.split(",")[0]?.trim() || "";
  const ipHash = clientIp ? await sha256(clientIp) : "unknown";

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

  // Check if this crash hash has been fixed in a newer version
  const { data: fixedRows } = await supabase
    .from("crash_report_events")
    .select("fixed_in_version")
    .eq("message_hash", report.hash)
    .not("fixed_in_version", "is", null)
    .limit(1);

  if (fixedRows && fixedRows.length > 0) {
    const fixedIn = fixedRows[0].fixed_in_version;
    // Compare versions: if report version <= fixed version, auto-dismiss
    if (compareVersions(report.app_version, fixedIn) <= 0) {
      // Still store the event for analytics but mark as dismissed, don't post to Discord
      const dismissedRow = {
        id: report.id,
        received_at: now.toISOString(),
        message_hash: report.hash,
        device_id: report.device_id,
        ip_hash: ipHash,
        app_version: report.app_version,
        build_commit: report.build_commit || null,
        status: "auto_dismissed",
        dismissed: true,
        fixed_in_version: fixedIn,
        payload: { report, embed },
      };
      await supabase.from("crash_report_events").insert(dismissedRow);
      return json({ status: "auto_dismissed", fixed_in: fixedIn }, 202);
    }
  }

  const rateLimitFilters = [
    `device_id.eq.${report.device_id}`,
    clientIp ? `ip_hash.eq.${ipHash}` : null,
  ].filter((value): value is string => value !== null);

  if (rateLimitFilters.length > 0) {
    const { count, error: rateError } = await supabase
      .from("crash_report_events")
      .select("*", { count: "exact", head: true })
      .or(rateLimitFilters.join(","))
      .gte("received_at", hourAgo);
    if (rateError) return json({ error: "rate_limit_query_failed" }, 500);
    if ((count ?? 0) >= MAX_REPORTS_PER_HOUR) {
      return json({ error: "rate_limited" }, 429);
    }
  }

  const eventRow = {
    id: report.id,
    received_at: now.toISOString(),
    message_hash: report.hash,
    device_id: report.device_id,
    ip_hash: ipHash,
    app_version: report.app_version,
    build_commit: report.build_commit || null,
    status: "pending",
    payload: { report, embed },
  };
  const { error: insertError } = await supabase.from("crash_report_events").insert(eventRow);
  if (insertError) return json({ error: "event_insert_failed" }, 500);

  const discordURL = webhookURL.includes("?") ? `${webhookURL}&wait=true` : `${webhookURL}?wait=true`;
  const discordResp = await fetch(discordURL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "accept": "application/json",
      "accept-encoding": "identity",
    },
    body: JSON.stringify({ embeds: [embed] }),
  });
  if (!discordResp.ok) {
    const detail = await discordResp.text();
    await supabase
      .from("crash_report_events")
      .update({ status: "discord_failed", error_detail: detail.slice(0, 500) })
      .eq("id", report.id);
    return json({ error: "discord_post_failed", detail: detail.slice(0, 200) }, 502);
  }

  const discordText = await discordResp.text();
  let discordBody: { id?: string } | null = null;
  if (discordText.trim()) {
    try {
      discordBody = JSON.parse(discordText) as { id?: string };
    } catch {
      discordBody = null;
    }
  }
  await supabase
    .from("crash_report_events")
    .update({
      status: "sent",
      discord_message_id: typeof discordBody?.id === "string" ? discordBody.id : null,
    })
    .eq("id", report.id);

  return json({ status: "sent", id: report.id, discord_message_id: discordBody?.id ?? null }, 202);
});
