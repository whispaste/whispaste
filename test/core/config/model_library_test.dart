/// The model library's lists (#1514): what each section shows, in which
/// order, which actions an entry offers, and what "use" changes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/model_library.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/models/bundled_model_catalog.dart';
import 'package:whispaste/services/download_error_kind.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_models_provider.dart';

UserModel _own(
  String id,
  UserModelRuntime runtime, {
  UserModelStatus status = UserModelStatus.ready,
  UserModelFailure? failure,
  UserModelSourceKind source = UserModelSourceKind.huggingFace,
}) => UserModel(
  id: id,
  name: id,
  runtime: runtime,
  sourceKind: source,
  files: const [
    UserModelFile(role: UserModelFileRole.model, name: 'm', sizeBytes: 300),
  ],
  addedAt: DateTime.utc(2026, 11, 17),
  status: status,
  failure: failure,
);

List<SelectableSpeechModel> _speech({
  Set<String> downloaded = const {},
  AppSettings? settings,
}) => selectableSpeechModels(
  settings: settings ?? AppSettings.defaults,
  downloads: ModelDownloadState(downloadedModels: downloaded, scanned: true),
  parakeet: const ParakeetDownloadState(installed: true),
  models: sttModels.take(2).toList(),
);

void main() {
  group('speech section', () {
    test('the device recommendation comes first and is marked', () {
      final models = _speech();
      final entries = speechLibraryEntries(
        models,
        recommendedId: recommendedSpeechLibraryId(
          const EngineRecommendation(engine: OnDeviceEngine.parakeet),
        ),
      );
      expect(entries.first.id, SpeechModelEngine.parakeet.name);
      expect(entries.first.recommended, isTrue);
      expect(entries.where((e) => e.recommended), hasLength(1));
    });

    test('a model not on disk offers install, with its catalog facts', () {
      final first = sttModels.first;
      final entry = speechLibraryEntries(
        _speech(),
      ).firstWhere((e) => e.id == first.id);
      expect(entry.status, ModelLibraryStatus.notInstalled);
      expect(entry.canInstall, isTrue);
      expect(entry.canActivate, isFalse);
      expect(entry.canRemove, isFalse);
      expect(entry.location, ModelLocation.local);
      final catalog = bundledModelCatalog.tryById(first.id);
      expect(entry.sizeBytes, catalog?.sizeBytes ?? 0);
      expect(entry.speed, catalog?.speed);
    });

    test('a downloaded model can be used and removed', () {
      final first = sttModels.first;
      final entry = speechLibraryEntries(
        _speech(downloaded: {first.id}),
      ).firstWhere((e) => e.id == first.id);
      expect(entry.canActivate, isTrue);
      expect(entry.canRemove, isTrue);

      final after = activateLibraryEntry(AppSettings.defaults, entry);
      expect(after.sttProvider, SttProviderType.onDevice.value);
      expect(after.onDeviceEngine, OnDeviceEngine.whisper);
      expect(after.sttModel, first.id);
    });

    test('own speech models follow, marked not checked', () {
      final own = UserModelsState(
        models: [
          _own('user-aaaaaaaaaaaa', UserModelRuntime.whispercpp),
          _own('user-bbbbbbbbbbbb', UserModelRuntime.llamaCpp),
        ],
      );
      final entries = speechLibraryEntries(_speech(), own: own);
      final mine = entries.where((e) => e.userModel != null).toList();
      expect(mine.map((e) => e.id), ['user-aaaaaaaaaaaa']);
      expect(entries.last.id, 'user-aaaaaaaaaaaa');
      final entry = mine.single;
      expect(entry.verified, isFalse);
      expect(entry.status, ModelLibraryStatus.installed);
      expect(entry.canRemove, isTrue);
    });
  });

  group('fit to the dictation languages (#1953)', () {
    SelectableSpeechModel apple() => SelectableSpeechModel(
      engine: SpeechModelEngine.system,
      modelId: 'apple-speech',
      displayName: (_) => 'Apple',
      group: SpeechModelGroup.local,
      state: const SpeechModelReady(),
    );

    test('missing languages come from the catalog list', () {
      final parakeet = bundledModelCatalog.tryById(CatalogIds.parakeet);
      expect(missingDictationLanguages(parakeet, ['de', 'en']), isEmpty);
      expect(missingDictationLanguages(parakeet, ['de', 'ja', 'ko']), [
        'ja',
        'ko',
      ]);
    });

    test('no catalog entry, no fixed list or no language: no claim', () {
      expect(missingDictationLanguages(null, ['de']), isNull);
      expect(missingDictationLanguages(smartModeModel, ['de']), isNull);
      final whisper = bundledModelCatalog.tryById(sttModels.first.id);
      expect(missingDictationLanguages(whisper, const []), isNull);
    });

    test('Parakeet misses Japanese and moves behind the models that fit', () {
      final entries = speechLibraryEntries(
        _speech(),
        dictationLanguages: const ['de', 'ja'],
      );
      final parakeet = entries.firstWhere(
        (e) => e.id == SpeechModelEngine.parakeet.name,
      );
      expect(parakeet.missingLanguages, ['ja']);
      expect(parakeet.missesLanguages, isTrue);
      final whisper = entries.firstWhere((e) => e.id == sttModels.first.id);
      expect(whisper.fitsLanguages, isTrue);
      expect(entries.last, same(parakeet));
    });

    test('the recommendation stays first even when listed later', () {
      final entries = speechLibraryEntries(
        _speech(),
        recommendedId: SpeechModelEngine.parakeet.name,
        dictationLanguages: const ['de'],
      );
      expect(entries.first.id, SpeechModelEngine.parakeet.name);
      expect(entries.first.fitsLanguages, isTrue);
    });

    test('engines without catalog languages and own models claim nothing', () {
      final entries = speechLibraryEntries(
        [..._speech(), apple()],
        dictationLanguages: const ['de'],
        own: UserModelsState(
          models: [_own('user-aaaaaaaaaaaa', UserModelRuntime.whispercpp)],
        ),
      );
      final system = entries.firstWhere(
        (e) => e.id == SpeechModelEngine.system.name,
      );
      expect(system.missingLanguages, isNull);
      expect(system.fitsLanguages, isFalse);
      expect(entries.last.id, 'user-aaaaaaaaaaaa');
      expect(entries.last.missingLanguages, isNull);
    });
  });

  group('own models', () {
    test('a running addition shows progress and cannot be removed', () {
      final model = _own(
        'user-aaaaaaaaaaaa',
        UserModelRuntime.llamaCpp,
        status: UserModelStatus.checking,
      );
      final entry = ownLibraryEntries(
        UserModelsState(models: [model], installingId: model.id),
        UserModelPurpose.smartMode,
      ).single;
      expect(entry.status, ModelLibraryStatus.downloading);
      expect(entry.canCancel, isTrue);
      expect(entry.canRemove, isFalse);
    });

    test('a failed model keeps its reason; retry only for downloads', () {
      final fromWeb = ownLibraryEntries(
        UserModelsState(
          models: [
            _own(
              'user-aaaaaaaaaaaa',
              UserModelRuntime.llamaCpp,
              status: UserModelStatus.failed,
              failure: UserModelFailure.shortTestFailed,
            ),
            _own(
              'user-bbbbbbbbbbbb',
              UserModelRuntime.llamaCpp,
              status: UserModelStatus.failed,
              failure: UserModelFailure.badFormat,
              source: UserModelSourceKind.file,
            ),
          ],
        ),
        UserModelPurpose.smartMode,
      );
      expect(fromWeb[0].failure, UserModelFailure.shortTestFailed);
      expect(fromWeb[0].canRetry, isTrue);
      expect(fromWeb[0].canRemove, isTrue);
      expect(fromWeb[1].canRetry, isFalse);
    });
  });

  group('using own models (#1789)', () {
    test('a ready own speech model can be used and shows as active', () {
      final whisper = _own('user-aaaaaaaaaaaa', UserModelRuntime.whispercpp);
      final sherpa = _own('user-bbbbbbbbbbbb', UserModelRuntime.sherpaOnnx);
      final failed = _own(
        'user-cccccccccccc',
        UserModelRuntime.sherpaOnnx,
        status: UserModelStatus.failed,
        failure: UserModelFailure.failedInUse,
      );
      final entries = ownLibraryEntries(
        UserModelsState(models: [whisper, sherpa, failed]),
        UserModelPurpose.speech,
        activeId: sherpa.id,
      );
      expect(entries[0].canActivate, isTrue);
      expect(entries[1].status, ModelLibraryStatus.active);
      expect(entries[2].canActivate, isFalse);

      final after = activateLibraryEntry(AppSettings.defaults, entries[0]);
      expect(after.onDeviceEngine, OnDeviceEngine.whisper);
      expect(after.effectiveModelId, whisper.id);
      final sherpaAfter = activateLibraryEntry(after, entries[1]);
      expect(sherpaAfter.onDeviceEngine, OnDeviceEngine.userModel);
      expect(sherpaAfter.effectiveModelId, sherpa.id);
    });

    test('an own Smart Mode model in use replaces Gemma as active', () {
      final own = _own('user-dddddddddddd', UserModelRuntime.llamaCpp);
      final settings = activateLibraryEntry(
        AppSettings.defaults,
        ownLibraryEntries(
          UserModelsState(models: [own]),
          UserModelPurpose.smartMode,
        ).single,
      );
      expect(settings.smartMode.provider, SmartModeProviderType.local.value);
      expect(settings.smartMode.localModel, own.id);

      final entries = smartModeLibraryEntries(
        settings: settings,
        download: const SmartModeDownloadState(modelDownloaded: true),
        localEngineAvailable: true,
        own: UserModelsState(models: [own]),
      );
      expect(entries.first.status, ModelLibraryStatus.installed);
      expect(entries.last.status, ModelLibraryStatus.active);

      // Choosing Gemma again sets the own model aside.
      final back = activateLibraryEntry(settings, entries.first);
      expect(back.smartMode.localModel, isEmpty);
    });
  });

  group('Smart Mode section', () {
    test('Gemma is always first and recommended; cloud only when set up', () {
      final entries = smartModeLibraryEntries(
        settings: AppSettings.defaults,
        download: const SmartModeDownloadState(),
        localEngineAvailable: true,
      );
      expect(entries.map((e) => e.id), ['gemma']);
      expect(entries.single.recommended, isTrue);
      expect(entries.single.canInstall, isTrue);

      final withKey = smartModeLibraryEntries(
        settings: AppSettings.defaults.copyWithSections(
          cloudProvider: AppSettings.defaults.cloudProvider.copyWith(
            openAiApiKey: 'k',
          ),
        ),
        download: const SmartModeDownloadState(modelDownloaded: true),
        localEngineAvailable: true,
      );
      expect(withKey.map((e) => e.id), ['gemma', 'smart-openai']);
      expect(withKey.first.recommended, isTrue);
    });

    test('switching to OpenAI changes the Smart Mode service', () {
      final settings = AppSettings.defaults.copyWithSections(
        cloudProvider: AppSettings.defaults.cloudProvider.copyWith(
          openAiApiKey: 'k',
        ),
      );
      final openAi = smartModeLibraryEntries(
        settings: settings,
        download: const SmartModeDownloadState(modelDownloaded: true),
        localEngineAvailable: true,
      ).firstWhere((e) => e.id == 'smart-openai');
      expect(openAi.canActivate, isTrue);
      final after = activateLibraryEntry(settings, openAi);
      expect(after.smartMode.provider, SmartModeProviderType.openAI.value);
    });

    test('without the local engine Gemma is shown as not available', () {
      final gemma = smartModeLibraryEntries(
        settings: AppSettings.defaults,
        download: const SmartModeDownloadState(),
        localEngineAvailable: false,
      ).single;
      expect(gemma.status, ModelLibraryStatus.unavailable);
      expect(gemma.canInstall, isFalse);
    });
  });

  test('offline only when a download failed for lack of a connection', () {
    expect(
      modelLibraryOffline(
        whisper: const ModelDownloadState(),
        parakeet: const ParakeetDownloadState(),
        smartMode: const SmartModeDownloadState(),
      ),
      isFalse,
    );
    expect(
      modelLibraryOffline(
        whisper: const ModelDownloadState(),
        parakeet: const ParakeetDownloadState(),
        smartMode: const SmartModeDownloadState(
          phase: SmartModeDownloadPhase.error,
          errorKind: DownloadErrorKind.offline,
        ),
      ),
      isTrue,
    );
  });
}
