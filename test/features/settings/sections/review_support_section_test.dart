/// The rating fallback of the support page's rate row (#395; growth review
/// R-15): a store page that cannot be opened falls back to GitHub, except on
/// the Mac App Store build. The rate and star rows themselves are covered by
/// support_page_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/features/settings/sections/review_support_section.dart';

void main() {
  group('GitHub fallback after a failed store page (growth review R-15)', () {
    test('a non-MAS build falls back to GitHub when the store page fails', () {
      expect(
        shouldFallBackToGitHub(
          launched: false,
          url: kMacAppStoreReviewUrl,
          isMasBuild: false,
        ),
        isTrue,
      );
    });

    test('a MAS build never falls back to GitHub', () {
      expect(
        shouldFallBackToGitHub(
          launched: false,
          url: kMacAppStoreReviewUrl,
          isMasBuild: true,
        ),
        isFalse,
      );
    });

    test('a successful launch never falls back', () {
      expect(
        shouldFallBackToGitHub(
          launched: true,
          url: kMacAppStoreReviewUrl,
          isMasBuild: false,
        ),
        isFalse,
      );
    });

    test('the GitHub URL itself never falls back to itself', () {
      expect(
        shouldFallBackToGitHub(
          launched: false,
          url: kGitHubRepoUrl,
          isMasBuild: false,
        ),
        isFalse,
      );
    });
  });
}
