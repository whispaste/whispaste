import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/tray_language_menu.dart';
import 'package:whispaste/services/tray_submenu_builder.dart';

void main() {
  group('langMenuKey / langCodeFromMenuKey', () {
    test('round-trips language codes', () {
      expect(langCodeFromMenuKey(langMenuKey('de')), 'de');
      expect(langCodeFromMenuKey(langMenuKey('auto')), 'auto');
    });

    test('returns null for keys outside the language namespace', () {
      expect(langCodeFromMenuKey('mic:de'), isNull);
      expect(langCodeFromMenuKey(langMoreMenuKey), isNull);
    });
  });

  group('buildTrayRadioItems', () {
    test('checks exactly the selected option and adds no separator alone', () {
      final items = buildRadioCommands(
        keyPrefix: 'x:',
        options: const [
          TrayRadioOption(value: 'a', labelKey: 'A'),
          TrayRadioOption(value: 'b', labelKey: 'B'),
        ],
        selected: 'b',
      );
      expect(items, hasLength(2));
      expect(items[0].id, 'x:a');
      expect(items[0].checked, isFalse);
      expect(items[1].checked, isTrue);
    });

    test('puts trailing entries after one separator', () {
      final items = buildRadioCommands(
        keyPrefix: 'x:',
        options: const [TrayRadioOption(value: 'a', labelKey: 'A')],
        selected: null,
        trailing: [const AppCommand(id: 'more', labelKey: 'More')],
      );
      expect(items, hasLength(3));
      expect(items[1].isSeparator, isTrue);
      expect(items[2].id, 'more');
    });

    test('adds no separator when there are no options', () {
      final items = buildRadioCommands(
        keyPrefix: 'x:',
        options: const [],
        selected: null,
        trailing: [const AppCommand(id: 'more', labelKey: 'More')],
      );
      expect(items, hasLength(1));
    });
  });

  group('buildLanguageMenuItems', () {
    test('lists favorites in stored order with the active one checked', () {
      final items = buildLanguageCommands(
        activeCode: 'ru',
        favoriteCodes: const ['de', 'ru', 'en'],
        autoLabelKey: 'Auto-detect',
        moreLabelKey: 'More…',
      );
      final langItems = items
          .where((i) => i.id.startsWith(langMenuKeyPrefix))
          .toList();
      expect(langItems.map((i) => langCodeFromMenuKey(i.id)), [
        'de',
        'ru',
        'en',
      ]);
      expect(langItems.where((i) => i.checked ?? false).map((i) => i.id), [
        langMenuKey('ru'),
      ]);
    });

    test('prepends the active language when it is not a favorite', () {
      final items = buildLanguageCommands(
        activeCode: 'fr',
        favoriteCodes: const ['de'],
        autoLabelKey: 'Auto-detect',
        moreLabelKey: 'More…',
      );
      final codes = items
          .where((i) => i.id.startsWith(langMenuKeyPrefix))
          .map((i) => langCodeFromMenuKey(i.id))
          .toList();
      expect(codes, ['fr', 'de']);
      expect(items.first.checked, isTrue);
    });

    test('names auto with the given label and ends with the More entry', () {
      final items = buildLanguageCommands(
        activeCode: 'auto',
        favoriteCodes: const [],
        autoLabelKey: 'Auto-detect',
        moreLabelKey: 'More…',
      );
      expect(items.first.labelKey, 'Auto-detect');
      expect(items.first.checked, isTrue);
      expect(items.last.id, langMoreMenuKey);
      expect(items.last.labelKey, 'More…');
      expect(items[items.length - 2].isSeparator, isTrue);
    });
  });
}
