import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/clipboard_app_exclusion.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_monitor_service.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isClipboardSourceExcluded', () {
    test('matches case-insensitively on the whole identifier', () {
      expect(
        isClipboardSourceExcluded('COM.1Password.1password', [
          'com.1password.1password',
        ]),
        isTrue,
      );
      expect(
        isClipboardSourceExcluded('com.1password', ['com.1password.1password']),
        isFalse,
      );
    });

    test('unknown source is never excluded', () {
      expect(isClipboardSourceExcluded(null, ['a.exe']), isFalse);
      expect(isClipboardSourceExcluded('  ', ['a.exe']), isFalse);
    });
  });

  group('stored list', () {
    test('never edited means the platform defaults', () {
      expect(
        parseClipboardExcludedApps(null, TargetPlatform.windows),
        contains('1password.exe'),
      );
      expect(
        parseClipboardExcludedApps(null, TargetPlatform.macOS),
        contains('com.bitwarden.desktop'),
      );
      expect(parseClipboardExcludedApps(null, TargetPlatform.linux), isEmpty);
    });

    test('an edited (even empty) list replaces the defaults', () {
      expect(parseClipboardExcludedApps('[]', TargetPlatform.windows), isEmpty);
      final apps = normalizeClipboardExcludedApps([
        ' Bank.exe ',
        'bank.EXE',
        '',
      ]);
      expect(apps, ['Bank.exe']);
      expect(
        parseClipboardExcludedApps(
          encodeClipboardExcludedApps(apps),
          TargetPlatform.windows,
        ),
        ['Bank.exe'],
      );
    });

    test('unreadable storage falls back to the defaults', () {
      expect(
        parseClipboardExcludedApps('{oops', TargetPlatform.windows),
        defaultClipboardExcludedApps(TargetPlatform.windows),
      );
    });
  });

  test('only macOS and Windows can name the source app', () {
    expect(clipboardSourceAppDetectable(TargetPlatform.macOS), isTrue);
    expect(clipboardSourceAppDetectable(TargetPlatform.windows), isTrue);
    expect(clipboardSourceAppDetectable(TargetPlatform.linux), isFalse);
  });

  group('monitor service', () {
    const channelName = 'com.whispaste.clipboard_history';
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late ProviderContainer container;

    Future<void> copy(String text, {String? sourceApp}) =>
        messenger.handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(
            MethodCall('clipEntryDetected', {
              'kind': 'text',
              'text': text,
              'capturedAtMs': 1700000000000,
              'sourceApp': ?sourceApp,
            }),
          ),
          (_) {},
        );

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      container = ProviderContainer();
      container.listen(clipboardHistoryMonitorServiceProvider, (_, _) {});
    });

    tearDown(() {
      container.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    test('a copy from a default-listed app is not recorded', () async {
      await copy('hunter2', sourceApp: '1password.exe');
      expect(container.read(clipboardHistoryProvider), isEmpty);
    });

    test('copies from other or unknown apps are recorded', () async {
      await copy('from notepad', sourceApp: 'notepad.exe');
      await copy('no source reported');
      expect(container.read(clipboardHistoryProvider), hasLength(2));
    });
  });
}
