/// Regression for E8 a (Onboarding v6, V08): an existing install keeps its
/// stored paste setting. Only a new install gets the default. No migration may
/// flip the stored after-transcription action of someone who already finished
/// setup, Windows included. Windows users often keep "clipboard only", which was
/// the earlier default.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/initial_locale.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart'
    show kOnboardingFlowVersion;

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

/// Loads the settings from [stored] and returns the container and database.
Future<(ProviderContainer, HistoryDatabase)> _load(
  Map<String, String> stored,
) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  if (stored.isNotEmpty) await db.writeAppSettings(stored);
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
      systemLocalesProvider.overrideWithValue(const [Locale('en', 'US')]),
    ],
  );
  await container.read(settingsProvider.future);
  await container.read(settingsProvider.notifier).secureKeysFuture;
  return (container, db);
}

/// What an existing Windows install looks like on disk: finished setup on the
/// previous flow version, with the paste setting as the user left it.
Map<String, String> _existingWindowsInstall(String afterTranscription) => {
  'onboarding_completed': 'true',
  'after_transcription': afterTranscription,
};

void main() {
  group('existing install keeps its stored paste setting (E8 a)', () {
    for (final stored in [
      'clipboard',
      'nothing',
      'paste',
      'clipboard_and_paste',
    ]) {
      test('"$stored" survives loading untouched', () async {
        final (container, db) = await _load(_existingWindowsInstall(stored));
        addTearDown(container.dispose);

        expect(
          container
              .read(settingsProvider)
              .value!
              .afterTranscriptionAction
              .value,
          stored,
        );
        expect(
          (await db.readAppSettings())['after_transcription'],
          stored,
          reason: 'No migration may rewrite the stored value.',
        );
      });
    }

    test('an install from before the setting existed keeps the default'
        'gets no value written', () async {
      final (container, db) = await _load({'onboarding_completed': 'true'});
      addTearDown(container.dispose);

      expect(
        container.read(settingsProvider).value!.afterTranscriptionAction,
        AfterTranscriptionAction.clipboard,
      );
    });

    test(
      'stamping the notice as shown does not touch the paste setting',
      () async {
        final (container, db) = await _load(
          _existingWindowsInstall('clipboard'),
        );
        addTearDown(container.dispose);

        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                onboarding: s.onboarding.copyWith(
                  onboardingFlowVersion: kOnboardingFlowVersion,
                ),
              ),
            );

        expect(
          container.read(settingsProvider).value!.afterTranscriptionAction,
          AfterTranscriptionAction.clipboard,
        );
        expect(
          (await db.readAppSettings())['after_transcription'],
          'clipboard',
        );
      },
    );
  });
}
