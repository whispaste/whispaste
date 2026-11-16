/// Shared provider overrides for pumping the onboarding overlay in widget
/// tests. Used by `test/features/onboarding/onboarding_overlay_test.dart` and
/// by the UX screenshot sweep (`test/ux_audit/ux_fixtures.dart`), so both run
/// the overlay against the same inert platform fakes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  /// Read-back for tests that need to assert what the overlay persisted
  /// (e.g. that the legacy-flow migration did or didn't stamp a new value).
  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Inert platform truth for tests that run the *real* notifier — the mic
/// chip on the last page checks on mount, and leaving page 1 may request;
/// neither call may ever reach the real audio plugin in a widget test.
class FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

/// Pins the hotkey registration status for the conflict-branch fit test.
class FakeHotkeyStatusController extends HotkeyRegistrationStatusController {
  FakeHotkeyStatusController(this._initial);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

class _FakeRegistrar implements HotKeyRegistrar {
  const _FakeRegistrar({this.supportsKeyUp = true});

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

/// [HotkeyService] whose `build()` never runs the real startup registration —
/// that would asynchronously overwrite the status the conflict test seeds
/// (same fake as `trigger_step_test.dart`).
class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

HotkeyService _noopHotkeyService({bool supportsKeyUp = true}) {
  final svc = _NoopHotkeyService();
  svc.injectRegistrar(_FakeRegistrar(supportsKeyUp: supportsKeyUp));
  svc.injectMonitor(NoopKeyboardUpMonitor());
  return svc;
}

/// Both download providers pinned to a failed download, so whichever engine
/// the locale's recommendation selects renders the error branch.
class StaticWhisperDownload extends ModelDownloadNotifier {
  StaticWhisperDownload(this._initial);

  final ModelDownloadState _initial;

  @override
  ModelDownloadState build() => _initial;
}

class StaticParakeetDownload extends ParakeetDownloadNotifier {
  StaticParakeetDownload(this._initial);

  final ParakeetDownloadState _initial;

  @override
  ParakeetDownloadState build() => _initial;
}

/// The overrides every onboarding pump needs: fixed settings, inert mic
/// checker, model downloads pinned to idle (or to a failure), and — when
/// [hotkeyStatus] is given — a pinned hotkey status with a no-op service.
///
/// Pass [hotkeyStatus] whenever the page under test shows the hotkey state;
/// otherwise the real hotkey service would try to register with the OS.
List<Object> onboardingOverrides({
  FakeSettingsNotifier? settings,
  OnboardingRevisionRegistry? revisionRegistry,
  HotkeyRegistrationStatus? hotkeyStatus,
  bool supportsKeyUp = true,
  bool downloadFailed = false,
}) {
  const downloadError = 'Verbindung unterbrochen (HTTP 503)';
  return [
    settingsProvider.overrideWith(() => settings ?? FakeSettingsNotifier()),
    if (revisionRegistry != null)
      onboardingRevisionRegistryProvider.overrideWithValue(revisionRegistry),
    micPermissionCheckerProvider.overrideWithValue(FakeMicPermissionChecker()),
    if (hotkeyStatus != null) ...[
      hotkeyRegistrationStatusProvider.overrideWith(
        () => FakeHotkeyStatusController(hotkeyStatus),
      ),
      hotkeyServiceProvider.overrideWith(
        () => _noopHotkeyService(supportsKeyUp: supportsKeyUp),
      ),
    ],
    // Always statically overridden — never the real notifier. Its
    // initial disk scan hits real `Directory`/`File` calls, which
    // `ModelStep._detectHardware()` now awaits before its first
    // `setState` (see `awaitInitialScan()`); those real calls never
    // resolve under `testWidgets`, hanging every test that reaches
    // ModelStep until `pumpAndSettle` times out.
    modelDownloadProvider.overrideWith(
      () => StaticWhisperDownload(
        downloadFailed
            ? const ModelDownloadState(
                phase: DownloadPhase.error,
                errorMessage: downloadError,
              )
            : const ModelDownloadState(),
      ),
    ),
    parakeetDownloadProvider.overrideWith(
      () => StaticParakeetDownload(
        downloadFailed
            ? const ParakeetDownloadState(
                phase: ParakeetDownloadPhase.error,
                errorMessage: downloadError,
              )
            : const ParakeetDownloadState(),
      ),
    ),
  ];
}
