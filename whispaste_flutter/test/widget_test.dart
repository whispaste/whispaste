import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    testWidgets('wpLightTheme builds a valid ThemeData', (tester) async {
      final theme = wpLightTheme();

      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const Scaffold()),
      );

      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme renders a Scaffold with correct background',
        (tester) async {
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

    test('dark and light themes have different scaffold backgrounds', () {
      final dark = wpDarkTheme();
      final light = wpLightTheme();

      expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));
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
