/// Unit tests for [AutostartService] — verifies that a failed OS-level
/// autostart registration does not optimistically flip the exposed state to
/// "enabled", and that the failure is surfaced via
/// [autostartSyncFailureProvider] instead of being swallowed into logs only.
///
/// Regression net for
/// `.scratch/growth-reliability-conversion/issues/02-autostart-state-spiegelt-reale-os-registrierung.md`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/autostart_service.dart';

/// Fake settings notifier returning a fixed [AppSettings] synchronously so
/// [AutostartService.build] observes it within the same microtask.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier({required this.launchAtStartup});

  final bool launchAtStartup;

  @override
  Future<AppSettings> build() {
    return Future.value(
      AppSettings(
        interface_: InterfaceSettings(launchAtStartup: launchAtStartup),
      ),
    );
  }
}

/// Backend seam that reports a fixed `isEnabled` result and either succeeds
/// or throws on `enable`/`disable`, deterministically simulating real OS
/// registration outcomes without touching any platform API.
class _FakeAutostartBackend implements AutostartBackend {
  _FakeAutostartBackend({
    required this.initiallyEnabled,
    required this.shouldFail,
  });

  final bool initiallyEnabled;
  final bool shouldFail;

  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<bool> isEnabled() async => initiallyEnabled;

  @override
  Future<void> enable() async {
    enableCalls++;
    if (shouldFail) throw StateError('fake registration failure');
  }

  @override
  Future<void> disable() async {
    disableCalls++;
    if (shouldFail) throw StateError('fake registration failure');
  }
}

/// Test subclass exposing the injected backend seam, mirroring the
/// subclass-override fake convention used elsewhere in this codebase (see
/// `_FakeAutostartService` in `test/widgets/service_bootstrap_test.dart`).
class _SeamedAutostartService extends AutostartService {
  _SeamedAutostartService(this._backend);

  final AutostartBackend _backend;

  @override
  AutostartBackend get backend => _backend;
}

void main() {
  test(
    'backend enable() failure: exposed state stays disabled, not optimistic',
    () async {
      final fakeBackend = _FakeAutostartBackend(
        initiallyEnabled: false,
        shouldFail: true,
      );
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(launchAtStartup: true),
          ),
          autostartServiceProvider.overrideWith(
            () => _SeamedAutostartService(fakeBackend),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Warm up settingsProvider first so it is already AsyncData (not
      // AsyncLoading) by the time AutostartService.build() synchronously
      // reads it via `ref.read(settingsProvider).value` — mirroring
      // production bootstrap order (settings load before services sync).
      await container.read(settingsProvider.future);
      container.read(autostartServiceProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(fakeBackend.enableCalls, 1);
      expect(
        container.read(autostartServiceProvider),
        isFalse,
        reason: 'must not optimistically report enabled after a failure',
      );
      expect(
        container.read(autostartSyncFailureProvider),
        isNotNull,
        reason: 'failure must be observable, not just logged',
      );
    },
  );

  test('backend enable() success: exposed state flips to enabled', () async {
    final fakeBackend = _FakeAutostartBackend(
      initiallyEnabled: false,
      shouldFail: false,
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(launchAtStartup: true),
        ),
        autostartServiceProvider.overrideWith(
          () => _SeamedAutostartService(fakeBackend),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    container.read(autostartServiceProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(fakeBackend.enableCalls, 1);
    expect(container.read(autostartServiceProvider), isTrue);
    expect(container.read(autostartSyncFailureProvider), isNull);
  });
}
