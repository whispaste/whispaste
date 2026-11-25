import { describe, expect, it } from 'vitest';
import { FOCUS_CLEARANCE, coveredBottom } from '../focus-unobscured';

// #1909: the bottom scroll padding that keeps focus above fixed layers
// (sticky download bar, contact teaser).
describe('coveredBottom', () => {
  it('covers the sticky bar plus clearance', () => {
    expect(coveredBottom(844, [{ top: 771, bottom: 844 }])).toBe(73 + FOCUS_CLEARANCE);
  });

  it('uses the highest layer on screen', () => {
    expect(coveredBottom(844, [{ top: 771, bottom: 844 }, { top: 533, bottom: 760 }])).toBe(311 + FOCUS_CLEARANCE);
  });

  it('is 0 without layers or with layers off screen', () => {
    expect(coveredBottom(844, [])).toBe(0);
    expect(coveredBottom(844, [{ top: 900, bottom: 970 }])).toBe(0);
    expect(coveredBottom(844, [{ top: 10, bottom: 10 }])).toBe(0);
  });
});
