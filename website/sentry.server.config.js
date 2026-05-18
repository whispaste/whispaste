import * as Sentry from '@sentry/astro';

// Server-Init läuft nur beim `astro build` und im Dev-Server (`astro dev`).
// Die Marketing-Site hat keinen SSR-Adapter — zur Laufzeit gibt es keinen
// Node-Prozess. Diese Datei fängt also nur Build-/Dev-Time-Fehler ab
// (Integrationen, Plugins, Build-Skripte).
Sentry.init({
  dsn: 'https://51c18e410d7ef2dc90d3439ad8d6a8f1@o4511065943441408.ingest.de.sentry.io/4511410200772688',

  environment: process.env.NODE_ENV === 'production' ? 'production' : 'development',

  sendDefaultPii: false,

  // Build-Errors sind selten — 100 % reicht und kostet praktisch nichts.
  tracesSampleRate: 1.0,
});
