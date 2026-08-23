import * as Sentry from '@sentry/astro';

// DSN ist public und darf im Quellcode stehen.
Sentry.init({
  dsn: 'https://51c18e410d7ef2dc90d3439ad8d6a8f1@o4511065943441408.ingest.de.sentry.io/4511410200772688',

  environment: import.meta.env.MODE === 'production' ? 'production' : 'development',

  // Lokaler `astro dev` soll nicht ans Sentry-Quota gehen (WHISPASTE-WEBSITE-2:
  // Vite-HMR-Modulfehler von 127.0.0.1:4321 landeten sonst als echte Issues).
  enabled: import.meta.env.MODE === 'production',

  // Keine IP/Headers/User-Identität — Marketing-Site hat keinen Login und
  // wir wollen die Privacy-Latte konsistent mit der Flutter-App halten.
  sendDefaultPii: false,

  // Bekannte Nicht-Bugs, die als Browser-/Netzwerk-Rauschen ankommen statt als
  // echte Fehler unserer Seite: Edge/Outlook-SafeLinks-Objektfehler und
  // Content-Injection durch Proxys/DPI-Filter (rohes HTML landet als "Skript").
  ignoreErrors: [/Object Not Found Matching Id/, /illegal character/i],

  // Performance-Tracing: Marketing-Site hat wenig Traffic, aber wir wollen
  // nicht das Free-Tier-Span-Budget der Org sprengen. 10 % in Produktion,
  // 100 % lokal.
  tracesSampleRate: import.meta.env.MODE === 'production' ? 0.1 : 1.0,

  // Session Replay: nur Error-Sessions aufzeichnen. Datenschutzfreundlich,
  // weil Replays sonst Maus/Klicks/Text mitschneiden würden.
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 1.0,

  // Distributed Tracing: keine Header an Drittanbieter (Plausible/Cloudflare/CDN).
  // Aktuell propagieren wir nichts — die Site spricht mit keiner eigenen API.
  tracePropagationTargets: [],

  integrations: [
    Sentry.browserTracingIntegration(),
    Sentry.replayIntegration({
      maskAllText: true,
      blockAllMedia: true,
    }),
  ],
});

