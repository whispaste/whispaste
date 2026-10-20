import 'dart:async' show TimeoutException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/drift_recording_store.dart'
    show factKnownTermsProvider;
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_fact_guard.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/smart_mode/smart_mode_retroactive_service.dart';

/// Fake [SmartModeDownloadNotifier] — pins [modelDownloaded] without
/// touching disk (mirrors the orchestrator test's fake).
class _FakeSmartModeDownloadNotifier extends SmartModeDownloadNotifier {
  _FakeSmartModeDownloadNotifier({this.modelDownloaded = true});

  final bool modelDownloaded;

  @override
  SmartModeDownloadState build() =>
      SmartModeDownloadState(modelDownloaded: modelDownloaded);
}

/// Fake [SmartModeEngine] — configurable success/failure/delay, no real
/// FFI/model involved.
class _FakeSmartModeEngine implements SmartModeEngine {
  String? resultToReturn;
  Object? errorToThrow;
  Duration delay = Duration.zero;

  int runCalls = 0;
  String? lastSystemPrompt;
  String? lastUserText;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    runCalls++;
    lastSystemPrompt = systemPrompt;
    lastUserText = userText;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final error = errorToThrow;
    if (error != null) throw error;
    return resultToReturn ?? userText;
  }

  int cancelCalls = 0;

  @override
  Future<void> cancel() async => cancelCalls++;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

