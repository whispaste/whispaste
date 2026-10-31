/// Keycap rows of a hotkey are spelled per platform: macOS glyph caps side by
/// side, Windows and Linux named caps joined by "+".
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pumpHotkey(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: HotkeyDisplay(hotkeyKey: 'e', hotkeyModifiers: 'ctrl+shift'),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('macOS: glyph caps side by side, no "+"', (tester) async {
    await _onPlatform(TargetPlatform.macOS, () async {
      await _pumpHotkey(tester);

      expect(find.text('⌃'), findsOneWidget);
      expect(find.text('⇧'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('+'), findsNothing);
      expect(find.text('Strg'), findsNothing);
    });
  });

  testWidgets('Windows: named caps joined by "+"', (tester) async {
    await _onPlatform(TargetPlatform.windows, () async {
      await _pumpHotkey(tester);

      expect(find.text('Strg'), findsOneWidget);
      expect(find.text('Umschalt'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('+'), findsNWidgets(2));
      expect(find.text('⌃'), findsNothing);
    });
  });

  testWidgets('Linux: named caps joined by "+"', (tester) async {
    await _onPlatform(TargetPlatform.linux, () async {
      await _pumpHotkey(tester);

      expect(find.text('Strg'), findsOneWidget);
      expect(find.text('Umschalt'), findsOneWidget);
      expect(find.text('+'), findsNWidgets(2));
      expect(find.text('⌘'), findsNothing);
    });
  });
}
