import { expect, test } from '@playwright/test';

/**
 * sponsor.spec.ts
 *
 * Regression guard for the "Where sponsoring goes" cost-category block on
 * the sponsor page (replaces the old generic "What your support covers"
 * paragraph). Verifies the real cost categories are present and that no
 * total/summed euro amount is ever reintroduced into the markup — the
 * transparency block deliberately names cost categories (Apple Developer
 * Program, Microsoft Partner Center, hosting/domain) without a total figure.
 */

const SUM_AMOUNT_PATTERN = /(€|\bEUR\b)\s*\d/;

test.describe('sponsor page cost transparency block', () => {
  for (const [label, path] of [
    ['DE', '/sponsor/'],
    ['EN', '/en/sponsor/'],
  ] as const) {
    test(`${label}: shows the cost-category section with no total amount`, async ({
      page,
    }) => {
      await page.goto(path);

      const block = page.getByTestId('sponsor-cost-table');
      await expect(block).toBeVisible();
      await expect(block).toContainText('Apple Developer Program');
      await expect(block).toContainText('Microsoft Partner Center');

      const blockText = (await block.innerText()).trim();
      expect(blockText).not.toMatch(SUM_AMOUNT_PATTERN);

      const bodyText = await page.locator('body').innerText();
      expect(bodyText).not.toMatch(SUM_AMOUNT_PATTERN);
    });
  }
});
