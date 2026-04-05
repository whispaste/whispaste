import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/theme_provider.dart';

void main() {
  group('ThemeModeNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('defaults to dark mode', () {
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('setTheme changes mode', () {
      container.read(themeModeProvider.notifier).setTheme(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);

      container.read(themeModeProvider.notifier).setTheme(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('toggleDarkLight switches between dark and light', () {
      expect(container.read(themeModeProvider), ThemeMode.dark);

      container.read(themeModeProvider.notifier).toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.light);

      container.read(themeModeProvider.notifier).toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('toggleDarkLight from system goes to dark (system treated as non-dark)', () {
      container.read(themeModeProvider.notifier).setTheme(ThemeMode.system);
      container.read(themeModeProvider.notifier).toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('isDarkModeProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('returns true for dark mode', () {
      expect(container.read(isDarkModeProvider), true);
    });

    test('returns false for light mode', () {
      container.read(themeModeProvider.notifier).setTheme(ThemeMode.light);
      expect(container.read(isDarkModeProvider), false);
    });

    test('returns true for system mode (defaults to dark)', () {
      container.read(themeModeProvider.notifier).setTheme(ThemeMode.system);
      expect(container.read(isDarkModeProvider), true);
    });
  });
}
