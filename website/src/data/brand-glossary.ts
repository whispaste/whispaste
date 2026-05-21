/**
 * Brand-Glossar — Single Source of Truth für die kanonische Produkt-Sprache
 * der whispaste.de-Marketing-Site.
 *
 * Quellen (in Konfliktreihenfolge):
 *   1. `CONTEXT.md` §7 — Anti-Vokabular (Begriffe, die WhisPaste bewusst
 *      nicht verwendet, inkl. ihrer kanonischen Ersetzungen).
 *   2. `.scratch/seo-overhaul/prd.md` §D — Brand-Sprach-Mapping (kanonische
 *      EN/DE-Begriffe für Produkttyp, Tätigkeit, Artefakt und Verb).
 *
 * Konsumenten: alle Marketing-Texte, i18n-Strings, Schema-Komponenten und
 * — sobald implementiert — der CI-Drift-Gate sowie der `seo-audit`-Skill.
 *
 * Bei jeder Begriffs-Änderung wird ausschließlich diese Datei angefasst.
 * Anti-Vokabular-Einträge werden zusätzlich in `CONTEXT.md` §7 gepflegt;
 * diese Datei ist die maschinen-konsumierbare Spiegelung.
 */

// ---------------------------------------------------------------------------
// Kanonische Begriffe (PRD §D)
// ---------------------------------------------------------------------------

/** Produktkategorie auf Deutsch — verwendet in Hero, Schema, Title-Tags. */
export const productCategoryDE = "Sprach-Eingabe-Tool" as const;

/** Produktkategorie auf Englisch — verwendet in Hero, Schema, Title-Tags. */
export const productCategoryEN = "voice-input tool" as const;

/** Tätigkeit auf Deutsch — was der Nutzer tut. */
export const actionDE = "Spracheingabe" as const;

/** Tätigkeit auf Englisch — was der Nutzer tut. */
export const actionEN = "voice input" as const;

/** Output-Artefakt auf Deutsch — was die App produziert (sichtbar im UI). */
export const outputArtifactDE = "Transkript" as const;

/** Output-Artefakt auf Englisch — was die App produziert (sichtbar im UI). */
export const outputArtifactEN = "transcript" as const;

/** Verb auf Deutsch — was die App mit der Aufnahme macht. */
export const verbDE = "transkribiert" as const;

/**
 * Verb auf Englisch — was der Nutzer tut (Aktion-orientiert). PRD §D listet
 * zwei austauschbare Verben, kanonisch ist `speak`; `use voice input` ist die
 * längere, expliziere Variante für FAQ/Beschreibungstexte.
 */
export const verbEN = "speak" as const;

/** Alternative Lang-Variante des englischen Verbs aus PRD §D. */
export const verbENAlternative = "use voice input" as const;

// ---------------------------------------------------------------------------
// Anti-Vokabular (CONTEXT.md §7 + PRD §D)
// ---------------------------------------------------------------------------

/**
 * Eintrag im Anti-Vokabular. Wird vom CI-Drift-Gate und vom `seo-audit`-Skill
 * konsumiert, um Verstöße im Build-Output bzw. Repo zu detektieren.
 *
 * - `term`: der verbotene Begriff (case-insensitiv vergleichen).
 * - `replacement`: der kanonische Ersatz; leer (`""`) bedeutet „streichen,
 *   kein direkter 1:1-Ersatz" (siehe z. B. „Voice assistant").
 * - `rationale`: Kurzbegründung mit Quellverweis auf `CONTEXT.md` oder PRD.
 * - `contrastiveAllowed`: wenn `true`, darf der Begriff in explizit
 *   kontrastiven Sektionen (Vergleichs-/FAQ-Block) verwendet werden — der
 *   Drift-Gate respektiert dort eine Whitelist-Markierung.
 */
export interface AntiVocabularyEntry {
  readonly term: string;
  readonly replacement: string;
  readonly rationale: string;
  readonly contrastiveAllowed?: boolean;
}

/**
 * Aggregierte Liste aller verbotenen Begriffe. Reihenfolge: zuerst die
 * PRD-§D-Mappings (SEO-relevant, betreffen Title/Schema/Hero), danach die
 * weiteren CONTEXT.md-§7-Einträge.
 */
