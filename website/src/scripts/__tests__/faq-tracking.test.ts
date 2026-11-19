// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { installFaqTracking } from '../faq-tracking';

function setup(pathname: string, html: string) {
  const doc = document.implementation.createHTMLDocument('t');
  doc.body.innerHTML = html;
  const pushed: unknown[][] = [];
  const win = { location: { pathname }, _paq: { push: (c: unknown[]) => pushed.push(c) } } as unknown as Window;
  installFaqTracking(doc, win);
  const open = (key: string, state = true) => {
    const details = doc.querySelector<HTMLDetailsElement>(`[data-faq-key="${key}"]`)!;
    details.open = state;
    details.dispatchEvent(new Event('toggle'));
  };
  return { pushed, open };
}

describe('installFaqTracking', () => {
  const html =
    '<details data-faq-key="whyPay"><summary>q</summary>a</details>' +
    '<details data-faq-key="free"><summary>q</summary>a</details>' +
    '<details><summary>not an FAQ</summary></details>';

  it('sends the question key and the language-independent page', () => {
    const { pushed, open } = setup('/en/download/', html);
    open('whyPay');
    expect(pushed).toEqual([['trackEvent', 'FAQ', 'whyPay', 'download-page']]);
  });

  it('counts each question once per page view and ignores closing', () => {
    const { pushed, open } = setup('/', html);
    open('whyPay');
    open('whyPay', false);
    open('whyPay');
    open('free');
    expect(pushed).toEqual([
      ['trackEvent', 'FAQ', 'whyPay', 'home'],
      ['trackEvent', 'FAQ', 'free', 'home'],
    ]);
  });

  it('ignores details without a question key', () => {
    const doc = document.implementation.createHTMLDocument('t');
    doc.body.innerHTML = html;
    const pushed: unknown[][] = [];
    installFaqTracking(doc, { location: { pathname: '/' }, _paq: { push: (c: unknown[]) => pushed.push(c) } } as unknown as Window);
    const plain = doc.querySelector<HTMLDetailsElement>('details:not([data-faq-key])')!;
    plain.open = true;
    plain.dispatchEvent(new Event('toggle'));
    expect(pushed).toEqual([]);
  });

  it('does nothing without Matomo (development, private pages)', () => {
    const doc = document.implementation.createHTMLDocument('t');
    doc.body.innerHTML = html;
    installFaqTracking(doc, { location: { pathname: '/' } } as unknown as Window);
    const d = doc.querySelector<HTMLDetailsElement>('details')!;
    d.open = true;
    expect(() => d.dispatchEvent(new Event('toggle'))).not.toThrow();
  });
});
