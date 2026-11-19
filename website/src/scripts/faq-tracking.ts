/**
 * Matomo event "FAQ / <question key> / <page>" when a visitor opens an FAQ
 * answer (home FAQ, purchase FAQ on the download page, whisper-desktop FAQ).
 * It answers which purchase questions people read before a store click, e.g.
 * whether "Why pay?" is opened on the page that sells. Only the fixed question
 * key and the language-independent page name are sent: no text, no URL
 * parameters, no personal data (internal-notes). Each question
 * counts once per page view, so toggling it open and shut does not inflate it.
 */
import { placementForPath } from './download-tracking.ts';

export const FAQ_EVENT_CATEGORY = 'FAQ';
export const FAQ_KEY_ATTRIBUTE = 'data-faq-key';

type Paq = { push: (command: unknown[]) => void };

export function installFaqTracking(doc: Document = document, win: Window = window): void {
  const page = placementForPath(win.location.pathname);
  const seen = new Set<string>();
  // `toggle` does not bubble; the capture phase still sees it on document.
  doc.addEventListener(
    'toggle',
    (event) => {
      const details = event.target;
      if (!(details instanceof HTMLDetailsElement) || !details.open) return;
      const key = details.getAttribute(FAQ_KEY_ATTRIBUTE);
      if (!key || seen.has(key)) return;
      seen.add(key);
      const paq = (win as unknown as { _paq?: Paq })._paq;
      paq?.push(['trackEvent', FAQ_EVENT_CATEGORY, key, page]);
    },
    true,
  );
}
