/**
 * gsc-sitemap-ping.mjs — nudges Google to re-fetch the sitemap right after a
 * deploy, via the Search Console API's `sitemaps.submit` (a normal, ToS-
 * compliant call — unlike the Indexing API, which is restricted to
 * JobPosting/BroadcastEvent content and must not be used for regular
 * pages). Complements push-indexnow.mjs (Bing/Yandex/Naver/Seznam/Yep),
 * which cannot reach Google.
 *
 * Auth: a dedicated, minimal-scope service account
 * (whispaste-gsc-sitemap-ping@hellerio-ai.iam.gserviceaccount.com, GCP
 * project hellerio-ai) added as a "Full" user on the sc-domain:whispaste.de
 * Search Console property. It has no other IAM roles or product access. No
 * `googleapis` dependency — this signs its own JWT with Node's built-in
 * `crypto` and exchanges it for an access token, since the only call needed
 * is a single authenticated PUT.
 *
 * Credential handling: the service account key JSON is a long-lived
 * credential, stored only as the GitHub Actions secret GSC_SA_KEY (see
 * .github/workflows/deploy-pages.yml) — never committed, never written to
 * disk outside the CI runner's ephemeral environment.
 *
 * Usage: GSC_SA_KEY='<service-account-json>' node scripts/gsc-sitemap-ping.mjs
 */
import { fileURLToPath } from 'node:url';
import { createSign } from 'node:crypto';

export const SITE_URL = 'sc-domain:whispaste.de';
export const SITEMAP_URL = 'https://whispaste.de/sitemap-index.xml';
const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/webmasters';

function base64url(input) {
  return Buffer.from(input).toString('base64url');
}

/** Signs a Google service-account JWT assertion for the given scope. */
function buildAssertion({ client_email, private_key }) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claimSet = base64url(
    JSON.stringify({
      iss: client_email,
      scope: SCOPE,
      aud: TOKEN_ENDPOINT,
      iat: now,
      exp: now + 3600,
    }),
  );
  const signInput = `${header}.${claimSet}`;
  const signature = createSign('RSA-SHA256').update(signInput).sign(private_key, 'base64url');
  return `${signInput}.${signature}`;
}

/** Exchanges a signed JWT assertion for a short-lived OAuth2 access token. */
export async function getAccessToken(serviceAccountKey, { fetchImpl = fetch } = {}) {
  const assertion = buildAssertion(serviceAccountKey);
  const res = await fetchImpl(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`gsc-sitemap-ping: token exchange failed (${res.status}): ${await res.text()}`);
  }
  const { access_token } = await res.json();
  return access_token;
}

/** PUTs the sitemap to Search Console's sitemaps.submit endpoint. */
export async function submitSitemap(accessToken, { fetchImpl = fetch } = {}) {
  const url =
    `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(SITE_URL)}` +
    `/sitemaps/${encodeURIComponent(SITEMAP_URL)}`;
  const res = await fetchImpl(url, {
    method: 'PUT',
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    throw new Error(`gsc-sitemap-ping: sitemaps.submit failed (${res.status}): ${await res.text()}`);
  }
  return res;
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url);
if (isMain) {
  const raw = process.env.GSC_SA_KEY;
  if (!raw) {
    console.error('gsc-sitemap-ping: GSC_SA_KEY env var is not set — skipping.');
    process.exit(1);
  }
  try {
    const key = JSON.parse(raw);
    const token = await getAccessToken(key);
    await submitSitemap(token);
    console.log(`gsc-sitemap-ping: ok — resubmitted ${SITEMAP_URL}`);
  } catch (err) {
    console.error(err instanceof Error ? err.message : err);
    process.exit(1);
  }
}
