# MS Store Listing Content

Store listing texts for WhisPaste. Checked into the repo so changes are versioned.
Most fields are pushed to Partner Center via a manual local CSV import (see below);
`ReleaseNotes` alone is refreshed automatically during a real MSIX release, via the
release API.

## Structure

```
store/
  defaults.json               sprachneutral (Title, VoiceTitle, DevStudio) + locale→column map
  en-US/description.txt       Description           (required)
  en-US/short-description.txt ShortDescription      (required)
  en-US/features.txt          Feature1..N, one bullet per line (max 200 chars each)
  en-US/search-terms.txt      SearchTerm1..N, one term per line
  en-US/release-notes.txt     ReleaseNotes ("What's new") — defaults to changelog link
  en-US/copyright.txt         CopyrightTrademarkInformation
  en-US/license-terms.txt     AdditionalLicenseTerms
  de-DE/…                     same files, German
```

Optional files (skipped if absent): `short-title.txt`, `sort-title.txt`,
`minimum-hardware.txt`, `recommended-hardware.txt`.

## Updating store listing text (local CSV import)

Text changes are made here in the repo (versioned, git-diff-able) and pushed to
Partner Center via a compact **import CSV** — no manual field-fiddling in the
dashboard. This is a purely local workflow; it runs no GitHub Action and never
touches screenshots, logos, trailers, or their internal asset URLs.

1. Edit the relevant `.txt` / `defaults.json`.
2. Build the import CSV (writes to the gitignored `store/_build/`):

   ```
   node scripts/generate-store-listing.mjs        # → store/_build/listing-import.csv
   node scripts/generate-store-listing.mjs --check # validate only, write nothing
   ```

3. In Partner Center → app overview → **Import listings** → **Import .csv** →
   upload `store/_build/listing-import.csv`. Resolve any reported errors, repeat.

The generator emits only the text rows it manages (per MS docs, an import CSV may
contain just the rows you edit); every other field — screenshots, logos, captions,
hardware requirements — stays untouched in Partner Center.

"What's new" (ReleaseNotes) can follow two paths: the local CSV path above
(`release-notes.txt`), or the AI-generated notes injected automatically by the
release API during a real MSIX release. The API path wins during a normal
release; the CSV path is for standalone listing-text refreshes.

## Release / submission

Listing text is maintained here and turned into an import CSV locally
(`scripts/generate-store-listing.mjs`, see above). The CSV is uploaded by hand
via Partner Center → "Import listings".

The previous GitHub-based MS Store auto-submission (`scripts/submit-ms-store.ps1`,
the `submit-ms-store` job in `release.yml`, and `ms-store-credential-health.yml`)
has been removed — the release flow runs locally on macOS now.
