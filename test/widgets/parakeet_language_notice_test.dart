import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/parakeet_language_notice.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('names the unsupported language and offers Whisper', (
    tester,
  ) async {
    var switched = 0;
    await tester.pumpWidget(
      host(
        WpParakeetLanguageBanner(
          languageCode: 'ar',
          onSwitch: () => switched++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-stt-parakeet-language-notice')),
      findsOneWidget,
    );
    expect(
      find.text('Parakeet cannot transcribe Arabic. Switch to Whisper?'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-stt-parakeet-switch-whisper')),
    );
    await tester.pump();
    expect(switched, 1);
  });
}
