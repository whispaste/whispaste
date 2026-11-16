import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/initial_locale.dart';

void main() {
  group('systemPreferredLanguagesProvider (native channel contract)', () {
    const channel = MethodChannel('whispaste/system_languages');
    final messenger =
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<List<String>> readPreferences() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(systemPreferredLanguagesProvider.future);
    }

    test('asks preferredLanguages and keeps the platform order', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return ['de-DE', 'en-US'];
      });
      expect(await readPreferences(), ['de-DE', 'en-US']);
      expect(methods, ['preferredLanguages']);
    });

    test(
      'a failing channel yields no languages, so the rule falls back',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'unavailable');
        });
        expect(await readPreferences(), isEmpty);
      },
    );

    testWidgets('a channel that never answers yields no languages after the '
        'timeout', (tester) async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      List<String>? result;
      unawaited(readPreferences().then((value) => result = value));
      await tester.pump(const Duration(seconds: 3));
      expect(result, isEmpty);
    });
  });

  group('initialLocaleCode (UIA-VIS-06)', () {
    test('a supported system language is taken over', () {
      expect(initialLocaleCode(['de-DE']), 'de');
    });

    test('an unsupported system language falls back to English', () {
      expect(initialLocaleCode(['fr-FR']), 'en');
    });

    test('no system languages fall back to English', () {
      expect(initialLocaleCode(const []), 'en');
    });

    test('the first supported entry of the preference list wins', () {
      expect(initialLocaleCode(['fr', 'ru']), 'ru');
    });
  });

  group('namedLanguageTags', () {
    test('drops the C, POSIX and undetermined locales and empty entries', () {
      expect(
        namedLanguageTags(['C', 'C.UTF-8', 'POSIX', 'und', '', '  ']),
        isEmpty,
      );
    });

    test('strips encoding and modifier from a named locale', () {
      expect(namedLanguageTags(['de_DE.UTF-8', 'sr@latin']), ['de_DE', 'sr']);
    });
  });

  group('firstStartLanguages', () {
    test('a German Flutter locale gives German app and dictation', () {
      final first = firstStartLanguages(
        flutterLocales: ['de-DE'],
        systemPreferences: const [],
      );
      expect(first.appLocale, 'de');
      expect(first.dictationLanguage, 'de');
      expect(first.source, FirstStartSource.flutterLocales);
    });

    test('an empty Flutter list falls back to the platform preferences', () {
      final first = firstStartLanguages(
        flutterLocales: const [],
        systemPreferences: ['de-DE', 'en-US'],
      );
      expect(first.appLocale, 'de');
      expect(first.dictationLanguage, 'de');
      expect(first.source, FirstStartSource.systemPreferences);
    });

    test(
      'a C locale from the process falls back to the platform preferences',
      () {
        final first = firstStartLanguages(
          flutterLocales: ['C'],
          systemPreferences: ['de-DE'],
        );
        expect(first.appLocale, 'de');
        expect(first.dictationLanguage, 'de');
        expect(first.source, FirstStartSource.systemPreferences);
      },
    );

    test(
      'a POSIX locale with no platform preferences is the English fallback',
      () {
        final first = firstStartLanguages(
          flutterLocales: ['POSIX'],
          systemPreferences: const [],
        );
        expect(first.appLocale, 'en');
        expect(first.dictationLanguage, 'en');
        expect(first.source, FirstStartSource.fallback);
      },
    );

    test(
      'an empty list everywhere gives English, never automatic detection',
      () {
        final first = firstStartLanguages(
          flutterLocales: const [],
          systemPreferences: const [],
        );
        expect(first.appLocale, 'en');
        expect(first.dictationLanguage, 'en');
        expect(first.dictationLanguage, isNot('auto'));
        expect(first.source, FirstStartSource.fallback);
      },
    );

    test('an undetermined locale names no language', () {
      final first = firstStartLanguages(
        flutterLocales: ['und'],
        systemPreferences: const [],
      );
      expect(first.source, FirstStartSource.fallback);
    });

    test(
      'several languages: the first Whisper writes is the dictation language',
      () {
        final first = firstStartLanguages(
          flutterLocales: ['xx-XX', 'pl-PL', 'de-DE'],
          systemPreferences: const [],
        );
        expect(first.appLocale, 'de');
        expect(first.dictationLanguage, 'pl');
      },
    );

    test('a named but unsupported system language keeps the English app and '
        'automatic dictation', () {
      final first = firstStartLanguages(
        flutterLocales: ['xx-XX'],
        systemPreferences: const [],
      );
      expect(first.appLocale, 'en');
      expect(first.dictationLanguage, 'auto');
      expect(first.source, FirstStartSource.flutterLocales);
    });

    test('unsupported platform preferences also leave automatic dictation', () {
      final first = firstStartLanguages(
        flutterLocales: const ['C'],
        systemPreferences: const ['xx-XX'],
      );
      expect(first.appLocale, 'en');
      expect(first.dictationLanguage, 'auto');
      expect(first.source, FirstStartSource.systemPreferences);
    });
  });
}
