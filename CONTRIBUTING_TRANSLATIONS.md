# Translating WhisPaste

WhisPaste is used by people who dictate all day, so its interface should speak
their language. Translations are welcome: fixing a single string helps as
much as adding a whole new language.

The general contribution flow (fork, branch, pull request, gate commands) is
described in [CONTRIBUTING.md](CONTRIBUTING.md). This page covers what is
specific to translations.

## How the strings are organized

- All UI strings live in [ARB files](https://github.com/google/app-resource-bundle)
  under `lib/core/l10n/`, one file per language: `app_en.arb`, `app_de.arb`,
  `app_he.arb`, `app_ru.arb`, …
- **`app_en.arb` is the source of truth.** Every other file must contain
  exactly the same message keys, no more and no fewer.
- Entries starting with `@` (for example `"@settingsAutomationApiStatusRunning"`)
  are metadata: descriptions and placeholder types. They only need to exist in
  `app_en.arb`. You do not have to copy them into your language file.
- `lib/core/l10n/generated/` is generated code. Do not edit it by hand;
  regenerate it with `flutter gen-l10n` after changing any ARB file and commit
  the result together with your ARB change.

## Improving an existing translation

1. Find the key in `app_en.arb` (search for the English text), then change
   the value of the same key in your language's file.
2. Run `flutter gen-l10n`.
3. Run the parity gate (see below) and open a pull request.

## Adding a new language

1. Copy `app_en.arb` to `app_<code>.arb`, where `<code>` is the
   [ISO 639-1 language code](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
   (for example `app_fr.arb`). Use the plain language code, without a
   region: Brazilian Portuguese goes into `app_pt.arb`, Simplified Chinese
   into `app_zh.arb`.
2. Set `"@@locale"` at the top of the file to the same code.
3. Translate every value. You may delete the `@`-metadata entries.
4. Add the language's own name (its endonym, for example `Français`) to
   `lib/core/l10n/locale_native_name.dart`. The language picker shows it.
5. Run `flutter gen-l10n`. The new language then appears in
   `L10n.supportedLocales` and in the in-app language picker automatically.
6. Run the gate commands from [CONTRIBUTING.md](CONTRIBUTING.md), including
   the parity gate below, and open a pull request.

A partial translation is fine as a first step. List the keys you have not
translated yet in the parity baseline (see below), and they fall back to
English until someone fills them in.

## Placeholders and plurals

Values can contain placeholders in curly braces. Keep them exactly as they
are, only move them to where your grammar needs them:

```json
"settingsAutomationApiStatusRunning": "Running on port {port}"
```

Never translate the name inside the braces (`{port}` stays `{port}`), and
never drop a placeholder: the number or name would then be missing in the UI.

Counts use [ICU plural syntax](https://unicode-org.github.io/icu/userguide/format_parse/messages/).
Use the plural categories your language actually has according to
[CLDR](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html),
and always include `other`:

```json
"wordCount": "{count, plural, one{{count} word} other{{count} words}}"
```

Russian, for example, needs `one`, `few`, `many` and `other`. You may use plural
syntax in your language even where the English string is a plain
`{count} …` placeholder: grammar differs, and the generator handles it per
language.

## What stays untranslated

- The product name **WhisPaste**.
- Keyboard shortcuts (`⌘V / Ctrl+V`), addresses (`127.0.0.1`), HTTP headers
  (`Authorization: Bearer <token>`) and command names such as `curl`.
- **Spoken voice commands** such as `tag:`, `correct:` and `korrektur:`. The app
  matches these words literally in the transcript, so a translated keyword
  would not work. Quote them unchanged and explain them in your language
  around them.

When in doubt, check how the same term is already translated elsewhere in your
language's file and stay consistent with it.

## Right-to-left languages

Hebrew is already supported, and Arabic, Persian or Urdu work the same way.
Flutter mirrors the whole layout automatically for right-to-left locales, so
translators only provide the text. A few things to keep in mind:

- Latin snippets inside RTL text (shortcuts, `API`, quoted voice commands) are
  fine. Check in the running app that punctuation around them lands where you
  expect, and prefer short, self-contained Latin fragments.
- Keep placeholders as they are; the bidirectional algorithm places numbers
  correctly.

For code contributors: use direction-aware widgets and values
(`EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end` instead of
`left`/`right`) so new UI mirrors correctly.

## The parity gate

Every ARB file must have the same keys as `app_en.arb`. The check runs in the
pre-commit hook and in CI, and you can run it yourself from the repo root:

```bash
dart tool/check_arb_parity.dart
```

It fails on:

- a key that exists in `app_en.arb` but is **missing** in a language file,
- a key in a language file that `app_en.arb` **does not have** (usually a
  leftover from a removed feature, delete it),
- a **stale baseline entry** (see below).

### The baseline (intentional English fallbacks)

`lib/core/l10n/arb_parity_baseline.json` lists keys that are allowed to be
missing, per language:

```json
{
  "fr": ["settingsAutomationApiTokenSubtitle"]
}
```

A listed key falls back to English at runtime. Use the baseline only for
known, accepted gaps, such as a new language that is not complete yet, or a
string that is intentionally kept in English. Say why in your pull request.

The baseline is a ratchet: it can only shrink. As soon as a listed key is
translated (or removed from `app_en.arb`), the gate asks you to remove the
entry, so a closed gap cannot silently reopen. The goal is an empty baseline
(`{}`).

## Review

Translation pull requests are checked for:

1. **Parity gate green** and `flutter gen-l10n` output committed.
2. **Placeholders and plural forms intact** (the generator fails on broken ICU
   syntax).
3. **Native-speaker review.** Ideally a second native speaker reads the
   changes. If you know one, mention them in the pull request.
4. **Length and tone.** Buttons, chips and the status bar have little room, so
   keep those strings short. Follow the tone your language file already uses
   (for example, informal or formal address) and keep terminology consistent.
5. **A look in the running app** for new languages, especially right-to-left
   ones: switch the language in Settings and check the main screens.

## Wanted languages

Besides English, German, Hebrew and Russian, we would especially welcome
Spanish, French, Italian, Brazilian Portuguese, Polish, Chinese (Simplified),
Japanese, Korean, Turkish, Dutch and Ukrainian. Any other language is welcome
too.
