/// Single source of truth for the microphone permission surface.
///
/// Mirrors `paste_capability_notifier.dart`: wraps the platform permission
/// check behind a Riverpod [Notifier] so onboarding steps 1/4/5 and the
/// startup gate share one state and one deep-link instead of each holding
/// ad-hoc booleans that cannot tell "never asked" apart from "denied".
///
/// State shape ([MicPermissionState]):
///   - [MicPermissionStatus.unknown]: no request has resolved in this
///     process yet. A side-effect-free [MicPermissionNotifier.check] can
///     only ever promote out of this state, never regress into it.
///   - [MicPermissionStatus.denied] is reachable **only** via
///     [MicPermissionNotifier.request] — the underlying platform API
///     (`record`'s `hasPermission`) returns a silent `false` for both "never
///     asked" and "denied", so a passive read alone can never tell them
///     apart and must not claim `denied`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/app_logger.dart';

/// Deep-link target for macOS' microphone privacy pane.
const String _micSettingsUriMacOS =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone';

/// Deep-link target for Windows' microphone privacy page.
const String _micSettingsUriWindows = 'ms-settings:privacy-microphone';

enum MicPermissionStatus {
  /// No request has resolved in this process yet.
  unknown,

  /// [MicPermissionNotifier.request] is in flight.
  requesting,

  /// Permission confirmed granted, either by a passive [MicPermissionNotifier
  /// .check] or by [MicPermissionNotifier.request].
  granted,

  /// [MicPermissionNotifier.request] resolved without a grant. Only reachable
  /// through an in-process request — see class doc.
  denied,
}

/// Immutable snapshot of the microphone permission surface.
class MicPermissionState {
  const MicPermissionState({this.status = MicPermissionStatus.unknown});

  final MicPermissionStatus status;

  MicPermissionState copyWith({MicPermissionStatus? status}) =>
      MicPermissionState(status: status ?? this.status);
}

/// Minimal seam over `package:record`'s permission surface so tests can
/// drive the notifier without a real platform channel.
abstract class MicPermissionChecker {
  /// `request: false` must be a pure status read (never prompts).
  /// `request: true` may fire the one-time OS dialog on first contact;
  /// after a denial the OS returns `false` silently (verified against
  /// `record_macos`/`record_windows` — same platform truth documented in
  /// `startup_permission_gate.dart`).
  Future<bool> check({required bool request});
}

/// Holds a single [AudioRecorder] for the provider's lifetime instead of one
/// per [check] call — `hasPermission` never needs a fresh instance, and a
/// disposable-per-call recorder would leak a native session on every poll
/// tick.
class _RealMicPermissionChecker implements MicPermissionChecker {
  _RealMicPermissionChecker() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> check({required bool request}) =>
      _recorder.hasPermission(request: request);

  Future<void> dispose() => _recorder.dispose();
}

final micPermissionCheckerProvider = Provider<MicPermissionChecker>((ref) {
  final checker = _RealMicPermissionChecker();
  ref.onDispose(checker.dispose);
  return checker;
});

/// Riverpod notifier wrapping the microphone permission surface.
class MicPermissionNotifier extends Notifier<MicPermissionState> {
  static final _log = AppLogger('MicPermission');

  Timer? _pollTimer;
  Timer? _pollTimeout;
  bool _checkInFlight = false;

  /// `true` once [request] has fired the OS-prompted check at least once
  /// this process. The OS shows its permission dialog at most once per
  /// process — a second [request] call gets no dialog at all, so the
  /// Settings deep-link becomes the only way there. Deliberately in-memory
  /// only: a fresh process gets a fresh dialog budget.
  bool _osPromptFiredThisProcess = false;

  @override
  MicPermissionState build() {
    ref.onDispose(_cancelTimers);
    return const MicPermissionState();
  }

  /// Whether [startPolling] currently has an active timer.
  bool get isPolling => _pollTimer != null;

  /// Side-effect-free read. Never triggers the OS dialog. Promotes state to
  /// [MicPermissionStatus.granted] when the platform reports access;
  /// otherwise leaves the current status untouched — a bare `false` here
  /// cannot distinguish "never asked" from "denied" (see class doc), so it
  /// must never move state toward [MicPermissionStatus.denied].
  ///
  /// Calls that overlap are coalesced — a second [check] entered while the
  /// first is still in flight returns the current state's grant instead of
  /// firing a duplicate platform call.
  Future<bool> check() async {
    if (_checkInFlight) return state.status == MicPermissionStatus.granted;
    _checkInFlight = true;
    try {
      final granted = await ref
          .read(micPermissionCheckerProvider)
          .check(request: false);
      if (granted) {
        state = state.copyWith(status: MicPermissionStatus.granted);
      }
      return granted;
    } finally {
      _checkInFlight = false;
    }
  }

  /// Requests microphone access. Always asks the platform for a truthful
  /// result — after a denial `hasPermission(request: true)` resolves `false`
  /// silently with no dialog (verified platform truth, see
  /// [MicPermissionChecker.check]), so a repeat call costs nothing and can
  /// still observe a grant that happened outside the app since the last ask.
  /// Only the *dialog budget* is tracked: the real OS dialog fires on this
  /// process's first call; every later denied call instead deep-links to
  /// [openSystemSettings] (the one place a denial can still be reversed) and
  /// arms [startPolling] so a grant made there is picked up without another
  /// manual request.
  Future<bool> request() async {
    state = state.copyWith(status: MicPermissionStatus.requesting);
    final alreadyPrompted = _osPromptFiredThisProcess;
    _osPromptFiredThisProcess = true;
    final granted = await ref
        .read(micPermissionCheckerProvider)
        .check(request: true);
    state = state.copyWith(
      status: granted
          ? MicPermissionStatus.granted
          : MicPermissionStatus.denied,
    );
    if (!granted && alreadyPrompted) {
      await openSystemSettings();
      startPolling();
    }
    return granted;
  }

  /// Deep-links to the OS microphone privacy pane. macOS and Windows only —
  /// Linux has no equivalent single pane to target, so this is a deliberate
  /// no-op there rather than a launch attempt that would fail silently.
  Future<void> openSystemSettings() async {
    final uri = _settingsUri();
    if (uri == null) return;
    try {
      await launchUrl(Uri.parse(uri));
    } on Exception catch (e) {
      _log.warning('Could not open microphone privacy settings: $e');
    }
  }

  String? _settingsUri() {
    if (Platform.isMacOS) return _micSettingsUriMacOS;
    if (Platform.isWindows) return _micSettingsUriWindows;
    return null;
  }

  /// Watches for a grant applied outside the app (the user flips the
  /// Settings toggle while WhisPaste stays open) and self-stops the moment
  /// [check] reports it, or once [timeout] elapses — whichever comes first.
  /// No caller needs to remember [stopPolling] in the happy path.
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {
    _cancelTimers();
    _pollTimer = Timer.periodic(interval, (_) async {
      if (await check()) {
        _cancelTimers();
      }
    });
    _pollTimeout = Timer(timeout, _cancelTimers);
  }

  /// Cancels the active polling pair if any. Safe to call multiple times and
  /// before [startPolling] has ever run.
  void stopPolling() => _cancelTimers();

  /// Cancels both timers. Also the [ref.onDispose] hook, so no timer ever
  /// outlives the provider — no `state` write happens here, which would
  /// throw during teardown.
  void _cancelTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollTimeout?.cancel();
    _pollTimeout = null;
  }
}

final micPermissionNotifierProvider =
    NotifierProvider<MicPermissionNotifier, MicPermissionState>(
      MicPermissionNotifier.new,
    );
