/// Run 32 of the core review: transcribing a kept recording again that is no
/// longer kept must say so instead of the retry silently doing nothing.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart'
    show PendingRetryOutcome;
import 'package:whispaste/widgets/pending_retry_message.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('every outcome that ends without a saved text gets a message', () {
    for (final outcome in [
      PendingRetryOutcome.failed,
      PendingRetryOutcome.expired,
      PendingRetryOutcome.missing,
    ]) {
      expect(pendingRetryMessage(l10n, outcome), isNotNull, reason: '$outcome');
    }
  });

  test('a saved or silent retry, or nothing to retry, stays quiet', () {
    for (final outcome in [
      PendingRetryOutcome.saved,
      PendingRetryOutcome.empty,
      null,
    ]) {
      expect(pendingRetryMessage(l10n, outcome), isNull, reason: '$outcome');
    }
  });
}
