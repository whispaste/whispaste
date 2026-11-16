/// Which recording error codes have a cause-and-next-step pair (#453).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  test('only the four known cases carry cause and next step', () async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    for (final code in [
      'stt_model_not_found',
      'mic_permission_denied',
      'stt_server_failed',
      'stt_server_connection_lost',
    ]) {
      final notice = recordingErrorNotice(l10n, code);
      expect(notice, isNotNull, reason: code);
      expect(notice!.cause, isNotEmpty);
      expect(notice.nextStep, isNotEmpty);
    }
    expect(recordingErrorNotice(l10n, 'transcription_empty'), isNull);
  });
}
