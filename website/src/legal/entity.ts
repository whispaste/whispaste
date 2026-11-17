/**
 * Legal name of the provider (§ 5 DDG imprint, Art. 13 GDPR controller).
 * Single source for every legal page (#1774).
 *
 * The name is assembled from its parts on purpose. The export to the public
 * mirror anonymises the Sentry organisation slug with a pattern that also
 * matches the written-out name, and the live site is built from that mirror.
 * A literal name in a page would therefore go live as "org …". Keep the parts
 * split: `scripts/__tests__/legal-entity.test.ts` rejects any website source
 * that writes the name out in one piece, and `scripts/check-legal-entity.mjs`
 * fails the build if a built legal page does not show the full name.
 */
const PARTNERS = [["Silvio", "Lindstedt"], ["Maik", "Gräfendorf"]] as const;

export const PROVIDER_NAME = `${PARTNERS.map((p) => p.join(" ")).join(" und ")}, GbR`;

/** Placeholder in the translated privacy fragments (`src/legal/privacy/*.html`). */
export const PROVIDER_NAME_PLACEHOLDER = "{{PROVIDER_NAME}}";
