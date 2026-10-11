/**
 * Locale registry and cross-locale URL mapping, free of dictionaries so that
 * client scripts can import it without shipping every translation.
 *
 * German is the default locale and lives at the site root (`/download/`),
 * every other locale is prefixed (`/en/download/`, `/ru/download/`, …).
 * Non-German locales share the English slugs; only German has its own slugs
 * (`/datenschutz/` ↔ `/en/privacy/`), see `DE_SLUGS`.
 */
export type Locale = 'de' | 'en' | 'ru' | 'es' | 'pt' | 'it' | 'zh';

/** Display order of the language switcher. */
export const SUPPORTED_LOCALES: readonly Locale[] = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh'];

export const DEFAULT_LOCALE: Locale = 'de';

/** Locales served under a `/<locale>/` URL prefix (all but the default). */
export const PREFIXED_LOCALES: readonly Locale[] = SUPPORTED_LOCALES.filter((l) => l !== DEFAULT_LOCALE);

interface LocaleMeta {
  /** `<html lang>` and `hreflang` value. */
  readonly tag: string;
  /** Open Graph `og:locale`. */
  readonly ogLocale: string;
  /** Name of the language in that language (switcher label). */
  readonly nativeName: string;
  /** Short label for compact UI. */
  readonly short: string;
}

export const LOCALE_META: Record<Locale, LocaleMeta> = {
  de: { tag: 'de', ogLocale: 'de_DE', nativeName: 'Deutsch', short: 'DE' },
  en: { tag: 'en', ogLocale: 'en_US', nativeName: 'English', short: 'EN' },
  es: { tag: 'es', ogLocale: 'es_ES', nativeName: 'Español', short: 'ES' },
  pt: { tag: 'pt-BR', ogLocale: 'pt_BR', nativeName: 'Português (Brasil)', short: 'PT' },
  it: { tag: 'it', ogLocale: 'it_IT', nativeName: 'Italiano', short: 'IT' },
  ru: { tag: 'ru', ogLocale: 'ru_RU', nativeName: 'Русский', short: 'RU' },
  zh: { tag: 'zh-Hans', ogLocale: 'zh_CN', nativeName: '简体中文', short: '中文' },
};

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (SUPPORTED_LOCALES as readonly string[]).includes(value);
}

/**
 * Root-relative URL of `baseSlug` in `locale`. Pass the slug as used by that
 * locale (German slugs for `de`, English slugs for everything else).
 */
export function localePath(locale: Locale, baseSlug: string): string {
  const slug = baseSlug.replace(/^\/+|\/+$/g, '');
  if (locale === DEFAULT_LOCALE) {
    return slug.length === 0 ? '/' : `/${slug}/`;
  }
  return slug.length === 0 ? `/${locale}/` : `/${locale}/${slug}/`;
}

/** English slug → German slug, for every page whose slugs differ. */
const DE_SLUGS: Record<string, string> = {
  privacy: 'datenschutz',
  'privacy-speech-recognition': 'privatsphaere-spracherkennung',
  'gpu-compatibility': 'gpu-kompatibilitaet',
  'linux-speech-to-text': 'linux-spracherkennung',
  'whisper-model-size': 'whisper-modellgroesse',
  'comparison/whispaste-vs-system-speech-to-text': 'vergleich/whispaste-vs-system-spracheingabe',
  'comparison/voice-input-tool-alternatives': 'vergleich/diktiersoftware-alternativen',
  'use-cases/programmer': 'use-cases/programmierer',
  'use-cases/students': 'use-cases/studierende',
  'use-cases/everyday': 'use-cases/vielschreiber',
};

const EN_SLUGS: Record<string, string> = Object.fromEntries(
  Object.entries(DE_SLUGS).map(([enSlug, deSlug]) => [deSlug, enSlug]),
);

/**
 * Legal pages are only maintained in German and English (the German text is
 * binding). Other locales link to the English version.
 */
const LEGAL_SLUGS: ReadonlySet<string> = new Set(['impressum', 'privacy']);

/** Splits a root-relative pathname into its locale and the English slug. */
export function parsePath(pathname: string): { locale: Locale; slug: string } {
  const trimmed = pathname.replace(/^\/+|\/+$/g, '');
  const [first, ...rest] = trimmed.split('/');
  if (isLocale(first) && first !== DEFAULT_LOCALE) {
    return { locale: first, slug: rest.join('/') };
  }
  return { locale: DEFAULT_LOCALE, slug: EN_SLUGS[trimmed] ?? trimmed };
}

/** Locales a page (given by its English slug) is published in. */
export function localesForSlug(slug: string): readonly Locale[] {
  return LEGAL_SLUGS.has(slug) ? ['de', 'en'] : SUPPORTED_LOCALES;
}

/** URL of the page with English slug `slug` in `locale`. */
export function pathForSlug(locale: Locale, slug: string): string {
  if (locale === DEFAULT_LOCALE) return localePath(locale, DE_SLUGS[slug] ?? slug);
  if (LEGAL_SLUGS.has(slug)) return localePath('en', slug);
  return localePath(locale, slug);
}

/** Every locale's URL of the page at `pathname` (legal pages fall back to English). */
export function alternatePaths(pathname: string): Record<Locale, string> {
  const { slug } = parsePath(pathname);
  return Object.fromEntries(SUPPORTED_LOCALES.map((l) => [l, pathForSlug(l, slug)])) as Record<Locale, string>;
}

/** `getStaticPaths` result for pages under `src/pages/[lang]/`. */
export function prefixedLocalePaths(): { params: { lang: Locale } }[] {
  return PREFIXED_LOCALES.map((lang) => ({ params: { lang } }));
}

/** Narrows `Astro.currentLocale` to a supported locale (default: German). */
export function currentLocale(value: string | undefined): Locale {
  return isLocale(value) ? value : DEFAULT_LOCALE;
}
