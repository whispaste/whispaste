import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-facing outcome of the pending-audio queue, shown as a toast.
enum PendingAudioNotice {
  /// A dictation could not be saved to history; its audio is kept.
  saveLater,

  /// A dictation kept from an earlier session was saved to history.
  recovered,

  /// An interrupted recording could not be processed and was deleted.
  interruptedDiscarded,
}

/// Carries a [PendingAudioNotice] to the UI. The UI clears it after showing.
class PendingAudioNoticeNotifier extends Notifier<PendingAudioNotice?> {
  @override
  PendingAudioNotice? build() => null;

  void report(PendingAudioNotice notice) => state = notice;

  void clear() => state = null;
}

final pendingAudioNoticeProvider =
    NotifierProvider<PendingAudioNoticeNotifier, PendingAudioNotice?>(
      PendingAudioNoticeNotifier.new,
    );
