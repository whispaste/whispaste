/// Typed onboarding v6 events for Matomo, one method per event of the
/// taxonomy in `internal-notes`
/// §3.1/§3.2.
///
/// Every category, action and name comes from an enum, a fixed bucket or a
/// value checked against a narrow pattern, so no free text, path, device
/// name, app name or user text can reach the wire. Events go through
/// [OnboardingTelemetryBuffer]: held in memory until the privacy choice is
/// committed when the onboarding completes on screen 7 ([consentDecided]),
/// then sent or dropped; the consent gate of
/// `TelemetryService` still apply per event.
///
/// One stream: the onboarding overlay sends the funnel, the pages their side
/// events. A review or a revision run never feeds the first-run funnel; it
/// has its own [rerun] events. The speech-model choice is not here: it goes
/// out once as `onboarding/model_chosen` from `ModelHardwareTelemetry` (T1),
/// with the recommendation it was measured against.
///
/// Timing lives here too: [stepShown] starts the dwell clock of a screen and
/// [stepNext]/[stepSkip]/[stepBack]/[paused]/[quit] end it with a
/// `step_time` bucket; the time to the first dictation is measured from the
/// first welcome screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'telemetry_service.dart';

/// The seven onboarding v6 pages, by their wire id. The model view is no
/// page of its own; opening it is [OnboardingTelemetry.modelSwitchOpened].
enum OnboardingScreen {
  welcome('welcome'),
  about('about_you'),
  access('paste_access'),
  mic('mic'),
  hotkey('hotkey'),
  tryOut('first_dictation'),
  privacy('privacy');

  const OnboardingScreen(this.id);
  final String id;
}

/// A run over an already set-up app: Settings → "Einführung ansehen", or the
/// revision run after an update. Its events stay apart from the funnel.
enum OnboardingRerun { review, revision }

enum OnboardingRerunEvent { step, exit, complete }

/// Job chips on screen 2 (multi-select). Nothing selected is sent as `none`.
enum OnboardingRole { writing, dev, legal, education, business, other }

/// "How did you find us?" chips on screen 2 (single choice). `none` = skipped.
enum OnboardingAttribution {
  search,
  ai,
  friend,
  store,
  social,
  video,
  github,
  other,
  none,
}

/// What happened to the prefilled first name. The name itself never leaves.
enum OnboardingNameEdit { kept, edited, cleared }

enum OnboardingHotkeyMode { hold, toggle }

/// Shape of the chosen hotkey, never the keys.
enum OnboardingHotkeyShape { modifierOnly, combo }

enum OnboardingHotkeyResult { recognized, conflict, notRecognized }

enum OnboardingPermission { mic, pasteAccess }

enum OnboardingPermissionResult {
  granted,
  denied,
  already,
  later,
  continuedWithout,
  helperShown,
  notNeeded,
}

enum OnboardingDownloadEvent { started, done, failed, retried, cancelled }

enum OnboardingDownloadFailure { network, disk, checksum, other }

enum OnboardingFirstDictation { ok, failed, waitedForModel }

/// Upper limits and labels, checked in order; past the last limit [over].
String _bucket(num value, List<(num, String)> limits, String over) {
  for (final (limit, label) in limits) {
    if (value < limit) return label;
  }
  return over;
}

/// Dwell time on one screen.
String dwellBucket(Duration d) => _bucket(d.inMilliseconds / 1000, const [
  (5, 'lt5s'),
  (15, '5_15s'),
  (60, '15_60s'),
  (180, '1_3m'),
], 'gt3m');

/// Time from the first welcome screen to the first dictation.
String ttfdBucket(Duration d) => _bucket(d.inMilliseconds / 60000, const [
  (2, 'lt2m'),
  (5, '2_5m'),
  (10, '5_10m'),
  (30, '10_30m'),
], 'gt30m');

final _languageCode = RegExp(r'^[a-z]{2,3}$');
final _modelId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,47}$');
final _failureCode = RegExp(r'^[a-z0-9_]{1,32}$');

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Sends one event; the buffer's `track` in the app.
typedef OnboardingTrackFn =
    void Function({
      required String category,
      required String action,
      String? name,
    });

