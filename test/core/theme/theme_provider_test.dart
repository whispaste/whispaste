import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/theme_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/main.dart' as app_bootstrap;
import 'package:whispaste/services/multi_window_service.dart';

void main() {
  group('themeModeProvider (derived from settings)', () {
    late HistoryDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      await container.read(settingsProvider.future);
    });

    tearDown(() {
      container.dispose();
    });

    test('defaults to dark mode', () {
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('changes when settings theme changes', () async {
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(themeMode: ThemeMode.light),
          );
      expect(container.read(themeModeProvider), ThemeMode.light);

      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(themeMode: ThemeMode.system),
          );
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('toggleDarkLight switches between dark and light', () async {
      expect(container.read(themeModeProvider), ThemeMode.dark);

      await container.read(settingsProvider.notifier).toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.light);

      await container.read(settingsProvider.notifier).toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('toggleDarkLight from system goes to dark', () async {
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(themeMode: ThemeMode.system),
          );
      // system != dark, so toggle goes to light? No — toggle checks == dark.
      // system is NOT dark, so next = dark.
      await container.read(settingsProvider.notifier).toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('isDarkModeProvider', () {
    late HistoryDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      await container.read(settingsProvider.future);
    });

    tearDown(() {
      container.dispose();
    });

    test('returns true for dark mode', () {
      expect(container.read(isDarkModeProvider), true);
    });

    test('returns false for light mode', () async {
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(themeMode: ThemeMode.light),
          );
      expect(container.read(isDarkModeProvider), false);
    });

    test('returns true for system mode (defaults to dark)', () async {
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(themeMode: ThemeMode.system),
          );
      expect(container.read(isDarkModeProvider), true);
    });
  });

  group('bootstrapAppContainer', () {
    // Stub notifier that does nothing — prevents MultiWindowNotifier from
    // creating timers (showButton, ensureOverlay) that break pumpAndSettle.
    final multiWindowStub =
        multiWindowProvider.overrideWith(() => _StubMultiWindowNotifier());

    testWidgets('uses persisted light theme on the first frame', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.writeAppSettings(
        const AppSettings(themeMode: ThemeMode.light).toStorageMap(),
      );

      final container = await app_bootstrap.bootstrapAppContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          multiWindowStub,
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WhisPasteApp(),
        ),
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(app.themeMode, ThemeMode.light);
    });

    testWidgets('preserves persisted system theme on the first frame', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.writeAppSettings(
        const AppSettings(themeMode: ThemeMode.system).toStorageMap(),
      );

      final container = await app_bootstrap.bootstrapAppContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          multiWindowStub,
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WhisPasteApp(),
        ),
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(app.themeMode, ThemeMode.system);
    });
  });
}

/// Stub [MultiWindowNotifier] that does nothing — no timers, no listeners.
class _StubMultiWindowNotifier extends MultiWindowNotifier {
  @override
  MultiWindowState build() => const MultiWindowState();
}
