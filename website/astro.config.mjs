import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';
import sentry from '@sentry/astro';

export default defineConfig({
  site: 'https://whispaste.de',
  integrations: [
    sitemap(),
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
