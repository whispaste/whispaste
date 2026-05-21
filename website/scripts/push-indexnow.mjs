#!/usr/bin/env node
/**
 * IndexNow-Submission als Post-Build-Hook — siehe `.scratch/seo-overhaul/prd.md`
 * §D ("LLM-Search-Foundation") und Issue 06.
 *
 * Was passiert hier:
 *   1. Sitemap aus `<repo>/website/dist/sitemap-0.xml` lesen (Astro-Output;
 *      Voraussetzung: `astro build` ist gelaufen).
 *   2. Aus den `<loc>`-Einträgen die Submissions-URL-Liste bauen.
 *   3. Wenn `process.env.INDEXNOW_KEY` gesetzt ist, POST an
 *      `https://api.indexnow.org/IndexNow` mit dem JSON-Body
 *      `{ host, key, keyLocation, urlList }` (siehe
 *      https://www.indexnow.org/documentation).
 *   4. Wenn `INDEXNOW_KEY` fehlt: Log + Exit 0. Niemals failen — der Build-
 *      Hook ist opt-in. Lokale Maintainer-Builds und frische CI-Clones ohne
 *      gesetzten Key laufen sauber durch.
 *
 * --- Verifikations-Datei (AC2) --------------------------------------------
 *
 * IndexNow verifiziert den Site-Owner über eine statische Datei unter
 * `https://whispaste.de/<key>.txt`, deren Inhalt EXAKT der Key-String ist.
 *
 * Diese Datei wird vom Maintainer EINMALIG manuell unter
 * `website/public/<key>.txt` angelegt — sie ist absichtlich öffentlich
 * (das ist der Verifikations-Mechanismus) und kann ins Repo committet werden.
 * Astro kopiert sie automatisch in `dist/`. Der Key-WERT in `INDEXNOW_KEY`
 * bleibt trotzdem aus dem Repo raus (`.env.local` ist gitignored, AC5), weil
 * er die Build-Pipeline identifiziert; aber die `<key>.txt` AM gehosteten
 * Pfad ist by-design öffentlich lesbar.
 *
 * Dieses Skript erzeugt die Verifikations-Datei NICHT automatisch, weil
 *   (a) das den Key in jeden Build-Output leaken würde, auch in solche, die
 *       per Zufall ohne `.gitignore`-Schutz committet werden, und
 *   (b) der Setup-Schritt einmalig ist und manuell ins Repo gehört (sodass
 *       jeder CI-Lauf die selbe Datei ausliefert und die IndexNow-Verifikation
 *       stabil bleibt).
 *
 * --- Dry-Run --------------------------------------------------------------
 *
 * `INDEXNOW_DRY_RUN=1` führt den vollen Pfad inklusive Payload-Bau aus,
 * unterbindet aber den HTTP-Call. Praktisch für lokale Smoke-Tests und für
 * agent-getriebene Verifikation in Issue-Workflows.
 *
 * --- Pure-Funktionen für Tests --------------------------------------------
 *
 * `extractUrlsFromSitemap`, `buildPayload`, `submitIndexNow`, `main` sind
 * exportiert und werden über `__tests__/push-indexnow.test.ts` mit
 * injizierten `fetch`- und `readSitemap`-Mocks verifiziert — kein Netzwerk
 * und kein Filesystem-Zugriff im Test.
 */

import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// ---------------------------------------------------------------------------
// Konstanten
// ---------------------------------------------------------------------------

/**
 * IndexNow-API-Endpoint (generischer Aggregator; leitet an die teilnehmenden
 * Suchmaschinen weiter: Bing, Yandex, Naver, Seznam.cz, Yep). Alternativ
 * könnten Engine-spezifische Endpoints angesprochen werden
 * (`https://www.bing.com/IndexNow`, …) — der generische ist Standard.
 */
export const INDEXNOW_ENDPOINT = "https://api.indexnow.org/IndexNow";

/**
 * Site-Host für die `host`- und `keyLocation`-Felder im Payload. Hard-coded,
 * weil WhisPaste exakt eine Marketing-Domain hat (`whispaste.de`). Ein
 * Mehr-Domain-Setup würde diesen Wert aus `astro.config.mjs` `site` ableiten;
 * für den aktuellen Single-Domain-Build ist das overkill.
 */
