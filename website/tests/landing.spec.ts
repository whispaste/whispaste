import { test, expect } from '@playwright/test';

const BASE = '/whispaste';

// ------------------------------------------------------------------ P0 Tests
test('Datenschutz-Seite erreichbar und hat Titel', async ({ page }) => {
    const res = await page.goto(`${BASE}/datenschutz`);
    expect(res?.status()).toBe(200);
    await expect(page).toHaveTitle(/Datenschutz/i);
});

test('Impressum-Seite erreichbar und hat Titel', async ({ page }) => {
    const res = await page.goto(`${BASE}/impressum`);
    expect(res?.status()).toBe(200);
    await expect(page).toHaveTitle(/Impressum/i);
});

// ------------------------------------------------------------------ P1 Tests
test('Hero Store-CTA hat Link zu #store', async ({ page }) => {
    await page.goto(`${BASE}/`);
    const cta = page.locator('[data-testid="hero-cta-store"]');
    await expect(cta).toBeVisible();
    await expect(cta).toHaveAttribute('href', '#store');
});

test('Hero GitHub-CTA verlinkt auf GitHub', async ({ page }) => {
    await page.goto(`${BASE}/`);
    const cta = page.locator('[data-testid="hero-cta-github"]');
    await expect(cta).toBeVisible();
    await expect(cta).toHaveAttribute('href', /github\.com/);
});

test('Hero Portable-Link verlinkt auf GitHub Releases', async ({ page }) => {
    await page.goto(`${BASE}/`);
    const link = page.locator('[data-testid="hero-cta-portable"]');
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute('href', /github\.com.*releases/);
});

test('i18n: Lang-Toggle wechselt Sprache von EN zu DE', async ({ page }) => {
    await page.goto(`${BASE}/`);

    // Standardsprache ist EN
    const heroHeading = page.locator('h1').first();
    await expect(heroHeading).toContainText('Voice to text');

    // Auf DE umschalten
    await page.click('[data-testid="lang-toggle"]');

    // DE-Text erscheint (Grossschreibung unterscheidet sich: "Voice to Text")
    await expect(heroHeading).toContainText('Voice to Text,');
    // Der Toggle-Button zeigt jetzt "EN" an
    await expect(page.locator('[data-testid="lang-toggle"]')).toContainText('EN');
});
