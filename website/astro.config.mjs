import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';
import sentry from '@sentry/astro';

export default defineConfig({
  site: 'https://whispaste.de',
  // i18n-Routing: Deutsch ist Default (kein Prefix), Englisch unter `/en/`.
  // Das `<html lang>`-Attribut wird aus `Astro.currentLocale` in `Layout.astro`
  // gesetzt; die client-seitige `data-i18n`-Schicht bleibt als
  // Progressive-Enhancement-Sprachumschalter erhalten.
  i18n: {
    defaultLocale: 'de',
    locales: ['de', 'en'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
  integrations: [
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
        },
      },
    }),
    // Source-Maps werden nur hochgeladen, wenn SENTRY_AUTH_TOKEN gesetzt ist
    // (Build-Time-Env, niemals committen). org/project müssen vor dem ersten
    // CI-Build mit den realen Sentry-Slugs des neuen Website-Projekts ersetzt
    // werden — siehe TODO unten.
    sentry({
      // Region "de" → Org liegt in der EU-Instanz.
      org: 'silvio-lindstedt-und-maik-g-y2',
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
  },
});
