import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

AppSettings _settings({
  String openAiKey = '',
  String deepgramKey = '',
  String model = 'whisper-small',
}) => AppSettings.defaults
    .copyWith(sttModel: model)
    .copyWithSections(
      cloudProvider: AppSettings.defaults.cloudProvider.copyWith(
        openAiApiKey: openAiKey,
        deepgramApiKey: deepgramKey,
      ),
    );

final _models = sttModels.take(2).toList();

/// The dock's choices built the way the dock builds them: the provider's
/// entries, mapped to choices.
List<SttChoice> _choices(
  AppSettings settings,
  L10n l10n, {
  required List<SttModelInfo> models,
  required Set<String> downloaded,
  String? loadingModelId,
  ParakeetDownloadState parakeet = const ParakeetDownloadState(),
  bool offerMissing = false,
}) {
  final entries = selectableSpeechModels(
    settings: settings,
    downloads: ModelDownloadState(downloadedModels: downloaded, scanned: true),
    parakeet: parakeet,
    models: models,
    loadingModelId: loadingModelId,
  );
  return sttChoicesFrom(
    entries,
    l10n,
    missing: offerMissing
        ? missingSelectedSpeechModel(settings, entries)
        : null,
  );
}

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final small = _models[0].id;
  final medium = _models[1].id;

  List<String> values(
    AppSettings settings, {
    Set<String> downloaded = const {},
    String? loading,
    ParakeetDownloadState parakeet = const ParakeetDownloadState(),
  }) => [
    for (final c in _choices(
      settings,
      l10n,
      models: _models,
      downloaded: downloaded,
      loadingModelId: loading,
      parakeet: parakeet,
    ))
      c.value,
  ];

  test('the current choice is the model on device, the provider in cloud', () {
    expect(sttChoiceValue(_settings(model: small)), 'whisper:$small');

    final parakeet = AppSettings.defaults.copyWith(
      sttProvider: SttProviderType.onDevice.value,
      sttEngine: OnDeviceEngine.parakeet.value,
    );
    expect(sttChoiceValue(parakeet), OnDeviceEngine.parakeet.value);

    final cloud = AppSettings.defaults.copyWith(
      sttProvider: SttProviderType.openAI.value,
    );
    expect(sttChoiceValue(cloud), SttProviderType.openAI.name);
  });

  test('the dock offers only installed models, downloads stay in Settings '
      '(UIA-DOCK-02)', () {
    final choices = _choices(
      _settings(),
      l10n,
      models: _models,
      downloaded: {small},
    );
    expect([for (final c in choices) c.value], ['whisper:$small']);
    expect(choices.single.label, 'Whisper · ${_models[0].label}');
  });

  test('the model being loaded is marked as loading', () {
    final choices = _choices(
      _settings(),
      l10n,
      models: _models,
      downloaded: {small, medium},
      loadingModelId: small,
    );
    expect(choices.first.label, 'Whisper · ${_models[0].label} · loading');
    expect(choices[1].label, 'Whisper · ${_models[1].label}');
  });

  test('Parakeet only once its bundle is installed, cloud only with a saved '
      'key (UIA-DOCK-02)', () {
    expect(values(_settings()), isEmpty);
    expect(
      values(
        _settings(),
        parakeet: const ParakeetDownloadState(
          phase: ParakeetDownloadPhase.downloading,
          progressPercent: 40,
        ),
      ),
      isEmpty,
    );
    expect(
      values(
        _settings(),
        parakeet: const ParakeetDownloadState(installed: true),
      ),
      [OnDeviceEngine.parakeet.value],
    );
    final withKey = values(_settings(deepgramKey: 'k'));
    expect(withKey, contains(SttProviderType.deepgram.name));
    expect(withKey, isNot(contains(SttProviderType.openAI.name)));
  });

  test('a cloud provider in use stays offered even without its key', () {
    final current = AppSettings.defaults.copyWith(
      sttProvider: SttProviderType.openAI.value,
    );
    expect(values(current), contains(SttProviderType.openAI.name));
  });

  test('applying a downloaded model selects the Whisper engine and model', () {
    final applied = applySttChoice(
      AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.deepgram.value,
      ),
      'whisper:$medium',
    );
    expect(applied.sttProviderType, SttProviderType.onDevice);
    expect(applied.onDeviceEngine, OnDeviceEngine.whisper);
    expect(applied.sttModel, medium);
  });

  test('a download choice never changes the settings', () {
    final base = _settings();
    expect(applySttChoice(base, 'download:$medium'), base);
  });

  test('applying Parakeet switches the provider back to on-device', () {
    final cloud = AppSettings.defaults.copyWith(
      sttProvider: SttProviderType.deepgram.value,
    );
    final applied = applySttChoice(cloud, OnDeviceEngine.parakeet.value);
    expect(applied.sttProviderType, SttProviderType.onDevice);
    expect(applied.onDeviceEngine, OnDeviceEngine.parakeet);
  });

  test('applying a cloud provider sets the provider', () {
    final applied = applySttChoice(
      AppSettings.defaults,
      SttProviderType.deepgram.name,
    );
    expect(applied.sttProviderType, SttProviderType.deepgram);
  });

  // UIA-MDL-GATE b: with the selected model missing, its download is the
  // first entry, for Whisper and Parakeet alike, in every app language.
  group('the missing selected model is offered for download', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(Locale(locale.languageCode));

      test('Whisper, ${locale.languageCode}', () {
        final choices = _choices(
          _settings(model: _models.first.id),
          l10n,
          models: _models,
          downloaded: const {},
          offerMissing: true,
        );
        expect(choices, hasLength(1));
        expect(
          choices.first.value,
          '$kSttDownloadChoicePrefix${_models.first.id}',
        );
        expect(choices.first.label, contains(_models.first.sizeLabel));
        expect(choices.first.label, isNot(contains('{')));
      });

      test('Parakeet, ${locale.languageCode}', () {
        final choices = _choices(
          _settings().copyWith(sttEngine: OnDeviceEngine.parakeet.value),
          l10n,
          models: _models,
          downloaded: {_models.first.id},
          offerMissing: true,
        );
        expect(
          choices.first.value,
          '$kSttDownloadChoicePrefix${OnDeviceEngine.parakeet.value}',
        );
        expect(choices.first.label, contains(l10n.settingsSttEngineParakeet));
        // The installed Whisper model stays selectable next to it.
        expect(
          choices.map((c) => c.value),
          contains('$kSttModelChoicePrefix${_models.first.id}'),
        );
      });
    }

    test('nothing to download once the selected model is there', () {
      final choices = _choices(
        _settings(model: _models.first.id),
        lookupL10n(const Locale('en')),
        models: _models,
        downloaded: {_models.first.id},
        offerMissing: true,
      );
      expect(
        choices.where((c) => c.value.startsWith(kSttDownloadChoicePrefix)),
        isEmpty,
      );
    });
  });

  // UIA-XP-7-04: switching to Whisper lands on a model that is on disk.
  group('applyEngineChoice', () {
    final parakeet = _settings(
      model: _models[1].id,
    ).copyWith(sttEngine: OnDeviceEngine.parakeet.value);

    test('a missing Whisper model gives way to an installed one', () {
      final next = applyEngineChoice(
        parakeet,
        OnDeviceEngine.whisper.value,
        downloaded: {_models[0].id},
        models: _models,
      );
      expect(next.onDeviceEngine, OnDeviceEngine.whisper);
      expect(next.effectiveModelId, _models[0].id);
    });

    test('an installed Whisper model is kept', () {
      final next = applyEngineChoice(
        parakeet,
        OnDeviceEngine.whisper.value,
        downloaded: {_models[0].id, _models[1].id},
        models: _models,
      );
      expect(next.effectiveModelId, _models[1].id);
    });

    test('with no Whisper model on disk the selection stays', () {
      final next = applyEngineChoice(
        parakeet,
        OnDeviceEngine.whisper.value,
        downloaded: const {},
        models: _models,
      );
      expect(next.onDeviceEngine, OnDeviceEngine.whisper);
      expect(next.effectiveModelId, _models[1].id);
    });

    test('switching to Parakeet leaves the Whisper model alone', () {
      final whisper = _settings(model: _models[1].id);
      final next = applyEngineChoice(
        whisper,
        OnDeviceEngine.parakeet.value,
        downloaded: {_models[0].id},
        models: _models,
      );
      expect(next.onDeviceEngine, OnDeviceEngine.parakeet);
      expect(next.effectiveModelId, _models[1].id);
    });
  });

  test('an unknown value leaves the settings unchanged', () {
    final base = AppSettings.defaults;
    expect(applySttChoice(base, 'nonsense'), base);
  });
}
