/// How well the speech model works, per dictation (#1791): session counters
/// in the usage statistics (Matomo), never text or audio.
///
/// - `model/dictation` `<model>|<device>|<ok|fail>|<rtf class|na>`: one per
///   finished dictation ([countOutcome]);
/// - `model/redictate` `<model>|<device>`: a new recording started within
///   [kQuickRedictationWindow] after a paste ([dictationStarted]);
/// - `model/undo` `<model>|<device>|<source>`: an undo took the pasted text
///   back, either a WhisPaste undo ([recordUndoAfterPaste]) or the user's own
///   Ctrl+Z / Cmd+Z in the target app within [kUndoShortcutWindow] after an
///   auto-paste (source `shortcut`, #2078). A paste counts at most one undo;
/// - `model/undo_watch` `<model>|<device>|<watched|unknown>`: one per
///   auto-paste with the shortcut watch asked for, the base of the shortcut
///   rate; `unknown` where the platform cannot observe it (Wayland, no
///   accessibility permission, no keyboard hook).
///
/// The shortcut watch ([UndoShortcutProbe]) only runs when the caller asks
/// for it: after an auto-paste, with usage sharing on and the privacy choice
/// made. Switching usage sharing off ends it at once ([stopShortcutWatch]).
///
/// Everything goes through [telemetrySessionAggregatorProvider], so it is
/// counted in memory and only sent with usage sharing on; on a first run the
/// network gate holds it until the privacy choice (#686).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_enums.dart'
    show OnDeviceEngine, SttProviderType;
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'hardware_info_service.dart' as hw;
import 'model_hardware_telemetry.dart'
    show ownModelLookupProvider, telemetryModelKey;
import 'model_telemetry_identity.dart';
import 'speech_recommendation.dart' show ramMBProvider;
import 'stt_parakeet/parakeet_engine_notifier.dart' show parakeetEngineProvider;
import 'telemetry_model_buckets.dart';
import 'telemetry_service.dart';
import 'undo_shortcut_probe.dart';

final _log = AppLogger('DictationQualityTelemetry');

/// The model and device a dictation ran on, in telemetry values.
typedef DictationTelemetryContext = ({
  String modelKey,
  String backend,
  String device,
});

/// One paste into another app, in memory only.
final class _Paste {
  _Paste({required this.at, required this.modelKey, required this.device});

  final DateTime at;
  final String modelKey;
  final String device;

  /// An undo (WhisPaste's or the shortcut) was already counted for it.
  bool undone = false;
}

/// Extra time after [kUndoShortcutWindow] before the watch is collected, so
/// a shortcut right at the native deadline is not lost to timer jitter. The
/// native side never counts past its own deadline.
const Duration _collectGrace = Duration(seconds: 1);

/// Remembers the last paste in memory and counts the quality signals.
/// Obtain through [dictationQualityTelemetryProvider].
class DictationQualityTelemetry {
  DictationQualityTelemetry(this._ref, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _ref.onDispose(() => _watchEnd?.cancel());
  }

  final Ref _ref;
  final DateTime Function() _clock;

  _Paste? _lastPaste;

  /// The paste the native undo shortcut watch runs for, and the timer that
  /// collects it at the end of the window.
  _Paste? _watched;
  Timer? _watchEnd;

  /// The model key ([telemetryModelKey], own models included), the compute
  /// backend ([telemetryBackend]) and the device class ([deviceTier]) of a
  /// dictation with [settings].
  DictationTelemetryContext contextFor(AppSettings settings) {
    final gpu = _ref.read(hw.gpuInfoProvider).value;
    final parakeet =
        settings.sttProviderType == SttProviderType.onDevice &&
        settings.onDeviceEngine == OnDeviceEngine.parakeet;
    final backend = telemetryBackend(
      settings: settings,
      actualParakeetBackend: parakeet
          ? _ref.read(parakeetEngineProvider).backend
          : null,
      optimalBackend: gpu?.optimalBackend,
    );
    return (
      modelKey: telemetryModelKey(_ref.read(ownModelLookupProvider), settings),
      backend: backend,
      device: deviceTier(
        ramClass: ramBucket(_ref.read(ramMBProvider)),
        hasGpu: backendIsGpu(gpu?.optimalBackend),
        ranOnGpu: backendIsGpu(backend),
      ),
    );
  }

  /// `model/dictation` for a finished dictation in [context]. [rtf] is the
  /// class from [rtfBucket]; a failed run is sent with `na`.
  void countOutcome(
    DictationTelemetryContext context, {
    required bool ok,
    required String? rtf,
  }) {
    _count(
      'dictation',
      dictationQualityName(
        modelKey: context.modelKey,
        device: context.device,
        ok: ok,
        rtf: ok ? rtf : null,
      ),
    );
  }

