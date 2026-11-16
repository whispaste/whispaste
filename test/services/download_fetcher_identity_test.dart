/// Guard: a download notifier keeps one [HttpModelFetcher] for its lifetime.
///
/// A getter that built a fresh fetcher on every access made
/// `cancelDownload()` and `onDispose` cancel an idle instance: the real
/// download ran on in the background while the UI showed it as cancelled,
/// and a restart appended a second writer to the same `.tmp` (UIA-RT-05).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const notifiers = [
    'lib/services/model_download_service.dart',
    'lib/services/smart_mode/smart_mode_model_download_service.dart',
    'lib/services/stt_parakeet/parakeet_download_service.dart',
    'lib/services/stt/whisper/cuda_pack.dart',
  ];

  for (final path in notifiers) {
    test('$path keeps one fetcher instead of building one per access', () {
      final source = File(path).readAsStringSync();

      expect(
        source,
        isNot(matches(RegExp(r'get\s+_fetcher\s*=>[^;]*HttpModelFetcher\('))),
      );
      expect(source, contains('late final HttpModelFetcher _fetcher'));
    });
  }
}
