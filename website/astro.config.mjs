import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';
import sentry from '@sentry/astro';
import { cspMeta } from './scripts/csp-meta.mjs';
import { collectLastmods, readBlogPosts, readLatestRelease } from './scripts/sitemap-lastmod.mjs';

const SITE = 'https://whispaste.de';
const LOCALES = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'];

// Sitemap-`lastmod` nur mit echtem Änderungsdatum (#1769): Blogbeiträge aus
// ihrem Frontmatter, Changelog aus dem neuesten Release. Alle anderen Seiten
// bleiben ohne `lastmod`, statt ein falsches Datum zu tragen.
const LASTMODS = collectLastmods({
  site: SITE,
  posts: readBlogPosts(fileURLToPath(new URL('./src/content/blog/', import.meta.url))),
  latestRelease: readLatestRelease(fileURLToPath(new URL('./src/data/releases.json', import.meta.url))),
  locales: LOCALES,
});

export default defineConfig({
  site: SITE,
  // i18n-Routing: Deutsch ist Default (kein Prefix), alle anderen Sprachen
  // unter `/<locale>/` (Seiten in `src/pages/[lang]/`, Registry in
  // `src/scripts/locales.ts` — beide Listen müssen übereinstimmen).
  // Das `<html lang>`-Attribut wird aus `Astro.currentLocale` in `Layout.astro`
  // gesetzt; jede Sprache wird vollständig serverseitig gerendert.
  i18n: {
    defaultLocale: 'de',
    locales: LOCALES,
    routing: {
      prefixDefaultLocale: false,
    },
  },
  integrations: [
    // Design-system catalogue (/design-system/): dev server only, never part
    // of the build, so it needs no translations, sitemap entry or SEO meta.
    {
      name: 'wp-design-system-catalogue',
      hooks: {
        'astro:config:setup': ({ command, injectRoute }) => {
          if (command !== 'dev') return;
          injectRoute({
            pattern: '/design-system',
            entrypoint: './src/design-system/DesignSystemPage.astro',
          });
        },
      },
    },
    // Sitemap-Plugin generiert hreflang-Alternates per `<xhtml:link>`-Eintrag.
    // Die `locales`-Map muss BCP-47-Sprachtags auf die in `i18n.locales`
    // konfigurierten Slugs abbilden (siehe Astro-Docs zum Sitemap-Integrations-
    // Plugin §i18n-Option).
    sitemap({
      i18n: {
        defaultLocale: 'de',
        locales: {
          de: 'de',
          en: 'en',
          es: 'es',
          pt: 'pt-BR',
          it: 'it',
          ru: 'ru',
          zh: 'zh-Hans',
          fr: 'fr',
        },
      },
      // /yt/ is a redirect-only short link for YouTube Shorts (src/pages/yt.astro).
      filter: (page) => !page.endsWith('/yt/') && !/\/newsletter\/(confirm|unsubscribe|device)\/$/.test(page),
      serialize(item) {
        const lastmod = LASTMODS.get(item.url);
        if (lastmod) item.lastmod = lastmod;
        return item;
      },
    }),
    // Source-Maps werden nur hochgeladen, wenn SENTRY_AUTH_TOKEN gesetzt ist
    // (Build-Time-Env, niemals committen). org/project müssen vor dem ersten
    // CI-Build mit den realen Sentry-Slugs des neuen Website-Projekts ersetzt
    // werden — siehe TODO unten.
    sentry({
      // Region "de" → Org liegt in der EU-Instanz.
      org: 'org',
      project: 'whispaste-website',
      authToken: process.env.SENTRY_AUTH_TOKEN,
      // Kein Telemetry-Ping vom sentry-vite-plugin an Sentry über sich selbst.
      telemetry: false,
      // Die Seite sendet nur Fehlerberichte (#1627, sentry.client.config.js):
      // Tracing- und Replay-Code fliegt schon beim Build aus dem Bundle.
      bundleSizeOptimizations: {
        excludeTracing: true,
        excludeReplayIframe: true,
        excludeReplayShadowDom: true,
        excludeReplayWorker: true,
      },
      sourceMapsUploadOptions: {
        assets: ['./dist/**'],
      },
    }),
    // Content-Security-Policy als <meta> in jeder gebauten Seite, mit den
    // Hashes ihrer Inline-Skripte (#1629, Hosts und Begründung in
    // scripts/csp-meta.mjs). Nur im Build, der Dev-Server bleibt ohne CSP.
    cspMeta(),
  ],
  vite: {
    plugins: [tailwindcss()],
    // WhisPaste ist eine Desktop-App für aktuelle macOS/Windows/Linux —
    // die Marketing-Site braucht keine Alt-Browser-Kompatibilität. Modernes
    // Build-Target vermeidet unnötiges Down-Leveling (z. B. Array.from-
    // Transpilierung), das Lighthouse als "legacy JavaScript" flaggt.
    build: {
      target: 'es2022',
    },
  },
});
