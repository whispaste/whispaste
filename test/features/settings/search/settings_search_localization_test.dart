/// Section-picker labels and search titles must read in every app UI language,
/// not only in German and English. Expected strings are the section headings
/// the page renders for each locale (the same ARB keys), so the picker never
/// drifts from them.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../../fixtures/test_helpers.dart';

/// sectionKey -> {languageCode: rendered section heading}.
const _headings = <String, Map<String, String>>{
  'interface': {'ru': 'Интерфейс', 'he': 'ממשק'},
  'stt': {'ru': 'Распознавание речи', 'he': 'זיהוי דיבור'},
  'smartMode': {'ru': 'Умный режим', 'he': 'Smart Mode'},
  'audio': {'ru': 'Аудио', 'he': 'אודיו'},
  'afterTranscription': {'ru': 'После транскрипции', 'he': 'אחרי תמלול'},
  'overlay': {'ru': 'Оверлей записи', 'he': 'שכבת הקלטה צפה'},
  'floatingButton': {'ru': 'Плавающая кнопка', 'he': 'כפתור צף'},
  'hotkey': {'ru': 'Горячая клавиша', 'he': 'קיצור מקלדת'},
  'sound': {'ru': 'Звук и отклик', 'he': 'צלילים ומשוב'},
  'recordingSafety': {'ru': 'Безопасность записи', 'he': 'בטיחות הקלטה'},
  'history': {'ru': 'История', 'he': 'היסטוריה'},
  'settingsPortability': {
    'ru': 'Резервное копирование и перенос',
    'he': 'גיבוי והעברה',
  },
  'advanced': {'ru': 'Дополнительно', 'he': 'מתקדם'},
  'automationApi': {
    'ru': 'Локальный API автоматизации',
    'he': 'ממשק API מקומי לאוטומציה',
  },
  'updates': {'ru': 'Обновления', 'he': 'עדכונים'},
  'onboardingReview': {'ru': 'Введение', 'he': 'מבוא'},
  'reviewSupport': {
    'ru': 'Оценить и поддержать WhisPaste',
    'he': 'דרגו ותמוכו ב-WhisPaste',
  },
  'privacy': {'ru': 'Конфиденциальность', 'he': 'Privacy'},
};

SettingsSearchEntry _entry(String sectionKey) =>
    kSettingsSearchTable.singleWhere((e) => e.sectionKey == sectionKey);

List<String> _keysFor(String query, String locale) => matchSettingsEntries(
  kSettingsSearchTable,
  query,
  locale,
).map((e) => e.sectionKey).toList();

void main() {
  group('SettingsSearchEntry localisation (ru, he)', () {
    test('every table entry has an expected heading for ru and he', () {
      expect(
        _headings.keys.toSet(),
        kSettingsSearchTable.map((e) => e.sectionKey).toSet(),
      );
    });

    test('title() yields the rendered section heading, not English', () {
      for (final section in _headings.entries) {
        for (final locale in section.value.entries) {
          expect(
            _entry(section.key).title(locale.key),
            locale.value,
            reason: '${section.key} title in ${locale.key}',
          );
        }
      }
    });

    test(
      'subtitle() resolves per locale instead of falling back to English',
      () {
        expect(_entry('interface').subtitle('ru'), 'Внешний вид и поведение');
        expect(_entry('interface').subtitle('he'), 'מראה והתנהגות');
      },
    );

    test('an unsupported language tag falls back to English', () {
      expect(_entry('interface').title('fr'), 'Interface');
      expect(_entry('interface').title('en-US'), 'Interface');
    });
  });

  group('matchSettingsEntries matches the localised title', () {
    test('Russian title matches in ru', () {
      expect(_keysFor('Умный', 'ru'), ['smartMode']);
    });

    test('Russian subtitle matches in ru', () {
      expect(_keysFor('Внешний вид', 'ru'), contains('interface'));
    });

    test('Hebrew title matches in he', () {
      expect(_keysFor('זיהוי דיבור', 'he'), ['stt']);
    });

    test('English keywords still match in ru', () {
      expect(_keysFor('microphone', 'ru'), contains('audio'));
    });
  });

  group('SettingsSectionPicker in ru', () {
    testWidgets('the picker shows Russian section titles, not English', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('ru'),
          size: const Size(1280, 800),
        ),
      );
      await tester.pumpAndSettle();

      final picker = find.byKey(const Key('settings-section-picker'));
      expect(picker, findsOneWidget);
      expect(
        find.descendant(of: picker, matching: find.text('Интерфейс')),
        findsOneWidget,
      );

      await tester.tap(picker);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-section-picker-stt')),
        findsOneWidget,
      );
      expect(find.text('Распознавание речи'), findsWidgets);
      expect(find.text('Speech Recognition'), findsNothing);
    });
  });
}