  /// Notes that a dictation in [context] was pasted into another app. With
  /// [watchShortcut] the native watch looks for the user's own undo shortcut
  /// for [kUndoShortcutWindow]; the caller passes it only for an auto-paste
  /// with usage sharing on and the privacy choice made.
  void rememberPaste(
    DictationTelemetryContext context, {
    bool watchShortcut = false,
  }) {
    final paste = _Paste(
      at: _clock(),
      modelKey: context.modelKey,
      device: context.device,
    );
    _lastPaste = paste;
    final previous = _endWatch();
    if (!watchShortcut) {
      // Collects (and so ends) the earlier watch; nothing new is observed.
      if (previous != null) unawaited(_collect(previous));
      return;
    }
    _watched = paste;
    _watchEnd = Timer(kUndoShortcutWindow + _collectGrace, () {
      final ended = _endWatch();
      if (ended != null) unawaited(_collect(ended));
    });
    unawaited(_startWatch(paste, previous));
  }

  /// Ends the shortcut watch now and drops what it saw: usage sharing was
  /// switched off. The native side stops looking at input at once.
  void stopShortcutWatch() {
    final ended = _endWatch();
    if (ended != null) unawaited(_collect(ended, count: false));
  }

  _Paste? _endWatch() {
    _watchEnd?.cancel();
    _watchEnd = null;
    final watched = _watched;
    _watched = null;
    return watched;
  }

  Future<void> _startWatch(_Paste paste, _Paste? previous) async {
    UndoShortcutWatchStart? start;
    try {
      start = await _ref
          .read(undoShortcutProbeProvider)
          .watch(kUndoShortcutWindow);
    } catch (e) {
      // A platform without the watch: counted as unknown below.
      _log.debug('undo shortcut watch unavailable: $e');
    }
    if (previous != null && start?.seen == true) _shortcutSeen(previous);
    final watching = start?.watching == true;
    _count(
      'undo_watch',
      '${paste.modelKey}|${paste.device}|${watching ? 'watched' : 'unknown'}',
    );
    if (!watching && identical(_watched, paste)) _endWatch();
  }

  Future<void> _collect(_Paste paste, {bool count = true}) async {
    try {
      final seen = await _ref.read(undoShortcutProbeProvider).take();
      if (seen && count) _shortcutSeen(paste);
    } catch (e) {
      _log.debug('undo shortcut watch not collected: $e');
    }
  }

  /// The user pressed the undo shortcut in another app within the window
  /// after [paste]: `model/undo` with source `shortcut`, once per paste.
  void _shortcutSeen(_Paste paste) {
    if (paste.undone) return;
    paste.undone = true;
    if (identical(_lastPaste, paste)) _lastPaste = null;
    _count(
      'undo',
      '${paste.modelKey}|${paste.device}|${UndoAfterPasteSource.shortcut.id}',
    );
  }

  /// A recording starts: `model/redictate` when it follows the last paste
  /// within [kQuickRedictationWindow], a sign the pasted text was not good
  /// enough. Counted for the model that produced the pasted text; a paste
  /// counts at most once, and a paste an undo already took back not again.
  void dictationStarted() {
    final last = _lastPaste;
    _lastPaste = null;
    if (last == null) return;
    if (!isQuickRedictation(lastInsertedAt: last.at, startedAt: _clock())) {
      return;
    }
    _count('redictate', '${last.modelKey}|${last.device}');
  }

  /// `model/undo` with `<model>|<device>|<source>`: a WhisPaste undo took a
  /// dictation back right after it was pasted. Within
  /// [kUndoAfterPasteWindow] after the last paste it counts for that paste's
  /// model (once); otherwise for the model in use now, since the undo offers
  /// only appear right after an insertion. The paste is then settled: its
  /// shortcut watch ends without counting, since a WhisPaste undo may send
  /// the shortcut itself.
  void recordUndoAfterPaste(UndoAfterPasteSource source) {
    final last = _lastPaste;
    final String modelKey;
    final String device;
    if (last != null &&
        isUndoRightAfterPaste(pastedAt: last.at, now: _clock())) {
      modelKey = last.modelKey;
      device = last.device;
      last.undone = true;
      _lastPaste = null;
      if (identical(_watched, last)) {
        unawaited(_collect(_endWatch()!, count: false));
      }
    } else {
      final settings = _ref.read(settingsProvider).value;
      if (settings == null) return;
      final context = contextFor(settings);
      modelKey = context.modelKey;
      device = context.device;
    }
    _count('undo', '$modelKey|$device|${source.id}');
  }

  void _count(String action, String name) {
    if (!isTelemetrySafeName(name)) {
      _log.warning('model telemetry dropped: unsafe value for $action');
      return;
    }
    try {
      _ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'model', action: action, name: name);
    } catch (e) {
      _log.debug('model telemetry skipped: $e');
    }
  }
}

final dictationQualityTelemetryProvider = Provider<DictationQualityTelemetry>((
  ref,
) {
  final quality = DictationQualityTelemetry(ref);
  // No observation without consent: switching usage sharing off ends a
  // running shortcut watch right away.
  ref.listen(settingsProvider.select((s) => s.value?.privacy.shareUsageStats), (
    _,
    share,
  ) {
    if (share == false) quality.stopShortcutWatch();
  });
  return quality;
});
