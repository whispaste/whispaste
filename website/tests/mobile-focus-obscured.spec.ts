import { expect, test } from '@playwright/test';

// #1909 (WCAG 2.4.11): on a phone-sized viewport the sticky download bar and
// the contact teaser float over the page bottom. A Tab walk through the home
// page must never leave the focused element fully covered by them.
test.use({ viewport: { width: 390, height: 844 } });

for (const path of ['/', '/en/'] as const) {
  test(`${path}: Tab walk at 390x844 keeps every focused element visible`, async ({ page }) => {
    // Fake time runs at real speed; fast-forward past the teaser's 6 s pause
    // so it appears (on the first scroll past the hero) as for a real visitor.
    await page.clock.install();
    test.setTimeout(120_000);
    await page.goto(path);
    await page.clock.fastForward(7000);
    const covered: string[] = [];
    // One pass through the page (about 65 stops in every locale).
    for (let i = 0; i < 75; i++) {
      await page.keyboard.press('Tab');
      // The page scrolls smoothly: wait until the position settles.
      let last = -1;
      for (let still = 0; still < 3; ) {
        const y = await page.evaluate(() => scrollY);
        still = y === last ? still + 1 : 0;
        last = y;
        await page.waitForTimeout(40);
      }
      const result = await page.evaluate(() => {
        const el = document.activeElement as HTMLElement | null;
        if (!el || el === document.body) return null;
        if (el.closest('#mobile-cta, .cw, #screenshot-lightbox')) return null;
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return null;
        const inset = 1;
        const pts = [
          [r.left + inset, r.top + inset],
          [r.right - inset, r.top + inset],
          [r.left + inset, r.bottom - inset],
          [r.right - inset, r.bottom - inset],
          [r.left + r.width / 2, r.top + r.height / 2],
        ].filter(([x, y]) => x >= 0 && y >= 0 && x < innerWidth && y < innerHeight);
        if (!pts.length) return null; // off-screen (e.g. inside a scroller), not our concern
        const visible = pts.some(([x, y]) => {
          const hit = document.elementFromPoint(x, y);
          return !!hit && (hit === el || el.contains(hit) || hit.contains(el));
        });
        if (visible) return null;
        const hit = document.elementFromPoint(pts[0][0], pts[0][1]);
        if (!hit?.closest('#mobile-cta, .cw')) return null; // only the fixed bottom layers are in scope
        return `${el.tagName} "${(el.textContent ?? '').trim().slice(0, 40)}"`;
      });
      if (result) covered.push(result);
    }
    expect(covered).toEqual([]);
  });
}
