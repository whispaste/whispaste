/// The engine's status while the system asset downloads: progress is polled
/// until the download finishes, and a failed start is reported. Time is faked,
/// so the polling runs without real waits.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/system_speech/system_speech_channel.dart';
import 'package:whispaste/services/system_speech/system_speech_status.dart';

const _channelName = 'whispaste/system_speech';

/// Settings with a fixed language, so the status checks that language.
class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(sttLanguage: 'de');
}

/// The same language with the system engine selected.
class _FakeSystemEngineSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWith(
    sttLanguage: 'de',
    sttEngine: OnDeviceEngine.system.value,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  ProviderContainer container() => ProviderContainer(
    overrides: [
      systemSpeechSupportedProvider.overrideWithValue(true),
      settingsProvider.overrideWith(_FakeSettings.new),
    ],
  );

  test('the download polls progress and ends installed', () {
    fakeAsync((async) {
      var progress = 0.0;
      var installed = false;
      messenger.setMockMethodCallHandler(const MethodChannel(_channelName), (
        call,
      ) async {
        switch (call.method) {
          case 'capability':
            return {
              'osSupported': true,
              'localeSupported': 'de_DE',
              'installed': installed,
            };
          case 'installAsset':
            return null;
          case 'installProgress':
            progress += 0.5;
            if (progress >= 1) installed = true;
            return {
              'state': progress >= 1 ? 'done' : 'installing',
              'fraction': progress.clamp(0.0, 1.0),
            };
        }
        return null;
      });

      final c = container();
      addTearDown(c.dispose);
      c.read(systemSpeechProvider);
      async.flushMicrotasks();

      c.read(systemSpeechProvider.notifier).install();
      async.flushMicrotasks();
      expect(c.read(systemSpeechProvider).installing, isTrue);

      async.elapse(kSystemSpeechPollInterval * 3);
      async.flushMicrotasks();

      final status = c.read(systemSpeechProvider);
      expect(status.installing, isFalse);
      expect(status.installed, isTrue);
      expect(status.failed, isFalse);
    });
  });

  test('a download that cannot start is reported as failed', () {
    fakeAsync((async) {
      messenger.setMockMethodCallHandler(const MethodChannel(_channelName), (
        call,
      ) async {
        if (call.method == 'installAsset') {
          throw PlatformException(code: 'LOCALE_UNSUPPORTED');
        }
        return {'osSupported': true, 'installed': false};
      });

      final c = container();
      addTearDown(c.dispose);
      c.read(systemSpeechProvider);
      async.flushMicrotasks();

      c.read(systemSpeechProvider.notifier).install();
      async.flushMicrotasks();

      final status = c.read(systemSpeechProvider);
      expect(status.installing, isFalse);
      expect(status.failed, isTrue);
    });
  });

  test('after a restart the prewarm reserves and the asset reads installed', () {
    fakeAsync((async) {
      // The system reports the asset as installed only to a process that holds
      // the language's reservation, which the prewarm takes.
      var reserved = false;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(const MethodChannel(_channelName), (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'capability':
            return {
              'osSupported': true,
              'localeSupported': 'de_DE',
              'installed': reserved,
            };
          case 'prewarm':
            reserved = true;
            return null;
        }
        return null;
      });

      final c = ProviderContainer(
        overrides: [
          systemSpeechSupportedProvider.overrideWithValue(true),
          settingsProvider.overrideWith(_FakeSystemEngineSettings.new),
        ],
      );
      addTearDown(c.dispose);
      c.read(systemSpeechProvider);
      async.flushMicrotasks();

      // The status is read again after the prewarm took the reservation.
      expect(calls.indexOf('prewarm'), greaterThan(0));
      expect(
        calls.lastIndexOf('capability'),
        greaterThan(calls.indexOf('prewarm')),
      );
      expect(c.read(systemSpeechProvider).installed, isTrue);
    });
  });

  test('a language the system cannot take is flagged, not offered', () {
    fakeAsync((async) {
      messenger.setMockMethodCallHandler(const MethodChannel(_channelName), (
        call,
      ) async {
        if (call.method == 'capability') {
          return {'osSupported': true, 'installed': false};
        }
        return null;
      });

      final c = container();
      addTearDown(c.dispose);
      c.read(systemSpeechProvider);
      async.flushMicrotasks();

      final status = c.read(systemSpeechProvider);
      expect(status.checked, isTrue);
      expect(status.localeUnsupported, isTrue);
    });
  });

  test('a fallback cause is announced once per session', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(systemSpeechFallbackProvider.notifier);

    notifier.show(SystemSpeechFallback.languageUnsupported);
    expect(
      c.read(systemSpeechFallbackProvider),
      SystemSpeechFallback.languageUnsupported,
    );
    notifier.clear();

    notifier.show(SystemSpeechFallback.languageUnsupported);
    expect(c.read(systemSpeechFallbackProvider), isNull);
  });
}
