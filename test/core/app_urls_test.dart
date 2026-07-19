/// Unit tests for the centralized external-URL constants.
///
/// Pins the single source of truth for WhisPaste's public GitHub and Microsoft
/// Store destinations. Every review / CTA surface must read these values from
/// [kGitHubRepoUrl] / [kWindowsStoreReviewUrl] / [kGitHubSponsorsUrl] /
/// [kKofiUrl]; the exact strings are asserted here so an accidental edit in
/// the constant surfaces as a test failure.
library;

import 'dart:io';

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

    test('kGitHubSponsorsUrl is the maintainer GitHub Sponsors page', () {
      expect(kGitHubSponsorsUrl, 'https://github.com/sponsors/silvio-l');
    });

    test('kKofiUrl is the maintainer Ko-fi support page', () {
      expect(kKofiUrl, 'https://ko-fi.com/silviol');
    });
  });

  group('app_urls consumer consistency', () {
    // Verification test (grep-based): no source file outside app_urls.dart
    // may hardcode the sponsors/Ko-fi URL literals — every consumer must
    // reference the named constants instead, so a single edit here
    // propagates everywhere.
    const sponsorsLiteral = "'https://github.com/sponsors/silvio-l'";
    const kofiLiteral = "'https://ko-fi.com/silviol'";

    Iterable<File> dartFilesUnder(String dirPath) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
    }

    test(
      'no lib/ file other than app_urls.dart hardcodes the sponsors/Ko-fi URL',
      () {
        final offenders = <String>[];
        for (final file in dartFilesUnder('lib')) {
          // Directory.listSync() returns backslash-separated paths on
          // Windows, so a forward-slash-only endsWith check never matches
          // there — the file wrongly flagged itself as a violator of its own
          // rule on Windows CI. Normalize before comparing.
          if (file.path.replaceAll('\\', '/').endsWith('core/app_urls.dart')) {
            continue;
          }
          final content = file.readAsStringSync();
          if (content.contains(sponsorsLiteral) ||
              content.contains(kofiLiteral)) {
            offenders.add(file.path);
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'These files hardcode the sponsors/Ko-fi URL instead of '
              'referencing kGitHubSponsorsUrl/kKofiUrl from app_urls.dart: '
              '$offenders',
        );
      },
    );
  });
}
