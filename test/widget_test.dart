import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';

void main() {
  group('App smoke tests', () {
    testWidgets('wpDarkTheme builds a valid ThemeData', (tester) async {
      final theme = wpDarkTheme();

      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const Scaffold()),
      );

      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    });

    // Removed 2026-08-11 (dark-only build): `wpLightTheme builds a valid
    // ThemeData`. It exercised `wpLightTheme()`, which no longer exists now
    // that the app ships one theme.
    testWidgets('dark theme renders a Scaffold with correct background', (
      tester,
    ) async {
      final theme = wpDarkTheme();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Text('Hello WhisPaste')),
        ),
      );

      expect(find.text('Hello WhisPaste'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    // Removed 2026-08-11 (dark-only build): `dark and light themes have
    // different scaffold backgrounds`. It compared `wpDarkTheme()` against
    // `wpLightTheme()` to prove the app shipped two grounds. There is one
    // ground now, and `wpLightTheme()` itself is removed in the phase that
    // takes out the theme switcher.
    test('the scaffold background is the palette background', () {
      expect(wpDarkTheme().scaffoldBackgroundColor, WpColorsDark.background);
    });

    test('theme appBarTheme uses correct toolbar height', () {
      final dark = wpDarkTheme();
      expect(dark.appBarTheme.toolbarHeight, 64);
    });

    test('theme card shape uses rounded rectangle', () {
      final dark = wpDarkTheme();
      expect(dark.cardTheme.shape, isA<RoundedRectangleBorder>());
    });
  });
}
