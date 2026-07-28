import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // Standard Playwright practice: absorb rare, environment-caused flakes
  // (real machine/CI load, not code) with one retry, without masking an
  // actually-broken test — a genuine regression still fails every retry.
  // No retries locally, where a flake should surface immediately for the
  // person running the suite to investigate.
  retries: process.env.CI ? 1 : 0,
  // Cross-engine parity (issue 10): the overlay-mockup snapshot baseline is
  // shared between the chromium and webkit projects (no {projectName} in the
  // path), so a passing run proves both engines render the same pixels.
  snapshotPathTemplate: '{testDir}/__screenshots__/{testFilePath}/{arg}{ext}',
  use: {
    baseURL: 'http://127.0.0.1:4321',
    locale: 'en-US',
    trace: 'on-first-retry',
  },
  webServer: {
    command: process.env.CI
      ? 'npm run preview -- --host 127.0.0.1 --port 4321'
      : 'npm run dev -- --host 127.0.0.1 --port 4321',
    url: 'http://127.0.0.1:4321',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    // WebKit (Safari engine) runs only the overlay-mockup parity spec; it
    // compares against the same shared baseline as chromium to prove parity.
    {
      name: 'webkit',
      testMatch: /overlay-parity\.spec\.ts/,
      use: { ...devices['Desktop Safari'] },
    },
  ],
});
