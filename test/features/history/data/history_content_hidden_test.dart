import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/history/data/history_lock.dart';

/// Settings that never finish loading, as at startup before the file is read.
class _LoadingSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() => Completer<AppSettings>().future;
}

/// Settings that fail to load.
class _FailingSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => throw StateError('settings unreadable');
}

/// Loaded settings with an optional PIN.
class _LoadedSettings extends SettingsNotifier {
  _LoadedSettings({this.pin = ''});
  final String pin;

  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    history: AppSettings.defaults.history.copyWith(historyPin: pin),
  );
}

/// Loaded with a PIN; while [isReloading] is true a rebuild never completes.
class _ReloadingSettings extends SettingsNotifier {
  _ReloadingSettings(this.isReloading);
  final bool Function() isReloading;

  @override
  Future<AppSettings> build() => isReloading()
      ? Completer<AppSettings>().future
      : Future.value(
          AppSettings.defaults.copyWithSections(
            history: AppSettings.defaults.history.copyWith(historyPin: '1234'),
          ),
        );
}

ProviderContainer _container(SettingsNotifier Function() settings) {
  final container = ProviderContainer(
    overrides: [settingsProvider.overrideWith(settings)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('historyContentHiddenProvider', () {
    test('is not hidden while the settings are still loading (no PIN is '
        'known to be active, so the lock must not claim one)', () {
      final container = _container(_LoadingSettings.new);
      expect(
        container.read(settingsProvider).isLoading,
        isTrue,
        reason: 'precondition: settings not yet loaded',
      );
      expect(container.read(historyContentHiddenProvider), isFalse);
    });

    test('stays hidden while a reload runs after a PIN was loaded', () async {
      var reloading = false;
      final container = _container(() => _ReloadingSettings(() => reloading));
      await container.read(settingsProvider.future);
      expect(container.read(historyContentHiddenProvider), isTrue);

      reloading = true;
      container.invalidate(settingsProvider);
      expect(
        container.read(settingsProvider).isLoading,
        isTrue,
        reason: 'precondition: reload in flight, previous value kept',
      );
      expect(container.read(historyContentHiddenProvider), isTrue);
    });

    test('is hidden when the settings fail to load', () async {
      final container = _container(_FailingSettings.new);
      await container
          .read(settingsProvider.future)
          .then<void>((_) {})
          .catchError((Object _) {});
      expect(container.read(settingsProvider).hasError, isTrue);
      expect(container.read(historyContentHiddenProvider), isTrue);
    });

    test('is visible once loaded without a PIN', () async {
      final container = _container(_LoadedSettings.new);
      await container.read(settingsProvider.future);
      expect(container.read(historyContentHiddenProvider), isFalse);
    });

    test('is hidden once loaded with a PIN and not unlocked', () async {
      final container = _container(() => _LoadedSettings(pin: '1234'));
      await container.read(settingsProvider.future);
      expect(container.read(historyContentHiddenProvider), isTrue);
    });
  });
}
