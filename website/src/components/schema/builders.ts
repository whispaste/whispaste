/**
 * Schema-Builder — reine TypeScript-Funktionen, die JSON-LD-Objekte für die
 * fünf Schema-Components der whispaste.de-Site erzeugen (Issue
 * `.scratch/seo-overhaul/issues/04-schema-component-familie.md`).
 *
 * Trennung von `.astro`-Wrappern und Logik: Die Builder sind pure Funktionen
 * (Locale, Optionen → JSON-LD-Object). Sie sind vitest-testbar ohne
 * Astro-Rendering-Setup, während die `.astro`-Wrapper sich auf die Emission
 * eines einzigen `<script type="application/ld+json">`-Blocks beschränken.
 *
 * Quellen / Konventionen:
 *  - Schema.org-Spezifikation: https://schema.org/SoftwareApplication etc.
 *  - Google Rich Results Eligibility: bevorzugte Felder für
 *    `SoftwareApplication` (name, operatingSystem, applicationCategory,
 *    offers).
 *  - PRD §C — Schema-Markup-Ausbau (USD-Currency raus, Linux-Support,
 *    Organization mit sameAs, BreadcrumbList, HowTo, FAQPage lokalisiert).
 *  - Brand-Glossar (`src/data/brand-glossary.ts`) liefert die kanonischen
 *    Produkt-Begriffe — keine hardgecodeten Marketing-Texte.
 *  - i18n-Helper `t(lang, key)` (`src/scripts/i18n.ts`) liefert die
 *    lokalisierten Strings (Beschreibung, FAQ-Inhalte, Schritt-Texte).
 *
 * Konvention: Alle Builder produzieren ein Objekt mit `@context` und `@type`
 * an Position 1/2; weitere Felder folgen in der Reihenfolge der Schema.org-
 * Empfehlungen für maximale Lesbarkeit im Rendered-HTML.
 */

import { t, type Locale } from "../../scripts/i18n.ts";

// ---------------------------------------------------------------------------
// Gemeinsame Konstanten
// ---------------------------------------------------------------------------

/** Konstanter `@context` für alle Schemas — Schema.org-Pflicht. */
export const SCHEMA_CONTEXT = "https://schema.org" as const;

/** Site-Origin — alle Schema-URLs werden absolut gebaut. */
export const SITE_ORIGIN = "https://whispaste.de" as const;

/** Schema-IDs: stabile Identifier, damit Crawler dieselbe Entität wiedererkennen. */
export const ORGANIZATION_ID = `${SITE_ORIGIN}/#organization` as const;
export const APPLICATION_ID = `${SITE_ORIGIN}/#app` as const;

/** Kanonische GitHub-Repo-URL — Quelle: Footer.astro / Nav.astro. */
export const GITHUB_REPO_URL = "https://github.com/whispaste/whispaste" as const;

/**
 * `sameAs` für die Organization. Aktuell nur GitHub. PRD §C nennt zusätzlich
 * Mastodon — bis das Profil existiert, bleibt der Eintrag bewusst draußen,
 * weil ein 404-`sameAs` Google-Rich-Results invalidiert (siehe
 * Schema.org-Validator-Hinweise). Der Punkt ist im Issue-Evidence-Block als
 * Decision dokumentiert.
 */
export const ORGANIZATION_SAME_AS: readonly string[] = [GITHUB_REPO_URL];

/**
 * Locale → BCP-47-Code für `inLanguage`. Schema.org erlaubt BCP-47 oder ISO-
 * Sprachcodes; wir nutzen die Region-spezifische Variante, weil Google sie
 * für Locale-Targeting bevorzugt.
 */
export function inLanguageFor(locale: Locale): "de-DE" | "en-US" {
  return locale === "de" ? "de-DE" : "en-US";
}

/**
 * Locale-aware Home-URL. Astro liefert DE unter `/`, EN unter `/en/` (siehe
 * Astro-i18n-Routing in `astro.config.mjs`). Beide Endpoints sind kanonisch
 * und mit Trailing-Slash zu adressieren.
 */
