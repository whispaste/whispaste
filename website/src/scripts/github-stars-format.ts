/** 59 → "59", 1234 → "1.2K" / "1234" depending on the locale. Shared by build and browser. */
export function formatStars(count: number, lang: string): string {
  return new Intl.NumberFormat(lang, { notation: 'compact', maximumFractionDigits: 1 }).format(count);
}
