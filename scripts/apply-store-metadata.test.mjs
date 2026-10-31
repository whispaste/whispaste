import { test } from 'node:test';
import assert from 'node:assert/strict';

import { repairMsstoreJson, mergeManagedMetadata } from './apply-store-metadata.mjs';

test('repairMsstoreJson strips ANSI codes and CLI banner text before the JSON body', () => {
  const raw = 'Retrieving Submission\nFound \x1b[38;5;2mPending Submission\x1b[0m.\n{"Id":"1"}';
  const repaired = repairMsstoreJson(raw);
  assert.equal(JSON.parse(repaired).Id, '1');
});

test('repairMsstoreJson escapes a raw newline the CLI wrapped inside a string value', () => {
  const raw = '{\n  "Description": "line one \nline two"\n}';
  const repaired = repairMsstoreJson(raw);
  const parsed = JSON.parse(repaired);
  assert.equal(parsed.Description, 'line one  line two');
});

test('repairMsstoreJson leaves structural newlines (outside strings) untouched', () => {
  const raw = '{\n  "A": "x",\n  "B": "y"\n}';
  const parsed = JSON.parse(repairMsstoreJson(raw));
  assert.deepEqual(parsed, { A: 'x', B: 'y' });
});

test('repairMsstoreJson preserves escaped quotes inside a string', () => {
  const raw = '{"Description": "she said \\"hi\\"\nto me"}';
  const parsed = JSON.parse(repairMsstoreJson(raw));
  assert.equal(parsed.Description, 'she said "hi" to me');
});

test('repairMsstoreJson throws a clear error when no JSON object is found', () => {
  assert.throws(() => repairMsstoreJson('no braces here'), /No JSON object found/);
});

test('mergeManagedMetadata leaves Pricing completely untouched (Pricing V2 account, API can\'t write it)', () => {
  const submission = {
    Pricing: { TrialPeriod: 'NoFreeTrial', PriceId: 'Free', IsAdvancedPricingModel: true },
    Listings: {
      'en-us': { BaseListing: { Title: 'Old', Images: ['a.png'] } },
      de: { BaseListing: { Title: 'Alt', Images: ['b.png'] } },
    },
    ApplicationPackages: ['unrelated'],
  };
  const managed = {
    listings: {
      'en-us': { Title: 'New', Description: 'desc', Features: ['f1'], Keywords: ['k1'], ReleaseNotes: 'rn' },
      de: { Title: 'Neu', Description: 'beschr', Features: ['f1de'], Keywords: ['k1de'], ReleaseNotes: 'rnde' },
    },
  };

  const merged = mergeManagedMetadata(submission, managed);

  assert.deepEqual(
    merged.Pricing,
    { TrialPeriod: 'NoFreeTrial', PriceId: 'Free', IsAdvancedPricingModel: true },
    'Pricing survives byte-for-byte — this script must never attempt to write it',
  );

  assert.equal(merged.Listings['en-us'].BaseListing.Title, 'New');
  assert.equal(merged.Listings['en-us'].BaseListing.Description, 'desc');
  assert.deepEqual(merged.Listings['en-us'].BaseListing.Images, ['a.png'], 'unmanaged listing fields survive');
  assert.equal(merged.Listings.de.BaseListing.Title, 'Neu');

  assert.deepEqual(merged.ApplicationPackages, ['unrelated'], 'unrelated top-level fields survive untouched');
});

test('mergeManagedMetadata does not mutate the input submission object', () => {
  const submission = {
    Pricing: { PriceId: 'Free' },
    Listings: { 'en-us': { BaseListing: { Title: 'Old' } }, de: { BaseListing: { Title: 'Alt' } } },
  };
  const managed = {
    listings: {
      'en-us': { Title: 'New', Description: '', Features: [], Keywords: [], ReleaseNotes: '' },
      de: { Title: 'Neu', Description: '', Features: [], Keywords: [], ReleaseNotes: '' },
    },
  };

  mergeManagedMetadata(submission, managed);

  assert.equal(submission.Pricing.PriceId, 'Free', 'original input left untouched');
  assert.equal(submission.Listings['en-us'].BaseListing.Title, 'Old');
});

test('mergeManagedMetadata throws if the submission is missing a managed locale', () => {
  const submission = { Pricing: {}, Listings: { 'en-us': { BaseListing: {} } } };
  const managed = {
    listings: {
      'en-us': { Title: 'x', Description: '', Features: [], Keywords: [], ReleaseNotes: '' },
      de: { Title: 'x', Description: '', Features: [], Keywords: [], ReleaseNotes: '' },
    },
  };
  assert.throws(() => mergeManagedMetadata(submission, managed), /no "de" listing/);
});
