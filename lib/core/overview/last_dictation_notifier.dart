/// The last dictation's processing, kept for the overview's "Letztes Diktat"
/// block. Written once per finished dictation (after its text is out), read
/// only while the overview is shown; the value survives a restart.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../logging/app_logger.dart';
import 'last_dictation.dart';

final _log = AppLogger('LastDictation');

/// App-settings key of the stored [LastDictation].
const kLastDictationSetting = 'overview_last_dictation';

class LastDictationNotifier extends Notifier<LastDictation?> {
  @override
  LastDictation? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    try {
      final stored = LastDictation.decode(
        await ref
            .read(historyDatabaseProvider)
            .readAppSetting(kLastDictationSetting),
      );
      // A dictation recorded while the stored value was still loading wins.
      state ??= stored;
    } on Object catch (e) {
      _log.debug('Last dictation not loaded (non-fatal): $e');
    }
  }

  /// Remembers [value] as the last dictation. The write is best effort: a
  /// lost value only means the block shows the previous dictation.
  Future<void> record(LastDictation value) async {
    state = value;
    try {
      await ref
          .read(historyDatabaseProvider)
          .writeAppSetting(kLastDictationSetting, value.encode());
    } on Object catch (e) {
      _log.debug('Last dictation not saved (non-fatal): $e');
    }
  }
}

final lastDictationProvider =
    NotifierProvider<LastDictationNotifier, LastDictation?>(
      LastDictationNotifier.new,
    );
