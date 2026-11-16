import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show CloudProviderSettings;
import 'package:whispaste/core/overview/speech_setup.dart';
import 'package:whispaste/core/recording/recording_state.dart'
    show SttServerState;

const _small = 'whisper-small';
const _medium = 'whisper-medium';

SelectableSpeechModel _whisper(String id, SpeechModelState state) =>
    SelectableSpeechModel(
      engine: SpeechModelEngine.whisper,
      modelId: id,
      displayName: (_) => id,
      group: SpeechModelGroup.local,
      state: state,
    );

SelectableSpeechModel _parakeet(SpeechModelState state) =>
    SelectableSpeechModel(
      engine: SpeechModelEngine.parakeet,
      modelId: OnDeviceEngine.parakeet.value,
      displayName: (_) => 'Parakeet',
      group: SpeechModelGroup.local,
      state: state,
    );

AppSettings _settings({
  SttProviderType provider = SttProviderType.onDevice,
  OnDeviceEngine engine = OnDeviceEngine.whisper,
  String model = _small,
  String mic = 'Default',
}) {
  final d = AppSettings.defaults;
  return d.copyWithSections(
    stt: d.stt.copyWith(
      provider: provider.value,
      engine: engine.value,
      model: model,
    ),
    audioInput: d.audioInput.copyWith(microphone: mic),
  );
}

OverviewSpeechSetup _setup({
  AppSettings? settings,
  List<SelectableSpeechModel> models = const [],
  SttServerState whisper = SttServerState.stopped,
  String whisperModel = '',
  SttServerState parakeet = SttServerState.stopped,
  List<String>? devices = const ['Default', 'Built-in'],
  bool listingUnavailable = false,
  bool denied = false,
}) => overviewSpeechSetup(
  settings: settings ?? _settings(),
  models: models,
  whisperState: whisper,
  whisperModelId: whisperModel,
  parakeetState: parakeet,
  micDevices: devices,
  micListingUnavailable: listingUnavailable,
  micDenied: denied,
);

void main() {
  group('engine', () {
    test('follows provider and on-device engine', () {
      expect(_setup().engine, SpeechModelEngine.whisper);
      expect(_setup().onDevice, isTrue);
      final parakeet = _setup(
        settings: _settings(engine: OnDeviceEngine.parakeet),
      );
      expect(parakeet.engine, SpeechModelEngine.parakeet);
      final cloud = _setup(
        settings: _settings(provider: SttProviderType.deepgram),
      );
      expect(cloud.engine, SpeechModelEngine.deepgram);
      expect(cloud.onDevice, isFalse);
    });
  });

  group('speech model', () {
    test('loaded only when the engine holds the selected model', () {
      final models = [_whisper(_small, const SpeechModelActive())];
      expect(
        _setup(
          models: models,
          whisper: SttServerState.ready,
          whisperModel: _small,
        ).modelState,
        OverviewModelState.ready,
      );
      // A model switch: the engine still holds the previous one.
      expect(
        _setup(
          models: models,
          whisper: SttServerState.ready,
          whisperModel: _medium,
        ).modelState,
        OverviewModelState.loadsOnDictation,
      );
    });

    test('on disk but not in memory loads with the next dictation', () {
      final s = _setup(models: [_whisper(_small, const SpeechModelActive())]);
      expect(s.modelId, _small);
      expect(s.modelState, OverviewModelState.loadsOnDictation);
    });

    test('loading and a failed load are told apart', () {
      final models = [_whisper(_small, const SpeechModelLoading())];
      expect(
        _setup(
          models: models,
          whisper: SttServerState.starting,
          whisperModel: _small,
        ).modelState,
        OverviewModelState.loading,
      );
      expect(
        _setup(
          models: models,
          whisper: SttServerState.error,
          whisperModel: _small,
        ).modelState,
        OverviewModelState.failed,
      );
    });

    test('a missing or downloading model wins over the engine state', () {
      expect(
        _setup(
          models: [_whisper(_small, const SpeechModelNotDownloaded())],
        ).modelState,
        OverviewModelState.notDownloaded,
      );
      final downloading = _setup(
        models: [_whisper(_small, const SpeechModelDownloading(42))],
      );
      expect(downloading.modelState, OverviewModelState.downloading);
      expect(downloading.downloadPercent, 42);
    });

    test('only the selected Whisper entry counts', () {
      final s = _setup(
        models: [
          _whisper(_medium, const SpeechModelNotDownloaded()),
          _whisper(_small, const SpeechModelActive()),
        ],
      );
      expect(s.modelState, OverviewModelState.loadsOnDictation);
    });

    test('Parakeet follows its own engine state', () {
      final s = _setup(
        settings: _settings(engine: OnDeviceEngine.parakeet),
        models: [_parakeet(const SpeechModelActive())],
        whisper: SttServerState.ready,
        whisperModel: _small,
        parakeet: SttServerState.ready,
      );
      expect(s.modelState, OverviewModelState.ready);
      expect(
        _setup(
          settings: _settings(engine: OnDeviceEngine.parakeet),
          models: [_parakeet(const SpeechModelNotDownloaded())],
        ).modelState,
        OverviewModelState.notDownloaded,
      );
    });

    test('cloud providers name their fixed model and have no load state', () {
      final openAi = _setup(
        settings: _settings(provider: SttProviderType.openAI),
      );
      expect(openAi.modelId, kOverviewOpenAiModel);
      expect(openAi.modelState, OverviewModelState.cloud);
    });

    test('a custom endpoint without a model has an empty model id', () {
      final s = _setup(
        settings: _settings(
          provider: SttProviderType.customEndpoint,
        ).copyWithSections(cloudProvider: const CloudProviderSettings()),
      );
      expect(s.modelId, isEmpty);
    });
  });

  group('microphone', () {
    test('system default with devices present', () {
      final s = _setup();
      expect(s.micState, OverviewMicState.systemDefault);
      expect(s.micName, isNull);
    });

    test('a chosen device is connected or not', () {
      expect(
        _setup(settings: _settings(mic: 'Built-in')).micState,
        OverviewMicState.device,
      );
      final gone = _setup(settings: _settings(mic: 'USB Mic'));
      expect(gone.micState, OverviewMicState.disconnected);
      expect(gone.micName, 'USB Mic');
    });

    test('an empty device list says no microphone was found', () {
      expect(
        _setup(devices: const ['Default']).micState,
        OverviewMicState.noneFound,
      );
    });

    test('no listing tool or a running listing claims nothing missing', () {
      expect(
        _setup(
          settings: _settings(mic: 'USB Mic'),
          devices: const ['Default'],
          listingUnavailable: true,
        ).micState,
        OverviewMicState.device,
      );
      expect(_setup(devices: null).micState, OverviewMicState.systemDefault);
    });

    test('a refused permission wins over every device state', () {
      expect(_setup(denied: true).micState, OverviewMicState.noAccess);
    });
  });
}
