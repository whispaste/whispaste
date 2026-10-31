/**
 * Unit tests for gsc-sitemap-ping.mjs's pure/testable exports.
 * fetch is mocked — no real network call, no real Search Console API hit.
 */
import { generateKeyPairSync } from 'node:crypto';
import { describe, it, expect, vi } from 'vitest';
import { getAccessToken, submitSitemap, SITE_URL, SITEMAP_URL } from '../gsc-sitemap-ping.mjs';

// A throwaway RSA keypair, generated once per test run — signing must
// succeed structurally even though no real Google endpoint verifies it here.
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const fakeServiceAccountKey = {
  client_email: 'whispaste-gsc-sitemap-ping@hellerio-ai.iam.gserviceaccount.com',
  private_key: privateKey.export({ type: 'pkcs1', format: 'pem' }),
};

describe('getAccessToken', () => {
  it('POSTs a signed JWT-bearer assertion to the OAuth2 token endpoint', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: 'fake-token' }),
    });

    const token = await getAccessToken(fakeServiceAccountKey, { fetchImpl });

    expect(token).toBe('fake-token');
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, options] = fetchImpl.mock.calls[0];
    expect(url).toBe('https://oauth2.googleapis.com/token');
    const body = new URLSearchParams(options.body);
    expect(body.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    // header.claims.signature — three base64url segments.
    expect(body.get('assertion')!.split('.')).toHaveLength(3);
  });

  it('throws on a non-2xx token response', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: false, status: 401, text: async () => 'invalid_grant' });
    await expect(getAccessToken(fakeServiceAccountKey, { fetchImpl })).rejects.toThrow('token exchange failed (401)');
  });
});

describe('submitSitemap', () => {
  it('PUTs to the sitemaps.submit endpoint for the whispaste.de property', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 200 });

    await submitSitemap('fake-token', { fetchImpl });

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, options] = fetchImpl.mock.calls[0];
    expect(url).toBe(
      `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(SITE_URL)}/sitemaps/${encodeURIComponent(SITEMAP_URL)}`,
    );
    expect(options.method).toBe('PUT');
    expect(options.headers.Authorization).toBe('Bearer fake-token');
  });

  it('throws on a non-2xx response (caller turns this into process.exit(1))', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: false, status: 403, text: async () => 'forbidden' });
    await expect(submitSitemap('fake-token', { fetchImpl })).rejects.toThrow('sitemaps.submit failed (403)');
  });
});
