import { expect, test } from '@playwright/test';

// The demo is one stage: three steps plus one finished example. The scene
// buttons swap the example (chat → mail → editor) and keep aria-pressed and the
// step texts in sync; chat is the default without JS.
test('demo scene buttons swap the finished example', async ({ page }) => {
  await page.goto('/en/');
  const stage = page.getByTestId('demo');
  await stage.scrollIntoViewIfNeeded();

  const chat = page.getByTestId('demo-scene-chat');
  const mail = page.getByTestId('demo-scene-mail');
  const editor = page.getByTestId('demo-scene-editor');
  await expect(chat).toHaveAttribute('aria-pressed', 'true');
  await expect(stage.locator('.apd-panel:visible')).toHaveCount(1);
  await expect(stage.locator('.apd-panel:visible')).toContainText('3 pm');

  await mail.click();
  await expect(mail).toHaveAttribute('aria-pressed', 'true');
  await expect(chat).toHaveAttribute('aria-pressed', 'false');
  await expect(stage.locator('.apd-panel:visible')).toContainText('Thursday');
  await expect(stage.locator('.apd-spoken:visible')).toContainText('Thursday');

  await editor.click();
  await expect(editor).toHaveAttribute('aria-pressed', 'true');
  await expect(stage.locator('.apd-panel:visible')).toContainText('empty input');
  await expect(stage.locator('.apd-step-note:visible')).toContainText('editor');
});
