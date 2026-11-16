/// A speech model download started from a card shows its progress at the
/// pill (#877).
///
/// The card closes on the click, so without this the user only saw a short
/// "Downloading…" and then nothing until the next dictation. While a download
/// the card started runs, every new whole percent replaces the pill hint, and
/// the end says the model is ready. A failed download stops quietly: the
/// download service reports its error on its own.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model_download_service.dart';
import '../stt_parakeet/parakeet_download_service.dart';
import 'pill_hint.dart';

/// Pill hint id of the progress, for logs and tests.
const String kDownloadPillHintId = 'model-download';

/// The last percent shown at the pill while a card's download is followed,
/// `null` while nothing is followed.
class DownloadPillProgressNotifier extends Notifier<int?> {
  String Function(int percent)? _progressText;
  String? _readyText;
  bool _sawBusy = false;

  @override
  int? build() {
    ref.listen<ModelDownloadState>(
      modelDownloadProvider,
      (_, s) => _onUpdate(
        busy: s.isBusy,
        percent: s.progressPercent,
        failed: s.phase == DownloadPhase.error,
      ),
    );
    ref.listen<ParakeetDownloadState>(
      parakeetDownloadProvider,
      (_, s) => _onUpdate(
        busy: s.isBusy,
        percent: s.progressPercent,
        failed: s.phase == ParakeetDownloadPhase.error,
      ),
    );
    return null;
  }

  /// Follows the next download until it ends. Called by the card's download
  /// button right before the download starts.
  void follow({
    required String Function(int percent) progressText,
    required String readyText,
  }) {
    _progressText = progressText;
    _readyText = readyText;
    _sawBusy = false;
    state = -1;
  }

  bool get _following => state != null && _progressText != null;

  void _onUpdate({
    required bool busy,
    required int percent,
    required bool failed,
  }) {
    if (!_following) return;
    if (busy) {
      _sawBusy = true;
      final p = percent.clamp(0, 100);
      if (p == state) return;
      state = p;
      _show(_progressText!(p));
      return;
    }
    // Idle before the download began: not the end yet.
    if (!_sawBusy) return;
    final ready = _readyText;
    _stop();
    if (!failed && ready != null) _show(ready);
  }

  void _show(String text) => ref
      .read(overlayPillHintProvider.notifier)
      .show(id: kDownloadPillHintId, text: text);

  void _stop() {
    _progressText = null;
    _readyText = null;
    _sawBusy = false;
    state = null;
  }
}

final downloadPillProgressProvider =
    NotifierProvider<DownloadPillProgressNotifier, int?>(
      DownloadPillProgressNotifier.new,
    );
