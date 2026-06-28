/// Tests for the store thank-you hint.
///
/// Locale content (AC — forbidden word rule):
///   The hint title and body in DE/EN/HE must NOT contain any of:
///   kauf, gekauft, preis, bezahlt, gratis, kostenlos, open source, github.
///   (Case-insensitive. Checked against the generated localizations directly —
///   no Flutter widget pump required.)
///
/// CTA URL sourcing (AC — single-source constants):
///   Verifies [kWindowsStoreReviewUrl] is the MS-Store deep-link and
///   [kGitHubRepoUrl] is the WhisPaste GitHub repo — both used verbatim in
///   the watcher without hardcoded literals.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_he.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Locale content assertions — pure (no Flutter widgets needed)
  // ---------------------------------------------------------------------------

  group('storeThankYou locale strings — forbidden word check', () {
    /// Words that MUST NOT appear in the hint title or body text (any locale).
    ///
    /// Rationale:
    ///   - kauf/gekauft/preis/bezahlt: refund-protection — must not imply the
    ///     user paid or refer to a purchase transaction.
    ///   - gratis/kostenlos/open source/github: must not mention the free /
    ///     open-source alternative and thereby hint at refund eligibility.
    const forbidden = [
      'kauf',
      'gekauft',
      'preis',
      'bezahlt',
      'gratis',
      'kostenlos',
      'open source',
      'github',
    ];

    final locales = [L10nDe(), L10nEn(), L10nHe()];

    for (final l10n in locales) {
      test('${l10n.localeName}: storeThankYouTitle + storeThankYouBody '
          'contain no forbidden words', () {
        final text = '${l10n.storeThankYouTitle} ${l10n.storeThankYouBody}'
            .toLowerCase();

        for (final word in forbidden) {
          expect(
            text.contains(word),
            isFalse,
            reason:
                'Locale "${l10n.localeName}" contains forbidden word '
                '"$word" in storeThankYouTitle / storeThankYouBody. '
                'Full text: "$text"',
          );
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  // CTA URL sourcing — single-source constants (no hardcoded literals)
  // ---------------------------------------------------------------------------

  group('storeThankYou CTA URL constants', () {
    test(
      'kWindowsStoreReviewUrl is the MS Store review deep-link (store CTA source)',
      () {
        expect(kWindowsStoreReviewUrl, startsWith('ms-windows-store://'));
        expect(kWindowsStoreReviewUrl, contains('ProductId='));
      },
    );

    test(
      'kGitHubRepoUrl is the WhisPaste GitHub repo (GitHub star CTA source)',
      () {
        expect(kGitHubRepoUrl, startsWith('https://github.com/'));
        expect(kGitHubRepoUrl, contains('whispaste'));
      },
    );
  });
}
