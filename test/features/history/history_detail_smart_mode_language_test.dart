/// Retroactive Smart Mode from the History detail panel uses the language the
/// entry was recorded in (DEV-132): an `auto` recording takes the language the
/// engine detected, stored with the entry.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/history_detail_provider.dart';
import 'package:whispaste/services/drift_recording_store.dart'
    show factKnownTermsProvider;
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_fact_guard.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/smart_mode/smart_mode_retroactive_service.dart'
    show SmartModeRetroactiveFailureReason;

class _FakeDownload extends SmartModeDownloadNotifier {
  @override
  SmartModeDownloadState build() =>
      const SmartModeDownloadState(modelDownloaded: true);
}

class _FakeEngine implements SmartModeEngine {
  String result = '';

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async => result;

  @override
  Future<void> cancel() async {}
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;
  late _FakeEngine engine;

  const entryId = 'auto-entry';

  Future<void> seed({required String language, required String detected}) {
    return db.insertHistoryEntry(
      HistoryEntriesCompanion(
        id: const Value(entryId),
        content: const Value('We met Brown yesterday.'),
        title: const Value('Titel'),
        timestamp: Value(DateTime(2026, 10, 18)),
        language: Value(language),
        languageHint: Value(detected),
        originalTranscript: const Value('We met Brown yesterday.'),
      ),
    );
  }

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    engine = _FakeEngine()..result = 'We met Smith yesterday.';
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        settingsProvider.overrideWith(_FakeSettings.new),
        smartModeDownloadProvider.overrideWith(_FakeDownload.new),
        smartModeEngineProvider.overrideWith((ref) => engine),
        factKnownTermsProvider.overrideWith(
          (ref) =>
              () async => const <String>[],
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
  });

  Future<HistoryPresetApplicationResult> apply() async {
    container.listen(historyDetailProvider(entryId), (_, _) {});
    await container.read(historyDetailProvider(entryId).future);
    return container
        .read(historyDetailProvider(entryId).notifier)
        .applyPreset(SmartModePreset.cleanup);
  }

  test(
    'an auto recording detected as English gets English name rules',
    () async {
      await seed(language: 'auto', detected: 'en');

      final result = await apply();

      expect(
        (result as HistoryPresetApplicationFailure).reason,
        SmartModeRetroactiveFailureReason.factsChanged,
      );
    },
  );

  test(
    'an auto recording without a detected language keeps German rules',
    () async {
      await seed(language: 'auto', detected: '');

      final result = await apply();

      expect(result, isA<HistoryPresetApplicationSuccess>());
    },
  );

  test(
    'a throwing fact guard fails closed and clears the busy flag (DEV-141)',
    () async {
      await seed(language: 'de', detected: '');
      debugSmartModeFactGuardOverride =
          ({
            required input,
            required output,
            required checkNames,
            required knownTerms,
            required singleCapitalisedWordsAreNames,
          }) => throw StateError('boom');
      addTearDown(() => debugSmartModeFactGuardOverride = null);

      final result = await apply();

      expect(
        (result as HistoryPresetApplicationFailure).reason,
        SmartModeRetroactiveFailureReason.factsChanged,
      );
      final state = container
          .read(historyDetailProvider(entryId))
          .asData!
          .value;
      expect(state.applyingPreset, isFalse);
      final entry = await db.getEntry(entryId);
      expect(entry!.smartModeEditedContent, isNull);
    },
  );
}
