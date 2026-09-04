import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
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
}

void main() {
  late _FakeSmartModeEngine fakeEngine;
  late ProviderContainer container;

  ProviderContainer buildContainer({bool modelDownloaded = true}) {
    return ProviderContainer(
      overrides: [
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
