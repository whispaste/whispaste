import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';
import sentry from '@sentry/astro';

// Build-Zeitstempel als Sitemap-`lastmod`. Einmal pro Build ausgewertet,
// damit alle Einträge denselben konsistenten Wert tragen.
const BUILD_LASTMOD = new Date().toISOString();

export default defineConfig({
  site: 'https://whispaste.de',
  // i18n-Routing: Deutsch ist Default (kein Prefix), alle anderen Sprachen
  // unter `/<locale>/` (Seiten in `src/pages/[lang]/`, Registry in
  // `src/scripts/locales.ts` — beide Listen müssen übereinstimmen).
  // Das `<html lang>`-Attribut wird aus `Astro.currentLocale` in `Layout.astro`
  // gesetzt; jede Sprache wird vollständig serverseitig gerendert.
  i18n: {
    defaultLocale: 'de',
    locales: ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'],
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
      // `lastmod` auf den Build-Zeitstempel setzen — bei einer statisch
      // generierten Site ist der Build/Deploy der letzte Änderungszeitpunkt
      // jeder Seite. Hilft Crawlern, ein knappes Crawl-Budget zu priorisieren.
      // /yt/ is a redirect-only short link for YouTube Shorts (src/pages/yt.astro).
      filter: (page) => !page.endsWith('/yt/'),
      serialize(item) {
        item.lastmod = BUILD_LASTMOD;
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
      sourceMapsUploadOptions: {
        assets: ['./dist/**'],
      },
    }),
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
