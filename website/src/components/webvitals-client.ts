/**
 * webvitals-client.ts — browser-side Core Web Vitals reporter.
 *
 * Bundled first-party by Astro (never a CDN) via <WebVitals>. Uses Google's
 * `web-vitals` library (Apache-2.0) to measure the five Core Web Vitals of real
 * visitors and reports them as Matomo custom events on the existing `_paq` queue
 * configured in Layout.astro (cookiefree, IP-anonymised, DNT-honouring).
 *
 * Only numeric timing/layout metrics are sent — no additional personal data. The
 * web-vitals library never transmits anything itself; it just invokes `report`.
 */
import { onCLS, onFCP, onINP, onLCP, onTTFB, type Metric } from "web-vitals";

type Paq = { push: (args: unknown[]) => void };

function report(metric: Metric): void {
  // CLS is a unitless fraction < 1 → scale ×1000 so the Matomo event value stays
  // an integer (Matomo event values are numeric; sub-1 decimals lose precision).
  const value =
    metric.name === "CLS" ? Math.round(metric.value * 1000) : Math.round(metric.value);

  const w = window as unknown as { _paq?: Paq };
  const paq = (w._paq = w._paq ?? ([] as unknown as Paq));

  // [trackEvent, category, action = metric name, name = good/needs-improvement/poor, value]
  paq.push(["trackEvent", "Core Web Vitals", metric.name, metric.rating, value]);
}

onLCP(report);
onINP(report);
onCLS(report);
onFCP(report);
onTTFB(report);
