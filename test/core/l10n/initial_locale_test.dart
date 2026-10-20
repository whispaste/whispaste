import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/initial_locale.dart';

void main() {
  group('initialLocaleCode (UIA-VIS-06)', () {
    test('a supported system language is taken over', () {
      expect(initialLocaleCode([const Locale('de', 'DE')]), 'de');
    });

    test('an unsupported system language falls back to English', () {
      expect(initialLocaleCode([const Locale('fr', 'FR')]), 'en');
    });

    test('no system locales fall back to English', () {
      expect(initialLocaleCode(const []), 'en');
    });

    test('the first supported entry of the preference list wins', () {
      expect(initialLocaleCode([const Locale('fr'), const Locale('ru')]), 'ru');
    });
  });
}