export const antiVocabulary: readonly AntiVocabularyEntry[] = [
  // --- PRD §D — SEO-Brand-Sprach-Mapping ---
  {
    term: "dictation",
    replacement: productCategoryEN, // "voice-input tool"
    rationale:
      "CONTEXT.md §7 / PRD §D — Produkttyp: WhisPaste ist explizit kein Diktier-Tool.",
    contrastiveAllowed: true,
  },
  {
    term: "dictate",
    replacement: verbEN, // "speak"
    rationale: "PRD §D — Verb: kanonisch `speak` bzw. `use voice input`.",
    contrastiveAllowed: true,
  },
  {
    term: "dictations",
    replacement: `${outputArtifactEN}s`, // "transcripts"
    rationale: "PRD §D — Artefakt: Output sind Transkripte, keine Diktate.",
  },
  {
    term: "Diktat",
    replacement: outputArtifactDE, // "Transkript"
    rationale:
      "CONTEXT.md §7 / PRD §D — Artefakt: WhisPaste produziert Transkripte.",
    contrastiveAllowed: true,
  },
  {
    term: "Diktate",
    replacement: `${outputArtifactDE}e`, // "Transkripte"
    rationale: "PRD §D — Artefakt (Plural): Transkripte statt Diktate.",
  },
  {
    term: "Diktier-Tool",
    replacement: productCategoryDE, // "Sprach-Eingabe-Tool"
    rationale:
      "CONTEXT.md §7 — Produkttyp: bewusste Abgrenzung von Diktier-Software.",
    contrastiveAllowed: true,
  },
  {
    term: "Diktat-Verlauf",
    replacement: "Verlauf",
    rationale: "PRD §D — DE-Changelog: nur `Verlauf`, nicht `Diktat-Verlauf`.",
  },
  {
    term: "Diktieren",
    replacement: actionDE, // "Spracheingabe"
    rationale:
      "PRD §D — Tätigkeit: `Spracheingabe` oder `Aufnahme starten` statt `Diktieren`.",
  },
  {
    term: "Diktiert",
    replacement: verbDE, // "transkribiert"
    rationale: "PRD §D — DE-Verb: `transkribiert` statt `diktiert`.",
  },

  // --- CONTEXT.md §7 — weitere Begriffe (nicht in PRD §D, aber Teil des
  // Anti-Vokabulars; aufgenommen für Drift-Gate-Vollständigkeit) ---
  {
    term: "Voice assistant",
    replacement: "",
    rationale:
      "CONTEXT.md §7 / §1 — WhisPaste ist nicht always-listening und nicht interpretierend.",
  },
  {
    term: "Sprachassistent",
    replacement: "",
    rationale:
      "CONTEXT.md §7 / §1 — WhisPaste ist nicht always-listening und nicht interpretierend.",
  },
  {
    term: "AI assistant",
    replacement: "",
    rationale:
      "CONTEXT.md §7 / §1 — Produkt nicht als AI-Assistant beschreiben; reine Transkription.",
  },
  {
    term: "AI agent",
    replacement: "",
    rationale:
      "CONTEXT.md §7 / §1 — Produkt nicht als AI-Agent beschreiben; reine Transkription.",
  },
  {
    term: "Voice command",
    replacement: "",
    rationale: "CONTEXT.md §7 / §1 — Output ist Text, nicht Befehl.",
  },
  {
    term: "Sprachsteuerung",
    replacement: "",
    rationale: "CONTEXT.md §7 / §1 — Output ist Text, nicht Befehl.",
  },
  {
    term: "Voice translator",
    replacement: "",
    rationale: "CONTEXT.md §7 / §1 — Transkription ist keine Übersetzung.",
  },
  {
    term: "Sprach-Übersetzer",
    replacement: "",
    rationale: "CONTEXT.md §7 / §1 — Transkription ist keine Übersetzung.",
  },
  {
    term: "Voice memo",
    replacement: "Aufnahme",
    rationale:
      "CONTEXT.md §7 / §1 — WhisPaste speichert kein dauerhaftes Audio.",
  },
  {
    term: "Sprachmemo",
    replacement: "Aufnahme",
    rationale:
      "CONTEXT.md §7 / §1 — WhisPaste speichert kein dauerhaftes Audio.",
  },
];

// ---------------------------------------------------------------------------
// Aggregierter Export-Typ für Downstream-Konsumenten
// ---------------------------------------------------------------------------

/**
 * Aggregierter Typ, der das gesamte Glossar bündelt. Konsumenten können das
 * Glossar als Single-Object importieren (`import { brandGlossary } from …`)
 * oder die Einzel-Konstanten direkt destrukturieren.
 */
export interface BrandGlossary {
  readonly productCategory: { readonly de: string; readonly en: string };
  readonly action: { readonly de: string; readonly en: string };
  readonly outputArtifact: { readonly de: string; readonly en: string };
  readonly verb: {
    readonly de: string;
    readonly en: string;
    readonly enAlternative: string;
  };
  readonly antiVocabulary: readonly AntiVocabularyEntry[];
}

export const brandGlossary: BrandGlossary = {
  productCategory: { de: productCategoryDE, en: productCategoryEN },
  action: { de: actionDE, en: actionEN },
  outputArtifact: { de: outputArtifactDE, en: outputArtifactEN },
  verb: { de: verbDE, en: verbEN, enAlternative: verbENAlternative },
  antiVocabulary,
};