final class OnboardingTelemetry {
  OnboardingTelemetry({
    required this._track,
    required this._decide,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OnboardingTrackFn _track;
  final void Function({required bool shareUsageStats}) _decide;
  final DateTime Function() _clock;

  OnboardingScreen? _current;
  DateTime? _shownAt;
  DateTime? _welcomeAt;
  bool _ttfdSent = false;

  void _emit(String category, String action, [String? name]) =>
      _track(category: category, action: action, name: name);

  /// The usage-statistics choice, committed when the onboarding completes:
  /// sends the held events once, or drops them. Later calls change nothing.
  void consentDecided({required bool shareUsageStats}) =>
      _decide(shareUsageStats: shareUsageStats);

  // Funnel

  /// Screen visible. Action stays `step`, the name the existing Matomo
  /// reports use for the per-step funnel.
  void stepShown(OnboardingScreen screen) {
    _endDwell();
    _current = screen;
    _shownAt = _clock();
    if (screen == OnboardingScreen.welcome) _welcomeAt ??= _shownAt;
    _emit('onboarding', 'step', screen.id);
  }

  void stepNext(OnboardingScreen screen) => _leave('step_next', screen);
  void stepSkip(OnboardingScreen screen) => _leave('step_skip', screen);
  void stepBack(OnboardingScreen screen) => _leave('step_back', screen);
  void paused(OnboardingScreen screen) => _leave('paused', screen);
  void quit(OnboardingScreen screen) => _leave('quit', screen);

  /// The main action of the closing page that starts WhisPaste.
  void complete() {
    _leave('step_next', OnboardingScreen.privacy);
    _emit('onboarding', 'complete');
  }

  /// A page shown, an early exit or the end of a review or revision run, as
  /// `review_step`, `revision_exit` and so on.
  void rerun(
    OnboardingRerun run,
    OnboardingRerunEvent event,
    OnboardingScreen screen,
  ) => _emit('onboarding', '${run.name}_${event.name}', screen.id);

  void _leave(String action, OnboardingScreen screen) {
    _emit('onboarding', action, screen.id);
    if (_current == screen) _endDwell();
  }

  void _endDwell() {
    final screen = _current;
    final at = _shownAt;
    if (screen == null || at == null) return;
    _emit(
      'onboarding',
      'step_time',
      '${screen.id}:${dwellBucket(_clock().difference(at))}',
    );
    _current = null;
    _shownAt = null;
  }

  // Side actions

  void contactOpened(OnboardingScreen screen) =>
      _emit('onboarding', 'contact_opened', screen.id);

  void modelSwitchOpened(OnboardingScreen screen) =>
      _emit('onboarding', 'model_switch_opened', screen.id);

  /// [code] is `auto` or an ISO 639 code; anything else is sent as `other`.
  void dictationLanguageChanged(String code) => _emit(
    'onboarding',
    'dictation_language_changed',
    code == 'auto' || _languageCode.hasMatch(code) ? code : 'other',
  );

  /// Call once when screen 2 is left: one `role` event per selected role, in
  /// enum order, so Matomo counts each role on its own; none selected sends a
  /// single `none`.
  void roles(Set<OnboardingRole> roles) {
    if (roles.isEmpty) {
      _emit('onboarding', 'role', 'none');
      return;
    }
    for (final role in OnboardingRole.values) {
      if (roles.contains(role)) _emit('onboarding', 'role', role.name);
    }
  }

  void attribution(OnboardingAttribution source) =>
      _emit('onboarding', 'attribution', source.name);

  void nameEdit(OnboardingNameEdit edit) =>
      _emit('onboarding', 'name', edit.name);

  void hotkeyChosen(OnboardingHotkeyMode mode, OnboardingHotkeyShape shape) =>
      _emit(
        'onboarding',
        'hotkey_chosen',
        '${mode.name}:${_snake(shape.name)}',
      );

  void hotkeyResult(OnboardingHotkeyResult result) =>
      _emit('onboarding', 'hotkey_result', _snake(result.name));

  void introSound({required bool played}) =>
      _emit('onboarding', 'intro_sound', played ? 'played' : 'muted');

  void permission(
    OnboardingPermission kind,
    OnboardingPermissionResult result,
  ) => _emit('permission', _snake(kind.name), _snake(result.name));

  void micLevel({required bool detected}) =>
      _emit('permission', 'mic_level', detected ? 'detected' : 'timeout');

  /// Counted only; the device name never leaves.
  void micDeviceChanged() => _emit('permission', 'mic_device_changed', '1');

  void download(
    OnboardingDownloadEvent event,
    String modelId, {
    OnboardingDownloadFailure? cause,
  }) => _emit(
    'model_download',
    event.name,
    event == OnboardingDownloadEvent.failed
        ? '${_safeModel(modelId)}:${(cause ?? OnboardingDownloadFailure.other).name}'
        : _safeModel(modelId),
  );

  /// The practice page (screen 6). On the first `ok`, also sends the time since the first
  /// welcome screen as `ttfd`. [failureCode] is a fixed error code, such as
  /// `no_speech`; anything else is sent as `other`.
  void firstDictation(OnboardingFirstDictation result, {String? failureCode}) {
    final name = switch (result) {
      OnboardingFirstDictation.ok => 'ok',
      OnboardingFirstDictation.waitedForModel => 'waited_for_model',
      OnboardingFirstDictation.failed =>
        'failed:${failureCode != null && _failureCode.hasMatch(failureCode) ? failureCode : 'other'}',
    };
    _emit('onboarding', 'first_dictation', name);
    final welcome = _welcomeAt;
    if (result == OnboardingFirstDictation.ok &&
        !_ttfdSent &&
        welcome != null) {
      _ttfdSent = true;
      _emit('onboarding', 'ttfd', ttfdBucket(_clock().difference(welcome)));
    }
  }

  String _safeModel(String id) => _modelId.hasMatch(id) ? id : 'other';
}

final onboardingTelemetryProvider = Provider<OnboardingTelemetry>((ref) {
  final buffer = ref.read(onboardingTelemetryBufferProvider);
  return OnboardingTelemetry(track: buffer.track, decide: buffer.decide);
});