void main() {
  late _FakeSmartModeEngine fakeEngine;
  late ProviderContainer container;

  ProviderContainer buildContainer({
    bool modelDownloaded = true,
    SmartModeProviderType provider = SmartModeProviderType.local,
    String sttLanguage = 'auto',
  }) {
    return ProviderContainer(
      overrides: [
        factKnownTermsProvider.overrideWith(
          (ref) =>
              () async => const <String>[],
        ),
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings.defaults.copyWithSections(
              smartMode: AppSettings.defaults.smartMode.copyWith(
                provider: provider.value,
              ),
              stt: AppSettings.defaults.stt.copyWith(language: sttLanguage),
            ),
          ),
        ),
        smartModeDownloadProvider.overrideWith(
          () =>
              _FakeSmartModeDownloadNotifier(modelDownloaded: modelDownloaded),
        ),
        smartModeEngineProvider.overrideWith((ref) => fakeEngine),
      ],
    );
  }

  setUp(() {
    fakeEngine = _FakeSmartModeEngine();
    SmartModeRetroactiveService.timeoutOverride = const Duration(
      milliseconds: 200,
    );
  });

  tearDown(() {
    SmartModeRetroactiveService.timeoutOverride = null;
    container.dispose();
  });

  group('SmartModeRetroactiveService.apply', () {
    test('model not downloaded — fails without calling the engine', () async {
      container = buildContainer(modelDownloaded: false);
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'raw text',
        preset: SmartModePreset.cleanup,
      );

      expect(result, isA<SmartModeRetroactiveFailure>());
      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.modelMissing,
      );
      expect(fakeEngine.runCalls, 0);
    });

    test(
      'cloud provider runs without a local model (ADR 0010 either-or)',
      () async {
        container = buildContainer(
          modelDownloaded: false,
          provider: SmartModeProviderType.openAI,
        );
        await container.read(settingsProvider.future);
        fakeEngine.resultToReturn = 'Cleaned text.';
        final service = container.read(smartModeRetroactiveServiceProvider);

        final result = await service.apply(
          rawText: 'raw text',
          preset: SmartModePreset.cleanup,
        );

        expect(result, isA<SmartModeRetroactiveSuccess>());
        expect(fakeEngine.runCalls, 1);
      },
    );

    test('a changed name fails with factsChanged (matrix 2.5)', () async {
      container = buildContainer();
      fakeEngine.resultToReturn = 'Ich habe mit Anna Meier gesprochen.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'Ich habe mit Anna Schmidt gesprochen.',
        preset: SmartModePreset.cleanup,
      );

      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.factsChanged,
      );
    });

    test(
      'a fact check that times out fails with checkTimedOut (DEV-151)',
      () async {
        container = buildContainer();
        fakeEngine.resultToReturn = 'Ich habe mit Anna Meier gesprochen.';
        debugSmartModeFactGuardOverride =
            ({
              required input,
              required output,
              required checkNames,
              required knownTerms,
              required singleCapitalisedWordsAreNames,
            }) => throw TimeoutException('slow guard');
        addTearDown(() => debugSmartModeFactGuardOverride = null);
        final service = container.read(smartModeRetroactiveServiceProvider);

        final result = await service.apply(
          rawText: 'Ich habe mit Anna Schmidt gesprochen.',
          preset: SmartModePreset.cleanup,
        );

        expect(
          (result as SmartModeRetroactiveFailure).reason,
          SmartModeRetroactiveFailureReason.checkTimedOut,
        );
      },
    );

    test('auto with a detected English entry applies English name rules '
        '(DEV-107)', () async {
      container = buildContainer();
      fakeEngine.resultToReturn = 'We met Smith yesterday.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'We met Brown yesterday.',
        preset: SmartModePreset.cleanup,
        detectedLanguage: 'en',
      );

      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.factsChanged,
      );
    });

    test('auto with a detected German entry keeps single words free '
        '(DEV-107)', () async {
      container = buildContainer();
      fakeEngine.resultToReturn = 'We met Smith yesterday.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'We met Brown yesterday.',
        preset: SmartModePreset.cleanup,
        detectedLanguage: 'de',
      );

      expect(result, isA<SmartModeRetroactiveSuccess>());
    });

    test('the recorded language decides the name rule, not the current '
        'setting (DEV-124)', () async {
      container = buildContainer(sttLanguage: 'de');
      fakeEngine.resultToReturn = 'We met Smith yesterday.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'We met Brown yesterday.',
        preset: SmartModePreset.cleanup,
        languageCode: 'en',
      );

      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.factsChanged,
      );
    });

    test('a recording made in auto without a detected language follows '
        'German rules, whatever the setting says (DEV-124)', () async {
      container = buildContainer(sttLanguage: 'en');
      fakeEngine.resultToReturn = 'We met Smith yesterday.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'We met Brown yesterday.',
        preset: SmartModePreset.cleanup,
        languageCode: 'auto',
      );

      expect(result, isA<SmartModeRetroactiveSuccess>());
    });

    test('an entry without a recorded language falls back to the current '
        'setting (DEV-124)', () async {
      container = buildContainer(sttLanguage: 'en');
      fakeEngine.resultToReturn = 'We met Smith yesterday.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'We met Brown yesterday.',
        preset: SmartModePreset.cleanup,
        languageCode: '',
      );

      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.factsChanged,
      );
    });

    test('cleanup preset succeeds and returns the engine result', () async {
      container = buildContainer();
      fakeEngine.resultToReturn = 'Cleaned text.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'raw text with um filler',
        preset: SmartModePreset.cleanup,
      );

      expect(result, isA<SmartModeRetroactiveSuccess>());
      expect(
        (result as SmartModeRetroactiveSuccess).editedContent,
        'Cleaned text.',
      );
      expect(fakeEngine.runCalls, 1);
      expect(fakeEngine.lastUserText, 'raw text with um filler');
    });

    test('translate preset uses the target-language system prompt', () async {
      container = buildContainer();
      fakeEngine.resultToReturn = 'Hallo Welt.';
      final service = container.read(smartModeRetroactiveServiceProvider);

      await service.apply(
        rawText: 'Hello world.',
        preset: SmartModePreset.translate,
        targetLanguage: SmartModeTargetLanguage.german,
      );

      expect(
        fakeEngine.lastSystemPrompt,
        smartModeSystemPromptFor(
          SmartModePreset.translate,
          targetLanguage: SmartModeTargetLanguage.german,
        ),
      );
    });

    test('engine timeout — fails with reason timeout', () async {
      container = buildContainer();
      fakeEngine.delay = const Duration(seconds: 5);
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'raw text',
        preset: SmartModePreset.concise,
      );

      expect(result, isA<SmartModeRetroactiveFailure>());
      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.timeout,
      );
      expect(
        fakeEngine.cancelCalls,
        1,
        reason: 'a timed-out generation must be aborted, not left running',
      );
    });

    test('engine throws — fails with reason engineError', () async {
      container = buildContainer();
      fakeEngine.errorToThrow = StateError('ffi crashed');
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'raw text',
        preset: SmartModePreset.cleanup,
      );

      expect(result, isA<SmartModeRetroactiveFailure>());
      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.engineError,
      );
    });

    test('blank engine result — fails with reason blankResult', () async {
      container = buildContainer();
      fakeEngine.resultToReturn = '   ';
      final service = container.read(smartModeRetroactiveServiceProvider);

      final result = await service.apply(
        rawText: 'raw text',
        preset: SmartModePreset.cleanup,
      );

      expect(result, isA<SmartModeRetroactiveFailure>());
      expect(
        (result as SmartModeRetroactiveFailure).reason,
        SmartModeRetroactiveFailureReason.blankResult,
      );
    });
  });
}
