import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

AppSettings _settings({
  String openAiKey = '',
  String model = 'whisper-small',
  String? provider,
}) {
  final base = AppSettings.defaults
      .copyWith(sttModel: model)
      .copyWithSections(
        cloudProvider: AppSettings.defaults.cloudProvider.copyWith(
          openAiApiKey: openAiKey,
        ),
      );
  return provider == null ? base : base.copyWith(sttProvider: provider);
}

final _models = sttModels.take(2).toList();
final _small = _models[0];
final _medium = _models[1];

List<SelectableSpeechModel> _entries({
  AppSettings? settings,
  Set<String> downloaded = const {},
  ModelDownloadState? downloads,
  String? loading,
  ParakeetDownloadState parakeet = const ParakeetDownloadState(installed: true),
}) => selectableSpeechModels(
  settings: settings ?? _settings(),
  parakeet: parakeet,
  downloads:
      downloads ??
      ModelDownloadState(downloadedModels: downloaded, scanned: true),
  models: _models,
  loadingModelId: loading,
);

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('whisper models in list order, then Parakeet, then usable cloud', () {
    final ids = [
      for (final e in _entries(settings: _settings(openAiKey: 'k')))
        e.choiceValue,
    ];
    expect(ids, [
      'download:${_small.id}',
      'download:${_medium.id}',
      OnDeviceEngine.parakeet.value,
      SttProviderType.openAI.name,
    ]);
  });

  test('each entry carries engine, model id, group and size', () {
    final entries = _entries(downloaded: {_small.id});
    final small = entries.firstWhere((e) => e.modelId == _small.id);
    expect(small.engine, SpeechModelEngine.whisper);
    expect(small.group, SpeechModelGroup.local);
    expect(small.sizeLabel, _small.sizeLabel);
    expect(small.displayName(l10n), 'Whisper · ${_small.label}');

    final parakeet = entries.firstWhere(
      (e) => e.engine == SpeechModelEngine.parakeet,
    );
    expect(parakeet.group, SpeechModelGroup.local);
  });

  test('state: the entry in use is active, others ready or not downloaded', () {
    final entries = _entries(downloaded: {_small.id, _medium.id});
    expect(
      entries.firstWhere((e) => e.modelId == _small.id).state,
      isA<SpeechModelActive>(),
    );
    expect(
      entries.firstWhere((e) => e.modelId == _medium.id).state,
      isA<SpeechModelReady>(),
    );
    final notDownloaded = _entries().firstWhere((e) => e.modelId == _medium.id);
    expect(notDownloaded.state, isA<SpeechModelNotDownloaded>());
  });

  test('state: a running download reports its percent', () {
    final entries = _entries(
      downloads: ModelDownloadState(
        phase: DownloadPhase.downloading,
        activeModelId: _medium.id,
        progressPercent: 42,
      ),
    );
    final state = entries.firstWhere((e) => e.modelId == _medium.id).state;
    expect(state, isA<SpeechModelDownloading>());
    expect((state as SpeechModelDownloading).percent, 42);
  });

  test('state: loading wins over active while the engine starts', () {
    final entries = _entries(downloaded: {_small.id}, loading: _small.id);
    expect(
      entries.firstWhere((e) => e.modelId == _small.id).state,
      isA<SpeechModelLoading>(),
    );
  });

  test('cloud providers appear only with a key or while in use', () {
    expect(_entries().where((e) => e.group == SpeechModelGroup.cloud), isEmpty);
    final inUse = _entries(
      settings: _settings(provider: SttProviderType.openAI.value),
    ).where((e) => e.group == SpeechModelGroup.cloud);
    expect(inUse.single.choiceValue, SttProviderType.openAI.name);
    expect(inUse.single.state, isA<SpeechModelActive>());
  });

  test('the dock choices are the installed entries, in order '
      '(UIA-DOCK-02)', () {
    final entries = _entries(
      settings: _settings(openAiKey: 'k'),
      downloaded: {_small.id},
    );
    final choices = sttChoicesFrom(entries, l10n);
    expect(choices.map((c) => c.value), [
      'whisper:${_small.id}',
      OnDeviceEngine.parakeet.value,
      SttProviderType.openAI.name,
    ]);
  });

  test(
    'an extra entry from the provider shows in the dock without dock code',
    () {
      const extra = SelectableSpeechModel(
        engine: SpeechModelEngine.whisper,
        modelId: 'whisper-extra',
        sizeLabel: '1 MB',
        group: SpeechModelGroup.local,
        state: SpeechModelReady(),
        displayName: _extraName,
      );
      final container = ProviderContainer(
        overrides: [
          selectableSpeechModelsProvider.overrideWithValue([
            ..._entries(downloaded: {_small.id}),
            extra,
          ]),
        ],
      );
      addTearDown(container.dispose);

      final choices = sttChoicesFrom(
        container.read(selectableSpeechModelsProvider),
        l10n,
      );
      final added = choices.singleWhere(
        (c) => c.value == 'whisper:whisper-extra',
      );
      expect(added.label, 'Extra model');
      expect(added.onDevice, isTrue);
    },
  );

  test('Parakeet reports its bundle: not downloaded, downloading, then ready '
      '(UIA-DOCK-02)', () {
    SpeechModelState parakeetState(ParakeetDownloadState state) => _entries(
      parakeet: state,
    ).singleWhere((e) => e.engine == SpeechModelEngine.parakeet).state;

    expect(
      parakeetState(const ParakeetDownloadState()),
      isA<SpeechModelNotDownloaded>(),
    );
    final downloading = parakeetState(
      const ParakeetDownloadState(
        phase: ParakeetDownloadPhase.downloading,
        progressPercent: 40,
      ),
    );
    expect(downloading, isA<SpeechModelDownloading>());
    expect((downloading as SpeechModelDownloading).percent, 40);
    expect(
      parakeetState(const ParakeetDownloadState(installed: true)),
      isA<SpeechModelReady>(),
    );
    expect(
      parakeetState(
        const ParakeetDownloadState(phase: ParakeetDownloadPhase.done),
      ),
      isA<SpeechModelReady>(),
    );
  });

  // UIA-MDL-GATE b: one source for "the selected speech model is not there",
  // for Whisper and Parakeet alike, read by the dock and the hotkey notice.
  group('missingSelectedSpeechModel (UIA-MDL-GATE b)', () {
    test('a Whisper model that is not on disk is missing', () {
      final settings = _settings(model: _small.id);
      final missing = missingSelectedSpeechModel(
        settings,
        _entries(settings: settings),
      );
      expect(missing?.modelId, _small.id);
      expect(
        missing?.downloadChoiceValue,
        '$kSttDownloadChoicePrefix${_small.id}',
      );
    });

    test('an installed Whisper model is not missing', () {
      final settings = _settings(model: _small.id);
      expect(
        missingSelectedSpeechModel(
          settings,
          _entries(settings: settings, downloaded: {_small.id}),
        ),
        isNull,
      );
    });

    test('a downloading Whisper model is not missing', () {
      final settings = _settings(model: _small.id);
      expect(
        missingSelectedSpeechModel(
          settings,
          _entries(
            settings: settings,
            downloads: ModelDownloadState(
              phase: DownloadPhase.downloading,
              activeModelId: _small.id,
              scanned: true,
            ),
          ),
        ),
        isNull,
      );
    });

    test('Parakeet without its bundle is missing, with a size and a '
        'download value of its own', () {
      final settings = _settings().copyWith(
        sttEngine: OnDeviceEngine.parakeet.value,
      );
      final missing = missingSelectedSpeechModel(
        settings,
        _entries(settings: settings, parakeet: const ParakeetDownloadState()),
      );
      expect(missing?.engine, SpeechModelEngine.parakeet);
      expect(missing?.sizeLabel, isNotEmpty);
      expect(
        missing?.downloadChoiceValue,
        '$kSttDownloadChoicePrefix${OnDeviceEngine.parakeet.value}',
      );
    });

    test('Parakeet with its bundle is not missing', () {
      final settings = _settings().copyWith(
        sttEngine: OnDeviceEngine.parakeet.value,
      );
      expect(
        missingSelectedSpeechModel(settings, _entries(settings: settings)),
        isNull,
      );
    });

    test('a cloud provider is never a missing model', () {
      final settings = _settings(
        openAiKey: 'k',
        provider: SttProviderType.openAI.value,
      );
      expect(
        missingSelectedSpeechModel(settings, _entries(settings: settings)),
        isNull,
      );
    });
  });
}

String _extraName(L10n _) => 'Extra model';
