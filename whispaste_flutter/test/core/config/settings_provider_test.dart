import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/locale_provider.dart';
import 'package:whispaste/core/theme/theme_provider.dart';
import 'package:whispaste/features/history/data/database.dart';

void main() {
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

  test('loads defaults when no settings rows exist', () {
    final settings = container.read(settingsProvider).value;

    expect(settings, isNotNull);
    expect(settings!.themeMode, ThemeMode.dark);
    expect(settings.locale, 'en');
    expect(settings.showOverlay, true);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('persists updates in drift and can reset to defaults', () async {
    await container.read(settingsProvider.notifier).updateSettings(
          (settings) => settings.copyWith(
            themeMode: ThemeMode.light,
            locale: 'de',
            sttModel: 'Best Quality (Large)',
            showOverlay: false,
            recordStartSound: false,
          ),
        );

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(container.read(localeProvider), const Locale('de'));

    final persisted = AppSettings.fromStorageMap(await db.readAppSettings());
    expect(persisted.themeMode, ThemeMode.light);
    expect(persisted.locale, 'de');
    expect(persisted.sttModel, 'Best Quality (Large)');
    expect(persisted.showOverlay, false);
    expect(persisted.recordStartSound, false);

    await container.read(settingsProvider.notifier).resetToDefaults();

    final rowsAfterReset = await db.readAppSettings();
    final resetState = container.read(settingsProvider).value;

    expect(rowsAfterReset, isEmpty);
    expect(resetState, isNotNull);
    expect(resetState!.themeMode, ThemeMode.dark);
    expect(resetState.locale, 'en');
    expect(resetState.showOverlay, true);
  });
}