export function homeUrlFor(locale: Locale): string {
  return locale === "de" ? `${SITE_ORIGIN}/` : `${SITE_ORIGIN}/en/`;
}

// ---------------------------------------------------------------------------
// SoftwareApplication
// ---------------------------------------------------------------------------

/**
 * Optionen für `buildSoftwareApplicationSchema`. Alle Felder sind optional;
 * die Defaults entsprechen dem aktuellen WhisPaste-Release (Win/macOS/Linux,
 * MIT-Lizenz, Free-Offer).
 */
export interface SoftwareApplicationOptions {
  readonly locale: Locale;
  /**
   * Beschreibung; default ist der lokalisierte `schema.app.description`-Key
   * (Glossar-konform — siehe `src/scripts/i18n.ts`).
   */
  readonly description?: string;
  /**
   * Operating-System-Liste. Default deckt die in `CONTEXT.md` §1 als „aktiv
   * unterstützt" gelisteten Plattformen ab (Windows, macOS, Linux).
   */
  readonly operatingSystems?: readonly string[];
  /**
   * Optional explizit überschreibbare Screenshot-Liste; default ist die
   * Locale-spezifische Auswahl aus `public/screenshots/<locale>/`.
   */
  readonly screenshots?: readonly string[];
}

/**
 * Default-OS-Liste — `CONTEXT.md` §1 nennt Windows, macOS und Linux als aktiv
 * unterstützte Plattformen. Die konkreten Versions-Hinweise spiegeln den
 * Stand der `download.astro`-Seite (Windows 10/11, macOS 13+) plus Linux als
 * Generic-Entry. PRD §C verlangt explizit Linux-Deklaration.
 */
export const DEFAULT_OPERATING_SYSTEMS: readonly string[] = [
  "Windows 10",
  "Windows 11",
  "macOS 13",
  "Linux",
];

/**
 * Default-Screenshot-Liste pro Locale; spiegelt die in `index.astro` bereits
 * verwendeten URLs. Die Locale-Trennung ist wichtig, weil die UI-Sprache in
 * den Screenshots sichtbar ist (DE-Workspace zeigt deutsche UI).
 */
export function defaultScreenshotsFor(locale: Locale): readonly string[] {
  const slug = locale === "de" ? "de" : "en";
  return [
    `${SITE_ORIGIN}/screenshots/${slug}/dark/01_workspace_overview.png`,
    `${SITE_ORIGIN}/screenshots/${slug}/light/02_workspace_detail.png`,
    `${SITE_ORIGIN}/screenshots/${slug}/dark/03_voice_shortcuts.png`,
    `${SITE_ORIGIN}/screenshots/${slug}/light/04_settings.png`,
    `${SITE_ORIGIN}/screenshots/${slug}/dark/05_analytics.png`,
  ];
}

/**
 * Baut das `SoftwareApplication`-Schema-Objekt. Repariert die in der PRD §C
 * gelisteten Mängel des bisherigen Inline-Schemas:
 *
 *   1. Keine USD-Currency mehr — `Offer.price = "0"` ohne `priceCurrency`
 *      ist für Free-Software laut Google-Rich-Results-Doku korrekt und löst
 *      das „Eligible for rich result" aus, ohne dass eine Pseudo-Währung
 *      gesetzt wird.
 *   2. Description aus dem Glossar (`schema.app.description`-Key), niemals
 *      hardgecoded — der Brand-Vokabular-CI-Gate prüft den Build-Output.
 *   3. Linux-Support deklariert.
 *
 * Ergebnisstruktur entspricht der Schema.org-`SoftwareApplication`-Spec:
 * https://schema.org/SoftwareApplication.
 */
