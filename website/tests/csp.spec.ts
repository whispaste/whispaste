import { expect, test } from '@playwright/test';
import { withCspMeta } from '../scripts/csp-meta.mjs';

/**
 * csp.spec.ts — Content-Security-Policy of the site (#1629).
 *
 * The build writes the policy as <meta http-equiv> into every page
 * (scripts/csp-meta.mjs); the dev server has none. So that both test modes
 * check the same thing, every HTML document goes through the same
 * `withCspMeta()` on its way into the browser: idempotent on the preview
 * build (CI=1), and on the dev server it applies exactly the policy the
 * build would. Each page is loaded, used a little (download button click),
 * and must not report a single `securitypolicyviolation`: a blocked inline
 * script, style, font, image or request means the policy misses something
 * the page really needs.
 */

const PAGES = [
  '/',
  '/en/',
  '/es/',
  '/pt/',
  '/it/',
  '/ru/',
  '/zh/',
  '/fr/',
  '/download/',
  '/en/download/',
  '/datenschutz/',
  '/en/privacy/',
  '/fr/privacy/',
  '/changelog/',
  '/blog/',
  '/newsletter/confirm/',
  '/yt/',
];

test.describe('content security policy', () => {
  test.beforeEach(async ({ page, baseURL }) => {
    // Registered first, so the host-specific routes below take precedence.
    await page.route('**/*', async (route) => {
      const req = route.request();
      if (req.resourceType() !== 'document' || !baseURL || !req.url().startsWith(baseURL)) {
        await route.fallback();
        return;
      }
      const res = await route.fetch();
      const type = res.headers()['content-type'] ?? '';
      if (!type.includes('text/html')) {
        await route.fulfill({ response: res });
        return;
      }
      await route.fulfill({ response: res, body: withCspMeta(await res.text()) });
    });
    // Keep the run offline and deterministic. Fulfilled or aborted requests
    // still pass through the CSP check first, so a missing host would still
    // be reported as a violation.
    await page.route('https://matomo.silvio-und-maik.de/**', (route) =>
      route.fulfill({ status: 200, contentType: 'text/javascript', body: '' }),
    );
    await page.route('https://api.github.com/**', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
    );
    await page.route('https://api.whispaste.de/**', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: '{}' }),
    );
    await page.route('https://*.ingest.de.sentry.io/**', (route) => route.fulfill({ status: 200, body: '{}' }));
    await page.addInitScript(() => {
      const w = window as unknown as { __cspViolations: string[] };
      w.__cspViolations = [];
      document.addEventListener('securitypolicyviolation', (e) => {
        w.__cspViolations.push(`${e.effectiveDirective} blocked ${e.blockedURI || '(inline)'} at ${e.sourceFile}:${e.lineNumber}`);
      });
    });
  });

  for (const path of PAGES) {
    test(`${path} loads without CSP violations`, async ({ page }) => {
      const consoleErrors: string[] = [];
      page.on('console', (msg) => {
        if (msg.type() === 'error' && /Content Security Policy/i.test(msg.text())) consoleErrors.push(msg.text());
      });
      await page.goto(path, { waitUntil: 'load' });
      // /yt/ redirects to a home page; the checks below apply to that page.

      await expect(page.locator('meta[http-equiv="content-security-policy"]')).toHaveCount(1);
      const csp = await page.locator('meta[http-equiv="content-security-policy"]').getAttribute('content');
      expect(csp).toContain("object-src 'none'");
      expect(csp).toContain("script-src 'self'");

      // Download buttons used to carry inline onclick handlers, which this
      // policy blocks; clicking one proves the replacement path is clean.
      const trigger = page.locator('[data-download-trigger]:visible').first();
      if ((await trigger.count()) > 0) {
        await page.evaluate(() =>
          document.addEventListener('click', (e) => e.preventDefault(), { capture: true }),
        );
        await trigger.click();
      }
      await page.waitForTimeout(300);

      const violations = await page.evaluate(
        () => (window as unknown as { __cspViolations: string[] }).__cspViolations,
      );
      expect(violations).toEqual([]);
      expect(consoleErrors).toEqual([]);
    });
  }
});
