/// Unit tests for the centralized external-URL constants.
///
/// Pins the single source of truth for WhisPaste's public GitHub and Microsoft
/// Store destinations. Every review / CTA surface must read these values from
/// [kGitHubRepoUrl] / [kWindowsStoreReviewUrl]; the exact strings are asserted
/// here so an accidental edit in the constant surfaces as a test failure.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';

void main() {
  group('app_urls', () {
    test('kGitHubRepoUrl is the WhisPaste GitHub repository home', () {
      expect(kGitHubRepoUrl, 'https://github.com/whispaste/whispaste');
      expect(kGitHubRepoUrl, startsWith('https://github.com/whispaste/'));
    });

    test('kWindowsStoreReviewUrl is the Microsoft Store review deep-link', () {
      expect(
        kWindowsStoreReviewUrl,
        'ms-windows-store://review/?ProductId=9p22jvkrq2v0',
      );
      expect(
        kWindowsStoreReviewUrl,
        startsWith('ms-windows-store://review/?ProductId='),
      );
    });
  });
}