export function buildSoftwareApplicationSchema(
  options: SoftwareApplicationOptions,
): Record<string, unknown> {
  const { locale } = options;
  const description = options.description ?? t(locale, "schema.app.description");
  const operatingSystem = (
    options.operatingSystems ?? DEFAULT_OPERATING_SYSTEMS
  ).join(", ");
  const screenshot = options.screenshots ?? defaultScreenshotsFor(locale);

  return {
    "@context": SCHEMA_CONTEXT,
    "@type": "SoftwareApplication",
    "@id": APPLICATION_ID,
    name: "WhisPaste",
    description,
    url: homeUrlFor(locale),
    inLanguage: inLanguageFor(locale),
    applicationCategory: "ProductivityApplication",
    operatingSystem,
    offers: {
      "@type": "Offer",
      price: "0",
      // priceCurrency bewusst weggelassen: WhisPaste ist MIT-lizenziert und
      // wird kostenlos angeboten. Google Rich Results akzeptiert
      // `price: "0"` ohne Currency als gültigen Free-Offer-Marker; das
      // bisherige `USD` war eine Fiktion (keine bezahlte WhisPaste-Variante)
      // und hätte Locale-Mismatch-Hinweise im Validator ausgelöst.
    },
    license: "https://opensource.org/licenses/MIT",
    author: {
      "@type": "Person",
      name: "Silvio Lindstedt",
    },
    publisher: { "@id": ORGANIZATION_ID },
    downloadUrl: `${GITHUB_REPO_URL}/releases/latest`,
    screenshot,
  };
}

// ---------------------------------------------------------------------------
// Organization
// ---------------------------------------------------------------------------

export interface OrganizationOptions {
  readonly locale: Locale;
  /**
   * `sameAs`-Liste; default ist die globale `ORGANIZATION_SAME_AS`-Konstante.
   * Tests dürfen die Liste überschreiben, ohne den Modul-State zu mutieren.
   */
  readonly sameAs?: readonly string[];
}

/**
 * Baut das `Organization`-Schema. Lebt im globalen `Layout.astro`, damit jede
 * Page denselben Organization-Knoten referenziert (gemeinsame Identität für
 * Knowledge-Graph-Konsolidierung in Google/Bing).
 *
 * `sameAs` nimmt aktuell nur die GitHub-Repo-URL auf — siehe Kommentar an
 * `ORGANIZATION_SAME_AS` zur Mastodon-Lücke.
 */
export function buildOrganizationSchema(
  options: OrganizationOptions,
): Record<string, unknown> {
  const { locale } = options;
  const sameAs = options.sameAs ?? ORGANIZATION_SAME_AS;
  return {
    "@context": SCHEMA_CONTEXT,
    "@type": "Organization",
    "@id": ORGANIZATION_ID,
    name: "WhisPaste",
    url: homeUrlFor(locale),
    logo: `${SITE_ORIGIN}/app-icon.png`,
    sameAs,
  };
}

// ---------------------------------------------------------------------------
// BreadcrumbList
// ---------------------------------------------------------------------------

/**
 * Ein einzelner Breadcrumb-Eintrag. `name` ist der sichtbare Label-Text (vom
 * Konsumenten lokalisiert), `item` ist die absolute URL des Knotens (oder
 * eine relative URL relativ zu `SITE_ORIGIN`, die der Builder absolutiert).
 */
export interface BreadcrumbItem {
  readonly name: string;
  readonly item: string;
}

export interface BreadcrumbListOptions {
  readonly items: readonly BreadcrumbItem[];
}

/**
 * Baut das `BreadcrumbList`-Schema. Reihenfolge der Items bestimmt die
 * `position`-Werte (1-basiert, Schema.org-Konvention).
 */
export function buildBreadcrumbListSchema(
  options: BreadcrumbListOptions,
): Record<string, unknown> {
  const itemListElement = options.items.map((entry, index) => ({
    "@type": "ListItem",
    position: index + 1,
    name: entry.name,
    item: absolutize(entry.item),
  }));
  return {
    "@context": SCHEMA_CONTEXT,
    "@type": "BreadcrumbList",
    itemListElement,
  };
}

function absolutize(url: string): string {
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  return new URL(url, SITE_ORIGIN).href;
}

// ---------------------------------------------------------------------------
// HowTo
// ---------------------------------------------------------------------------

export interface HowToStep {
  readonly name: string;
  readonly text: string;
}

