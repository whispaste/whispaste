// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest';
import {
  APPLY_CARRIED_REFERRER_JS,
  REFERRER_CARRY_KEY,
  REFERRER_CARRY_MAX_AGE_MS,
  rememberReferrer,
} from '../referrer-carry';

// Runs the inline Matomo snippet against a given path and returns the queue.
function applyOn(pathname: string): unknown[][] {
  const _paq: unknown[][] = [];
  const location = { pathname };
  new Function('_paq', 'location', 'sessionStorage', APPLY_CARRIED_REFERRER_JS)(_paq, location, sessionStorage);
  return _paq;
}

describe('referrer carry across the language redirect', () => {
  beforeEach(() => sessionStorage.clear());

  it('hands the original referrer to Matomo on the target page and forgets it', () => {
    rememberReferrer('/en/whisper-desktop/', sessionStorage, 'https://www.google.com/');
    expect(applyOn('/en/whisper-desktop/')).toEqual([['setReferrerUrl', 'https://www.google.com/']]);
    expect(sessionStorage.getItem(REFERRER_CARRY_KEY)).toBeNull();
    expect(applyOn('/en/whisper-desktop/')).toEqual([]);
  });

  it('keeps a direct entry direct (empty referrer instead of whispaste.de)', () => {
    rememberReferrer('/fr/', sessionStorage, '');
    expect(applyOn('/fr/')).toEqual([['setReferrerUrl', '']]);
  });

  it('ignores the entry on any other path and after it expired', () => {
    rememberReferrer('/fr/', sessionStorage, 'https://chatgpt.com/');
    expect(applyOn('/fr/download/')).toEqual([]);
    rememberReferrer('/fr/', sessionStorage, 'https://chatgpt.com/', Date.now() - REFERRER_CARRY_MAX_AGE_MS - 1);
    expect(applyOn('/fr/')).toEqual([]);
  });

  it('survives broken or missing storage content', () => {
    sessionStorage.setItem(REFERRER_CARRY_KEY, '{not json');
    expect(applyOn('/')).toEqual([]);
    expect(applyOn('/')).toEqual([]);
  });
});
