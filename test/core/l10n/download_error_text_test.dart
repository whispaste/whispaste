/// The disk-space refusal reads "benötigt X / frei Y" style in every app
/// language, with both sizes filled in.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/download_error_text.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/download_disk_space.dart';
import 'package:whispaste/services/model_download_service.dart'
    show formatModelSizeLabel;

void main() {
  const needed = 1200 * 1000 * 1000;
  const free = 300 * 1000 * 1000;
  final code = const DiskSpaceShortage(
    neededBytes: needed,
    freeBytes: free,
  ).errorCode;

  for (final locale in L10n.supportedLocales) {
    test('disk-space message is complete in ${locale.languageCode}', () {
      final l10n = lookupL10n(locale);

      final text = localizedDownloadError(l10n, code);

      expect(text, contains(formatModelSizeLabel(needed)));
      expect(text, contains(formatModelSizeLabel(free)));
      expect(text, isNot(contains('{')), reason: 'placeholders filled');
      expect(text, isNot(contains('disk_space_short')));
    });
  }

  test('German names the needed and the free size', () {
    final text = localizedDownloadError(lookupL10n(const Locale('de')), code);

    expect(text, contains('benötigt ${formatModelSizeLabel(needed)}'));
    expect(text, contains('frei ${formatModelSizeLabel(free)}'));
  });

  test('other errors pass through unchanged', () {
    final l10n = lookupL10n(const Locale('en'));

    expect(
      localizedDownloadError(l10n, 'SHA256 verification failed'),
      'SHA256 verification failed',
    );
    expect(localizedDownloadError(l10n, null), '');
  });
}