export const SITE_HOST = "whispaste.de";

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/**
 * Extrahiert alle `<loc>…</loc>`-Inhalte aus einem Astro-Sitemap-XML in
 * Document-Reihenfolge. Bewusst kein vollwertiger XML-Parser — Astros
 * Sitemap-Format ist stabil und enthält keine verschachtelten `<loc>`-
 * Elemente oder CDATA-Blöcke. Regex auf `<loc>`-Tags ist robust genug.
 *
 * `<xhtml:link href="…">`-Attribute (hreflang-Alternates) zählen NICHT als
 * Submission-URLs — IndexNow erwartet eine Liste der primären URLs, die
 * Locale-Alternates werden von den Suchmaschinen selbst aus dem Crawl
 * abgeleitet.
 *
 * XML-Entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`) werden auf ihre
 * Zeichenwerte zurückübersetzt, damit URLs mit Query-Parametern (z. B.
 * `?a=1&b=2`) korrekt submitted werden.
 *
 * @param {string} xml - Roh-XML einer Astro-`sitemap-0.xml`-Datei.
 * @returns {string[]} URL-Liste in Document-Reihenfolge.
 */
export function extractUrlsFromSitemap(xml) {
  const out = [];
  const re = /<loc>([\s\S]*?)<\/loc>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    out.push(decodeXmlEntities(m[1].trim()));
  }
  return out;
}

function decodeXmlEntities(str) {
  return str
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

/**
 * Baut das IndexNow-JSON-Body-Objekt. Reihenfolge der Felder ist für die
 * Spec irrelevant, wird hier aber deterministisch gehalten, damit der
 * Snapshot-Test stabil bleibt.
 *
 * @param {object} input
 * @param {string} input.host - Site-Domain ohne Schema (z. B. `whispaste.de`).
 * @param {string} input.key - IndexNow-Key (32-Zeichen-Hex empfohlen).
 * @param {string} input.keyLocation - öffentliche URL der Verifikations-Datei.
 * @param {ReadonlyArray<string>} input.urls - Submissions-URL-Liste.
 * @returns {{ host: string, key: string, keyLocation: string, urlList: string[] }}
 */
export function buildPayload({ host, key, keyLocation, urls }) {
  return {
    host,
    key,
    keyLocation,
    urlList: [...urls],
  };
}

/**
 * POSTet das Payload an den IndexNow-Endpoint und liefert ein Status-Objekt
 * zurück. Niemals werfen — alle Fehlerpfade werden vom Caller (`main`) als
 * Exit-Code 1 behandelt.
 *
 * @param {ReturnType<typeof buildPayload>} payload
 * @param {object} opts
 * @param {typeof fetch} opts.fetch - injizierte Fetch-Implementierung
 *   (für Tests via Mock, in Produktion das globale `fetch` von Node ≥ 18).
 * @param {boolean} [opts.dryRun] - wenn true, kein Netzwerk-Call.
 * @returns {Promise<{ status: number, statusText?: string, body?: string, dryRun?: boolean }>}
 */
export async function submitIndexNow(payload, { fetch: fetchImpl, dryRun = false }) {
  if (dryRun) {
    return { status: 0, dryRun: true };
  }
  const res = await fetchImpl(INDEXNOW_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(payload),
  });
  // Body ist klein (i. d. R. leer bei 200/202), wir lesen ihn defensive
  // für besseren Log-Output bei 4xx-Antworten.
  let body = "";
  try {
    body = await res.text();
  } catch {
    // ignorieren — Body ist nur für Logs nützlich
  }
  return { status: res.status, statusText: res.statusText, body };
}

// ---------------------------------------------------------------------------
// Orchestrator (`main`)
// ---------------------------------------------------------------------------

/**
 * Default-Sitemap-Pfad relativ zur Repo-Root.
 */
function defaultSitemapPath() {
  const here = dirname(fileURLToPath(import.meta.url));
  return resolve(here, "..", "dist", "sitemap-0.xml");
}

