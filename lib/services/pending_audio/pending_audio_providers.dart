import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show PrivacySettings;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../audio_service.dart';
import '../audio/user_audio_dirs.dart';
import '../clipboard_history/app_clipboard.dart';
import '../drift_recording_store.dart';
import '../path_service.dart';
import 'parked_dictation_save.dart';
import 'pending_audio_notice.dart';
import 'pending_audio_queue.dart';

final _log = AppLogger('PendingAudio');

/// Whether "Aufnahmen speichern" is on. Read at call time, so a switch made
/// while the app runs applies to the next recovery or retry.
bool _historyOn(Ref ref) =>
    ref.read(settingsProvider).value?.history.saveHistory ?? true;

final pendingAudioQueueProvider = Provider<PendingAudioQueue>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  final store = ref.watch(recordingStoreProvider);
  return PendingAudioQueue(
    directory: pendingAudioDir,
    // With saving off a retried or recovered dictation is copied, not written
    // as an entry (see saveParkedDictation).
    save: (input) => saveParkedDictation(
      input,
      historyOn: _historyOn(ref),
      save: store.save,
      copyText: AppClipboard.setText,
    ),
    entryExists: (id) async => (await db.getEntry(id)) != null,
    retainAudio: (id, wavPath) => _keepForRetention(ref, db, id, wavPath),
    applyReplacements: store.applyReplacements,
  );
});

/// Moves a recovered WAV into the retained-audio folder and links it to the
/// entry, the same way a live save does, including the rotation cap. With
/// saving off there is no entry to link, so the WAV is deleted instead.
Future<void> _keepForRetention(
  Ref ref,
  HistoryDatabase db,
  String entryId,
  String wavPath,
) async {
  if (!_historyOn(ref)) {
    final stale = File(wavPath);
    if (await stale.exists()) await stale.delete();
    return;
  }
  final dir = Directory(retainedAudioDir());
  await userAudioDirs.ensure(dir.path);
  final dest = p.join(dir.path, p.basename(wavPath));
  final source = File(wavPath);
  try {
    await source.rename(dest);
  } on FileSystemException {
    await source.copy(dest);
    await source.delete();
  }
  final size = await File(dest).length();
  await db.insertAudioAttachment(
    entryId: entryId,
    filePath: dest,
    sizeBytes: size,
  );
  final evicted = await db.enforceAudioAttachmentCap();
  for (final path in evicted) {
    await ref.read(audioServiceProvider.notifier).cleanupFile(path);
  }
}

/// Retries parked dictations once, after the app has started. Reports a
/// notice only when at least one entry was saved. Never throws.
Future<void> recoverPendingAudio(
  ProviderContainer container, {
  required bool retainAudio,
  Duration parkWindow = kDefaultParkWindow,
}) async {
  // With saving off the parked dictations wait for a manual retry, which
  // copies the text. An automatic pass would overwrite the clipboard at start.
  if (!(container.read(settingsProvider).value?.history.saveHistory ?? true)) {
    return;
  }
  try {
    final result = await container
        .read(pendingAudioQueueProvider)
        .recoverAll(retainAudio: retainAudio, parkWindow: parkWindow);
    if (result.saved > 0) {
      container
          .read(pendingAudioNoticeProvider.notifier)
          .report(PendingAudioNotice.recovered);
    }
  } on Object catch (e) {
    _log.error('Recovering pending audio failed: $e');
  }
}

/// Recordings kept for a retry (UIA-FLW-01), as the Settings list shows them.
final pendingRetryListProvider = FutureProvider.autoDispose<List<PendingRetry>>(
  (ref) {
    final privacy =
        ref.watch(settingsProvider).value?.privacy ?? PrivacySettings.defaults;
    return ref
        .watch(pendingAudioQueueProvider)
        .retryEntries(
          retainAudio: privacy.retainRecentAudio,
          parkWindow: privacy.failedAudioKeepDuration,
        );
  },
);
