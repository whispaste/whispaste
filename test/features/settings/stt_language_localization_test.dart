/// Verifies the STT recognition-language names are localised to the active UI
/// language (regression for: names always shown in English regardless of UI
/// locale). The dropdown resolves each Whisper code through
/// `LocaleNames.of(context).nameOf(code)`; this test exercises that exact
/// mechanism plus the German/English outcomes and the catalog fallback.
@Tags(<String>['l10n'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/whisper_languages.dart';

Future<LocaleNames> _localeNamesFor(WidgetTester tester, Locale locale) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        LocaleNamesLocalizationsDelegate(),
      ],
      supportedLocales: const [Locale('de'), Locale('en')],
      home: Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  // The delegate loads its CLDR data asynchronously — settle before reading.
  await tester.pumpAndSettle();
  return LocaleNames.of(ctx)!;
}

void main() {
  testWidgets('recognition-language names are German under the German UI', (
    tester,
  ) async {
    final names = await _localeNamesFor(tester, const Locale('de'));

    expect(names.nameOf('de'), 'Deutsch');
    expect(names.nameOf('ru'), 'Russisch');
    expect(names.nameOf('fr'), 'Französisch');
    expect(names.nameOf('en'), 'Englisch');
    // The old bug surfaced the English catalog name even in German.
    expect(names.nameOf('de'), isNot(whisperLanguages['de']));
  });

  testWidgets('recognition-language names are English under the English UI', (
    tester,
  ) async {
    final names = await _localeNamesFor(tester, const Locale('en'));

    expect(names.nameOf('de'), 'German');
    expect(names.nameOf('ru'), 'Russian');
  });

  testWidgets('every Whisper code resolves to a non-empty label', (
    tester,
  ) async {
    final names = await _localeNamesFor(tester, const Locale('de'));

    // Mirrors the dropdown's fallback: localised name, else the catalog name.
    for (final code in whisperLanguages.keys) {
      final label = names.nameOf(code) ?? whisperLanguages[code]!;
      expect(label, isNotEmpty, reason: 'no label for "$code"');
    }
  });
}
