import { defineConfig } from "vitest/config";

/**
 * Vitest configuration for the WhisPaste marketing website.
 *
 * Two test groups coexist in this repo:
 *
 *   1. Node-side build scripts under `scripts/__tests__/*.test.ts` — they read
 *      fixtures from disk, parse markdown, and exercise the release fetcher and
 *      release store. These run under `environment: 'node'` (the default).
 *
 *   2. Browser-side scripts under `src/scripts/__tests__/*.test.ts` — they
 *      exercise the `ChangelogHydrator` against `window`, `document`,
 *      `localStorage`, and mocked `fetch`. These need `environment: 'jsdom'`,
 *      which is opted in **per file** via the `// @vitest-environment jsdom`
 *      pragma at the top of each browser-side test. Vitest 4 removed the
 *      `environmentMatchGlobs` option, so we no longer match by glob here.
 *
 * The two groups are co-located in one Vitest invocation so a single
 * `npx vitest run` covers the whole site.
 */
export default defineConfig({
  test: {
    environment: "node",
    // jsdom (Vitest 4) leaves localStorage/sessionStorage undefined; the setup
    // file polyfills them so storage-dependent browser tests run. See
    // vitest.setup.ts for the full rationale.
    setupFiles: ["./vitest.setup.ts"],
    include: [
      "scripts/__tests__/**/*.test.ts",
      "src/scripts/__tests__/**/*.test.ts",
      // Schema-Builder-Tests (Issue 04, Schema-Component-Familie). Reine
      // Node-Tests gegen die pure-TS-Builder unter
      // `src/components/schema/builders.ts`; kein DOM-Setup nötig, weil die
      // Builder einfache JSON-LD-Objekte zurückgeben.
      "src/components/schema/__tests__/**/*.test.ts",
    ],
  },
});
