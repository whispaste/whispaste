/**
 * Crawler-Policy-Regression — Issue 08.
 *
 * Lockt die in `robots.txt` und `ai.txt` dokumentierte Default-Allow-Policy
 * für die sieben benannten KI-Crawler ein. Ein versehentliches Entfernen oder
 * Umstellen auf `Disallow` schlägt diesen Test fehl, bevor es deployt wird.
 *
 * Die Policy-Entscheidung selbst (Allow statt Block) ist in
 * `.scratch/seo-overhaul/issues/08-ai-txt-crawler-policy.md` begründet:
 * MIT-lizenziertes Projekt, Brand-Konsistenz-Interesse, KI-Such-Sichtbarkeit.
 */
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const publicDir = resolve(__dirname, "..", "..", "public");

const AI_CRAWLERS = [
  "GPTBot",
  "ClaudeBot",
  "Claude-Web",
  "PerplexityBot",
  "OAI-SearchBot",
  "Google-Extended",
  "Cohere-AI",
] as const;

describe("AI crawler policy (robots.txt + ai.txt)", () => {
  it("robots.txt explicitly allows every named AI crawler", async () => {
    const robots = await readFile(resolve(publicDir, "robots.txt"), "utf8");
    for (const bot of AI_CRAWLERS) {
      const uaLine = new RegExp(`^User-agent:\\s*${bot}\\s*$`, "m");
      expect(robots, `User-agent block missing for ${bot}`).toMatch(uaLine);
      // The Allow: / directive must follow within a few lines of the UA line.
      const segment = robots
        .split("\n")
        .slice(
          robots.split("\n").findIndex((l) => uaLine.test(l)),
          robots.split("\n").findIndex((l) => uaLine.test(l)) + 3,
        )
        .join("\n");
      expect(segment, `Allow: / missing after User-agent: ${bot}`).toMatch(
        /^Allow:\s*\/\s*$/m,
      );
    }
  });

  it("robots.txt keeps the wildcard block and the sitemap reference", async () => {
    const robots = await readFile(resolve(publicDir, "robots.txt"), "utf8");
    expect(robots).toMatch(/^User-agent:\s*\*\s*$/m);
    expect(robots).toMatch(/^Sitemap:\s*https:\/\/whispaste\.de\//m);
  });

  it("robots.txt embeds a machine-readable comment block explaining the Allow policy", async () => {
    const robots = await readFile(resolve(publicDir, "robots.txt"), "utf8");
    expect(robots).toMatch(/#\s*AI crawler policy/i);
    expect(robots).toMatch(/Default-Allow/);
    // The comment block must appear before the first AI crawler UA line.
    const policyIdx = robots.search(/AI crawler policy/i);
    const firstBotIdx = robots.search(/^User-agent:\s*GPTBot/m);
    expect(policyIdx).toBeGreaterThan(-1);
    expect(firstBotIdx).toBeGreaterThan(-1);
    expect(policyIdx).toBeLessThan(firstBotIdx);
  });

  it("ai.txt declares an Allow policy and lists every AI crawler", async () => {
    const aiTxt = await readFile(resolve(publicDir, "ai.txt"), "utf8");
    expect(aiTxt).toMatch(/^Policy:\s*allow\s*$/m);
    expect(aiTxt).toMatch(/^License:\s*MIT\s*$/m);
    expect(aiTxt).toMatch(/^Source:\s*https:\/\/whispaste\.de\//m);
    for (const bot of AI_CRAWLERS) {
      const uaLine = new RegExp(`^User-agent:\\s*${bot}\\s*$`, "m");
      expect(aiTxt, `ai.txt missing User-agent block for ${bot}`).toMatch(
        uaLine,
      );
    }
  });
});
