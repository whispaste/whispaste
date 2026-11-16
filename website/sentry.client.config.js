import * as Sentry from '@sentry/astro';

// Pages whose address carries a secret (newsletter mail links, layout
// `isPrivate`) mark themselves with a no-referrer meta: no error reports, no
// replays and no tracing there, so the token cannot reach Sentry.
const privatePage =
  typeof document !== 'undefined' && !!document.querySelector('meta[name="referrer"][content="no-referrer"]');

// DSN ist public und darf im Quellcode stehen.
Sentry.init({
  dsn: 'https://51c18e410d7ef2dc90d3439ad8d6a8f1@o4511065943441408.ingest.de.sentry.io/4511410200772688',

  environment: import.meta.env.MODE === 'production' ? 'production' : 'development',

  // Lokaler `astro dev` soll nicht ans Sentry-Quota gehen (WHISPASTE-WEBSITE-2:
  // Vite-HMR-Modulfehler von 127.0.0.1:4321 landeten sonst als echte Issues).
  enabled: import.meta.env.MODE === 'production' && !privatePage,

  // Keine IP/Headers/User-Identität — Marketing-Site hat keinen Login und
  // wir wollen die Privacy-Latte konsistent mit der Flutter-App halten.
  sendDefaultPii: false,

  // Bekannte Nicht-Bugs, die als Browser-/Netzwerk-Rauschen ankommen statt als
  // echte Fehler unserer Seite: Edge/Outlook-SafeLinks-Objektfehler und
  // Content-Injection durch Proxys/DPI-Filter (rohes HTML landet als "Skript").
  // Der zweite Filter ist bewusst eng auf den beobachteten Codepoint gefasst
  // (statt generisch "illegal character"), damit ein echter SyntaxError aus
  // unserem eigenen Bundle nicht mitgeschluckt wird.
  ignoreErrors: [/Object Not Found Matching Id/, /illegal character U\+009E/],

  // Nur Fehlerberichte (#1627): kein Performance-Tracing, kein Session
  // Replay, kein Sitzungs-Tracking. Replay legt eine Kennung im
  // sessionStorage ab und schneidet die Bedienung mit, Tracing misst jeden
  // Seitenaufruf, BrowserSession meldet jeden Seitenaufruf als Sitzung. Das
  // bräuchte eine eigene Offenlegung (Art. 13 DSGVO, § 25 TDDDG) und ist für
  // eine Marketing-Seite nicht nötig; die Datenschutzerklärung nennt nur die
  // Fehlerüberwachung (Abschnitt 4, alle 8 Sprachen). Deshalb: kein
  // `tracesSampleRate`, kein Replay, und aus den Standard-Integrationen fallen
  // BrowserTracing (hängt @sentry/astro sonst an) und BrowserSession heraus.
  // Ohne Fehler sendet die Seite nichts an Sentry. astro.config.mjs entfernt
  // Tracing- und Replay-Code zusätzlich aus dem Bundle.
  integrations: (defaults) =>
    defaults.filter((i) => i.name !== 'BrowserTracing' && i.name !== 'BrowserSession'),
});

