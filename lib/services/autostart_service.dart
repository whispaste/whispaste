import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

/// Abstraction over the `launch_at_startup` plugin's static API so
/// [AutostartService] can be tested against a deterministic fake instead of
/// real OS-level registration (Windows registry, macOS login items, Linux
/// autostart entries).
abstract class AutostartBackend {
  Future<bool> isEnabled();
  Future<void> enable();
  Future<void> disable();
}

/// Production backend — delegates to the real `launch_at_startup` plugin.
class _LaunchAtStartupBackend implements AutostartBackend {
  const _LaunchAtStartupBackend();

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<void> enable() => launchAtStartup.enable();

  @override
  Future<void> disable() => launchAtStartup.disable();
}

/// Manages the "launch at startup" registration using the system registry
/// (Windows), login items (macOS), or autostart entries (Linux).
class AutostartService extends Notifier<bool> {
  static bool _setupDone = false;
  static final _log = AppLogger('AutostartService');

  /// Injectable backend seam. Production uses the real plugin; tests
  /// override this getter in a subclass (mirroring the subclass-override
  /// fake convention used elsewhere, e.g. `_FakeAutostartService` in
  /// `test/widgets/service_bootstrap_test.dart`) to simulate success/failure
  /// deterministically.
  @visibleForTesting
  AutostartBackend get backend => const _LaunchAtStartupBackend();

  @override
  bool build() {
    _ensureSetup();
    // Re-sync whenever `launchAtStartup` changes after the initial `build()`
    // — without this, toggling the setting (e.g. from the onboarding Ready
    // step or Settings → Interface) only persists the flag; the OS-level
    // registration would not happen until the next time this provider's
    // `build()` re-runs (i.e. the next app start), leaving the toggle
    // silently inert for the whole current session.
    ref.listen(settingsProvider, (previous, next) {
      final prevValue = previous?.value?.interface_.launchAtStartup;
      final nextValue = next.value?.interface_.launchAtStartup;
      if (nextValue != null && nextValue != prevValue) {
        unawaited(_syncWithSettings());
      }
    });
    _syncWithSettings();
    return false;
  }

  /// One-time setup of the launch_at_startup plugin.
  void _ensureSetup() {
    if (_setupDone) return;
    _setupDone = true;

    launchAtStartup.setup(
      appName: 'WhisPaste',
      appPath: Platform.resolvedExecutable,
      // MSIX Store packages use a different startup mechanism.
      packageName: 'com.whispaste.app',
      args: ['--autostart'],
    );
  }

  /// Sync the autostart state with the persisted setting.
  ///
  /// On success, [state] is set to the real, now-confirmed registration
  /// outcome and [autostartSyncFailureProvider] is cleared. On failure the
  /// registration error is exposed via [autostartSyncFailureProvider]
  /// instead of only being logged, and [state] is left untouched — it must
  /// never optimistically report "enabled" for a registration that did not
  /// actually happen.
  Future<void> _syncWithSettings() async {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;

    try {
      final isEnabled = await backend.isEnabled();
      if (settings.interface_.launchAtStartup && !isEnabled) {
        await backend.enable();
        _log.info('Autostart enabled');
      } else if (!settings.interface_.launchAtStartup && isEnabled) {
        await backend.disable();
        _log.info('Autostart disabled');
      }
      state = settings.interface_.launchAtStartup;
      ref.read(autostartSyncFailureProvider.notifier).report(null);
    } catch (e) {
      _log.warning('Autostart sync failed: $e');
      ref.read(autostartSyncFailureProvider.notifier).report(e);
    }
  }
}

final autostartServiceProvider = NotifierProvider<AutostartService, bool>(
  AutostartService.new,
);

/// Holds the last error from an `AutostartService` OS-registration attempt,
/// or `null` when the most recent sync succeeded (or none has run yet).
/// Exposed separately from the `bool` autostart state so a failure is
/// observable from outside without changing the shape/consumers of the
/// existing enabled/disabled state.
class AutostartSyncFailureNotifier extends Notifier<Object?> {
  @override
  Object? build() => null;

  /// Records the outcome of the latest sync attempt: `null` on success, the
  /// thrown error on failure.
  void report(Object? error) => state = error;
}

final autostartSyncFailureProvider =
    NotifierProvider<AutostartSyncFailureNotifier, Object?>(
      AutostartSyncFailureNotifier.new,
    );
