/// State of the system speech engine for the language in Settings: whether the
/// OS can run it, whether the language is supported and installed, and the
/// progress of the system asset download. Polls the native progress while a
/// download runs, refreshes when the language or the engine changes, and loads
/// the model ahead of time only while this engine is the selected one.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import 'system_speech_channel.dart';

final _log = AppLogger('SystemSpeechStatus');

class SystemSpeechStatus {
  const SystemSpeechStatus({
    this.osSupported = false,
    this.checked = false,
    this.localeSupported,
    this.installed = false,
    this.installing = false,
    this.fraction = 0,
    this.failed = false,
  });

  final bool osSupported;

  /// The capability for the configured language has been read at least once.
  final bool checked;

  /// The system's identifier for the configured language, or `null` when the
  /// system cannot transcribe it.
  final String? localeSupported;
  final bool installed;
  final bool installing;

  /// Download progress in `0..1` while [installing].
  final double fraction;

  /// The last download failed; the user can retry.
  final bool failed;

  int get percent => (fraction * 100).round();

  /// The OS can run the engine, but not for the configured language. Only
  /// known once [checked], so the state never flickers at startup.
  bool get localeUnsupported =>
      osSupported && checked && localeSupported == null;

  SystemSpeechStatus copyWith({
    bool? osSupported,
    bool? checked,
    String? localeSupported,
    bool clearLocale = false,
    bool? installed,
    bool? installing,
    double? fraction,
    bool? failed,
  }) => SystemSpeechStatus(
    osSupported: osSupported ?? this.osSupported,
    checked: checked ?? this.checked,
    localeSupported: clearLocale
        ? null
        : (localeSupported ?? this.localeSupported),
    installed: installed ?? this.installed,
    installing: installing ?? this.installing,
    fraction: fraction ?? this.fraction,
    failed: failed ?? this.failed,
  );
}

final systemSpeechChannelProvider = Provider<SystemSpeechChannel>(
  (ref) => SystemSpeechChannel(),
);

/// Whether the OS can run the engine. Overridden in tests, which run on other
/// platforms too.
final systemSpeechSupportedProvider = Provider<bool>(
  (ref) => systemSpeechOsSupported(),
);

/// Polling interval of the asset download. Shorter than a second, so the
/// progress bar moves smoothly without loading the channel.
const kSystemSpeechPollInterval = Duration(milliseconds: 500);

class SystemSpeechNotifier extends Notifier<SystemSpeechStatus> {
  Timer? _poll;

  @override
  SystemSpeechStatus build() {
    ref.onDispose(() => _poll?.cancel());
    final osSupported = ref.watch(systemSpeechSupportedProvider);
    if (osSupported) {
      ref.listen(
        settingsProvider.select(
          (s) => (s.value?.sttLanguageCode, s.value?.onDeviceEngine),
        ),
        (prev, next) {
          if (prev != next) unawaited(refresh());
        },
      );
      unawaited(refresh());
    }
    return SystemSpeechStatus(osSupported: osSupported);
  }

  SystemSpeechChannel get _channel => ref.read(systemSpeechChannelProvider);

  /// The configured language, or `null` when it is set to automatic.
  String? get _locale =>
      systemSpeechLocaleFor(ref.read(settingsProvider).value?.sttLanguageCode);

  bool get _engineSelected =>
      ref.read(settingsProvider).value?.onDeviceEngine == OnDeviceEngine.system;

  /// Reads the capability for the configured language. When this engine is the
  /// selected one, the model is loaded ahead of time.
  Future<void> refresh() async {
    // Never touch the state synchronously: build() starts this call.
    await Future<void>.value();
    // The provider can be disposed during any await (app restart, test
    // teardown); writing state then throws.
    if (!ref.mounted || !state.osSupported) return;
    final locale = _locale;
    // An automatic language is not checked against the system language; the
    // system engine hands such recordings to the local engine.
    if (locale == null) {
      state = state.copyWith(
        checked: true,
        clearLocale: true,
        installed: false,
      );
      return;
    }
    var cap = await _channel.capability(locale);
    if (!ref.mounted) return;
    _apply(cap);
    if (cap.localeSupported != null && _engineSelected) {
      // The prewarm reserves the language first. The system reports the asset
      // as installed only to a process holding that reservation, so after an
      // app restart the status is read again once the prewarm ran.
      try {
        await _channel.prewarm(locale);
      } on SystemSpeechException catch (e) {
        _log.debug('prewarm skipped: ${e.code}');
      }
      if (!cap.installed) {
        cap = await _channel.capability(locale);
        if (!ref.mounted) return;
        _apply(cap);
      }
    }
  }

  void _apply(SystemSpeechCapability cap) {
    state = state.copyWith(
      checked: true,
      localeSupported: cap.localeSupported,
      clearLocale: cap.localeSupported == null,
      installed: cap.installed,
    );
  }

  /// Starts the system asset download for the configured language. Progress
  /// is polled until the download is done or failed.
  Future<void> install() async {
    final locale = _locale;
    if (!state.osSupported || state.installing || locale == null) return;
    state = state.copyWith(installing: true, fraction: 0, failed: false);
    try {
      await _channel.installAsset(locale);
    } on SystemSpeechException catch (e) {
      _log.warning('System speech download did not start: ${e.code}');
      state = state.copyWith(installing: false, failed: true);
      return;
    }
    _poll = Timer.periodic(kSystemSpeechPollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    final SystemSpeechProgress progress;
    try {
      progress = await _channel.installProgress();
    } on SystemSpeechException catch (e) {
      _log.warning('System speech download status failed: ${e.code}');
      _finish(failed: true);
      return;
    }
    state = state.copyWith(fraction: progress.fraction);
    if (progress.state == 'done') {
      _finish(failed: false);
    } else if (progress.state == 'error') {
      _log.warning('System speech download failed: ${progress.code}');
      _finish(failed: true);
    }
  }

  void _finish({required bool failed}) {
    _poll?.cancel();
    _poll = null;
    state = state.copyWith(installing: false, failed: failed);
    unawaited(refresh());
  }
}

final systemSpeechProvider =
    NotifierProvider<SystemSpeechNotifier, SystemSpeechStatus>(
      SystemSpeechNotifier.new,
    );

/// The fallback notice to show now, or `null`. A new value each time, so a
/// repeated cause fires again after the previous notice was cleared.
class SystemSpeechFallbackNotifier extends Notifier<SystemSpeechFallback?> {
  final Set<SystemSpeechFallback> _shown = {};

  @override
  SystemSpeechFallback? build() => null;

  /// Shows the notice for [cause] once per app session. A repeated cause stays
  /// silent after its first notice, so the notice is never noisy.
  void show(SystemSpeechFallback cause) {
    if (!_shown.add(cause)) return;
    state = cause;
  }

  void clear() => state = null;
}

final systemSpeechFallbackProvider =
    NotifierProvider<SystemSpeechFallbackNotifier, SystemSpeechFallback?>(
      SystemSpeechFallbackNotifier.new,
    );