/**
 * Hauptlauf. Alle externen Effekte (Filesystem, Netzwerk, ENV) sind
 * injizierbar, damit der Test ohne Side-Effects läuft.
 *
 * @param {object} [deps]
 * @param {typeof fetch} [deps.fetch]
 * @param {Record<string, string | undefined>} [deps.env]
 * @param {() => Promise<string>} [deps.readSitemap]
 * @param {(msg: string) => void} [deps.log] - stdout-Logger.
 * @param {(msg: string) => void} [deps.errorLog] - stderr-Logger.
 * @returns {Promise<{
 *   exitCode: number,
 *   skipped: boolean,
 *   reason?: string,
 *   error?: string,
 *   status?: number,
 *   dryRun?: boolean,
 * }>}
 */
export async function main(deps = {}) {
  const {
    fetch: fetchImpl = globalThis.fetch,
    env = process.env,
    readSitemap = async () => readFile(defaultSitemapPath(), "utf8"),
    log = (msg) => process.stdout.write(msg + "\n"),
    errorLog = (msg) => process.stderr.write(msg + "\n"),
  } = deps;

  const key = env.INDEXNOW_KEY;
  if (!key || key.trim().length === 0) {
    const reason = "no INDEXNOW_KEY set — skipping IndexNow submission";
    log(`[indexnow] ${reason}`);
    return { exitCode: 0, skipped: true, reason };
  }

  const dryRun = env.INDEXNOW_DRY_RUN === "1" || env.INDEXNOW_DRY_RUN === "true";

  let xml;
  try {
    xml = await readSitemap();
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : String(err ?? "unknown error");
    errorLog(`[indexnow] failed to read sitemap: ${msg}`);
    return { exitCode: 1, skipped: false, error: `sitemap: ${msg}` };
  }

  const urls = extractUrlsFromSitemap(xml);
  if (urls.length === 0) {
    const msg = "no URLs found in sitemap — refusing to submit empty list";
    errorLog(`[indexnow] ${msg}`);
    return { exitCode: 1, skipped: false, error: msg };
  }

  const payload = buildPayload({
    host: SITE_HOST,
    key,
    keyLocation: `https://${SITE_HOST}/${key}.txt`,
    urls,
  });

  if (dryRun) {
    log(
      `[indexnow] DRY RUN — would POST ${urls.length} URL(s) to ${INDEXNOW_ENDPOINT} (host=${SITE_HOST})`,
    );
    return { exitCode: 0, skipped: false, dryRun: true, status: 0 };
  }

  let response;
  try {
    response = await submitIndexNow(payload, { fetch: fetchImpl });
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : String(err ?? "unknown error");
    errorLog(`[indexnow] HTTP error: ${msg}`);
    return { exitCode: 1, skipped: false, error: msg };
  }

  // IndexNow-Spec: 200 = accepted + processed, 202 = accepted, pending.
  // Alles andere ist ein Fehler — Key invalid (403), Format-Fehler (422),
  // Quota überschritten (429), Server-Fehler (5xx). In allen Fehlerfällen
  // non-zero exit, damit Deploy-Pipelines die Sichtbarkeit haben.
  const ok = response.status === 200 || response.status === 202;
  if (ok) {
    log(
      `[indexnow] submitted ${urls.length} URL(s) — ${response.status} ${response.statusText ?? ""}`.trimEnd(),
    );
    return { exitCode: 0, skipped: false, status: response.status };
  }
  errorLog(
    `[indexnow] non-success response: ${response.status} ${response.statusText ?? ""} — ${response.body ?? ""}`.trimEnd(),
  );
  return { exitCode: 1, skipped: false, status: response.status };
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

const invokedAsCli = (() => {
  if (!process.argv[1]) return false;
  try {
    return pathToFileURL(process.argv[1]).href === import.meta.url;
  } catch {
    return false;
  }
})();

if (invokedAsCli) {
  main()
    .then((result) => {
      process.exit(result.exitCode);
    })
    .catch((err) => {
      // Defensive — `main()` sollte niemals throwen, aber wenn doch, klar
      // failen statt unbemerkt Exit 0.
      process.stderr.write(`[indexnow] uncaught error: ${err?.message ?? err}\n`);
      process.exit(1);
    });
}
