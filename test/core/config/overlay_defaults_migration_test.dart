/// Overlay defaults of 2026-10-29: a fresh install gets amber background, ink
/// wave, compact size and a fixed outline. An existing install keeps the look
/// it had (one-time pin, see `_migrateOverlayDefaults`). A retired neutral
/// wave loads as ink (ADR 0024 Nachtrag 2026-10-29).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/initial_locale.dart';

class _EmptySecureKeyStore extends SecureKeyStore {
  @override
  Future<String?> readKey(String key) async => null;

  @override
  Future<void> writeKey(String key, String value) async {}

  @override
  Future<void> deleteKey(String key) async {}

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

ProviderContainer _container(HistoryDatabase db) => ProviderContainer(
  overrides: [
    historyDatabaseProvider.overrideWithValue(db),
    secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
    systemLocalesProvider.overrideWithValue(const [Locale('en', 'US')]),
  ],
);

/// Loads the settings from the stored rows and returns the container.
Future<ProviderContainer> _load(HistoryDatabase db) async {
  final c = _container(db);
  await c.read(settingsProvider.future);
  await c.read(settingsProvider.notifier).secureKeysFuture;
  return c;
}

/// Fails only the overlay marker write, like a locked or full database.
class _FailingOverlayMarkerDatabase extends HistoryDatabase {
  _FailingOverlayMarkerDatabase() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> writeAppSettings(Map<String, String> values) async {
    if (values.containsKey(kOverlayDefaultsMigrationKey)) {
      throw StateError('database locked');
    }
    await super.writeAppSettings(values);
  }
}

void main() {
  group('overlay defaults for a fresh install', () {
    test('amber, ink, compact, pill and a fixed outline, persisted at the '
        'first start', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final c = await _load(db);
      addTearDown(c.dispose);

      final overlay = c.read(settingsProvider).value!.overlay;
      expect(overlay.overlayBackground, 'amber');
      expect(overlay.overlayWave, 'ink');
      expect(overlay.overlaySize, 'compact');
      expect(overlay.overlayForm, 'pill');
      expect(overlay.overlayWaveFluid, isFalse);

      final rows = await db.readAppSettings();
      expect(rows['overlay_background'], 'amber');
      expect(rows['overlay_wave'], 'ink');
      expect(rows['overlay_size'], 'compact');
      expect(rows['overlay_wave_fluid'], 'false');
      expect(rows[kOverlayDefaultsMigrationKey], '1');
    });
  });

  group('overlay defaults for an existing install', () {
    test(
      'a install without the overlay keys keeps the previous look',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.writeAppSettings({
          'onboarding_completed': 'true',
          'locale': 'en',
          'show_overlay': 'true',
        });
        final c = await _load(db);
        addTearDown(c.dispose);

        final overlay = c.read(settingsProvider).value!.overlay;
        expect(overlay.overlaySize, 'normal');
        expect(overlay.overlayBackground, 'marine');
        expect(overlay.overlayWave, 'cyan');
        expect(overlay.overlayWaveFluid, isTrue);

        final rows = await db.readAppSettings();
        expect(rows['overlay_size'], 'normal');
        expect(rows['overlay_background'], 'marine');
        expect(rows['overlay_wave'], 'cyan');
        expect(rows['overlay_wave_fluid'], 'true');
        expect(rows[kOverlayDefaultsMigrationKey], '1');
      },
    );

    test(
      'an install that stores every overlay key keeps those values',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.writeAppSettings({
          'onboarding_completed': 'true',
          'locale': 'en',
          'overlay_size': 'compact',
          'overlay_background': 'amber',
          'overlay_wave': 'ink',
          'overlay_wave_fluid': 'false',
        });
        final c = await _load(db);
        addTearDown(c.dispose);

        final overlay = c.read(settingsProvider).value!.overlay;
        expect(overlay.overlaySize, 'compact');
        expect(overlay.overlayBackground, 'amber');
        expect(overlay.overlayWave, 'ink');
        expect(overlay.overlayWaveFluid, isFalse);
      },
    );

    test('a later start does not pin again, so a value picked later '
        'is kept', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.writeAppSettings({
        'onboarding_completed': 'true',
        'locale': 'en',
      });

      final first = await _load(db);
      addTearDown(first.dispose);
      expect(first.read(settingsProvider).value!.overlay.overlaySize, 'normal');

      // The user switches to compact later; the next start must keep it.
      await db.writeAppSettings({'overlay_size': 'compact'});
      final second = await _load(db);
      addTearDown(second.dispose);
      expect(
        second.read(settingsProvider).value!.overlay.overlaySize,
        'compact',
      );
      expect(
        second.read(settingsProvider).value!.overlay.overlayBackground,
        'marine',
      );
    });

    test('a failed marker write keeps the pinned look in memory', () async {
      final db = _FailingOverlayMarkerDatabase();
      addTearDown(db.close);
      await db.writeAppSettings({
        'onboarding_completed': 'true',
        'locale': 'en',
      });
      final c = await _load(db);
      addTearDown(c.dispose);

      expect(c.read(settingsProvider).value!.overlay.overlaySize, 'normal');
      expect(c.read(settingsProvider).value!.overlay.overlayWave, 'cyan');
    });
  });

  group('retired neutral wave', () {
    test('a stored neutral on a light background loads as ink', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.writeAppSettings({
        'onboarding_completed': 'true',
        'locale': 'en',
        'overlay_background': 'gletscher',
        'overlay_wave': 'neutral',
      });
      final c = await _load(db);
      addTearDown(c.dispose);
      expect(c.read(settingsProvider).value!.overlay.overlayWave, 'ink');
    });

    test('a stored neutral on a dark background ends on cyan', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.writeAppSettings({
        'onboarding_completed': 'true',
        'locale': 'en',
        'overlay_background': 'marine',
        'overlay_wave': 'neutral',
      });
      final c = await _load(db);
      addTearDown(c.dispose);
      expect(c.read(settingsProvider).value!.overlay.overlayWave, 'cyan');
    });
  });
}
