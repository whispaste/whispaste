import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

void main() {
  Future<L10n> pumpLocale(WidgetTester tester, Locale locale) async {
    late L10n l10n;

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    return l10n;
  }

  group('settings_labels', () {
    testWidgets('localizes modifier and special key labels in German', (
      tester,
    ) async {
      final l10n = await pumpLocale(tester, const Locale('de'));

      expect(
        formatHotkeyShortcut('ctrl+shift', 'enter', l10n: l10n),
        'Strg+Umschalt+Eingabe',
      );
      expect(hotkeyKeyLabel('delete', l10n: l10n), 'Entf');
      expect(hotkeyKeyLabel('space', l10n: l10n), 'Leertaste');
    });

    testWidgets('keeps letter shortcuts uppercase', (tester) async {
      final l10n = await pumpLocale(tester, const Locale('en'));

      expect(formatHotkeyShortcut('ctrl', 'd', l10n: l10n), 'Ctrl+D');
    });

    testWidgets('altgr token renders as the AltGr label (#39)', (tester) async {
      final l10n = await pumpLocale(tester, const Locale('de'));

      expect(hotkeyModifierLabels('altgr', l10n: l10n), ['AltGr']);
      expect(hotkeyModifierLabels('shift+altgr', l10n: l10n), [
        'Umschalt',
        'AltGr',
      ]);
    });
  });

  group('pushToTalkUnavailableMessage', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(locale);

      test('Linux points to the --toggle CLI trigger '
          '(${locale.languageCode})', () {
        final message = pushToTalkUnavailableMessage(
          l10n,
          operatingSystem: 'linux',
        );
        expect(message, l10n.pushToTalkUnavailableLinuxTooltip);
        expect(message, contains('whispaste --toggle'));
      });

      test('other platforms keep the generic hint '
          '(${locale.languageCode})', () {
        expect(
          pushToTalkUnavailableMessage(l10n, operatingSystem: 'windows'),
          l10n.pushToTalkUnavailableTooltip,
        );
      });
    }
  });
}