export interface HowToOptions {
  readonly locale: Locale;
  /**
   * Optional Override für die Schritte. Default sind die drei Setup-Schritte
   * aus `HowItWorks.astro`, die aus dem i18n-Glossar gezogen werden — damit
   * das Schema 1:1 mit dem sichtbaren Text auf der Seite übereinstimmt
   * (Google-Rich-Results-Anforderung: HowTo-Schema-Inhalt muss visuell
   * existieren).
   */
  readonly steps?: readonly HowToStep[];
  /**
   * Optional Override für `name` (HowTo-Titel) und `description`. Defaults
   * sind die `howitworks.title` / `howitworks.desc`-Keys.
   */
  readonly name?: string;
  readonly description?: string;
}

/**
 * Default-Schritte des Setup-Flows: Hotkey drücken → sprechen → Text landet
 * am Cursor. Quelle: `HowItWorks.astro` Step-Loop, lokalisiert via i18n-Keys
 * `howitworks.stepN.title` / `howitworks.stepN.desc`.
 */
export function defaultHowToStepsFor(locale: Locale): readonly HowToStep[] {
  return [1, 2, 3].map((n) => ({
    name: t(locale, `howitworks.step${n}.title`),
    text: t(locale, `howitworks.step${n}.desc`),
  }));
}

export function buildHowToSchema(
  options: HowToOptions,
): Record<string, unknown> {
  const { locale } = options;
  const steps = options.steps ?? defaultHowToStepsFor(locale);
  const name = options.name ?? t(locale, "howitworks.title");
  const description = options.description ?? t(locale, "howitworks.desc");
  return {
    "@context": SCHEMA_CONTEXT,
    "@type": "HowTo",
    name,
    description,
    inLanguage: inLanguageFor(locale),
    step: steps.map((step, index) => ({
      "@type": "HowToStep",
      position: index + 1,
      name: step.name,
      text: step.text,
    })),
  };
}

// ---------------------------------------------------------------------------
// FAQPage
// ---------------------------------------------------------------------------

export interface FAQQuestion {
  readonly question: string;
  readonly answer: string;
}

export interface FAQPageOptions {
  readonly locale: Locale;
  /**
   * Optional explizite Liste von Fragen/Antworten. Default ist die Sequenz
   * der FAQ-Keys aus `FAQ.astro` (`free`, `offline`, `accuracy`, `sysreq`,
   * `languages`, `privacy`, `windows`, `smartscreen`, `gatekeeper`), die der
   * Builder direkt aus dem i18n-Glossar zieht.
   */
  readonly questions?: readonly FAQQuestion[];
  /**
   * Optional zur Vereinfachung: Schlüssel-Array (z. B. `["free","offline"]`),
   * das auf `faq.<key>.q` / `faq.<key>.a` mappt. Wenn beides leer ist,
   * werden die Default-Keys verwendet.
   */
  readonly questionKeys?: readonly string[];
}

/**
 * Default-Fragen für die Landing-Page-FAQ; spiegelt die `FAQ.astro`-Sequenz
 * exakt, damit der Schema-Inhalt mit dem sichtbaren FAQ-Akkordeon
 * korrespondiert (Google-Rich-Results-Anforderung).
 */
export const DEFAULT_FAQ_KEYS: readonly string[] = [
  "free",
  "offline",
  "accuracy",
  "sysreq",
  "languages",
  "privacy",
  "windows",
  "smartscreen",
  "gatekeeper",
];

export function buildFAQPageSchema(
  options: FAQPageOptions,
): Record<string, unknown> {
  const { locale } = options;
  let questions: readonly FAQQuestion[];
  if (options.questions !== undefined) {
    questions = options.questions;
  } else {
    const keys = options.questionKeys ?? DEFAULT_FAQ_KEYS;
    questions = keys.map((key) => ({
      question: t(locale, `faq.${key}.q`),
      answer: t(locale, `faq.${key}.a`),
    }));
  }
  return {
    "@context": SCHEMA_CONTEXT,
    "@type": "FAQPage",
    inLanguage: inLanguageFor(locale),
    mainEntity: questions.map((q) => ({
      "@type": "Question",
      name: q.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: q.answer,
      },
    })),
  };
}
