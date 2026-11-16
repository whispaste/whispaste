/// The Apple speech entry in the speech model list: shown only where the OS
/// runs it, and selected through its own engine value.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/system_speech/system_speech_status.dart';

AppSettings _settingsFor(OnDeviceEngine engine) =>
    AppSettings.defaults.copyWith(
      sttProvider: SttProviderType.onDevice.value,
      sttEngine: engine.value,
    );

List<SelectableSpeechModel> _entries({
  SystemSpeechStatus? system,
  OnDeviceEngine engine = OnDeviceEngine.whisper,
  List<SttModelInfo> models = const [],
  Set<String> downloaded = const {},
}) => selectableSpeechModels(
  settings: _settingsFor(engine),
  downloads: ModelDownloadState(downloadedModels: downloaded, scanned: true),
  parakeet: const ParakeetDownloadState(),
  models: models,
  system: system,
);

void main() {
  test('the Apple entry is absent where the OS cannot run it', () {
    final entries = _entries(
      system: const SystemSpeechStatus(osSupported: false),
    );

    expect(entries.where((e) => e.engine == SpeechModelEngine.system), isEmpty);
  });

  test('the Apple entry is listed and installed when the asset is there', () {
    final entries = _entries(
      system: const SystemSpeechStatus(osSupported: true, installed: true),
    );
    final apple = entries.singleWhere(
      (e) => e.engine == SpeechModelEngine.system,
    );

    expect(apple.isInstalled, isTrue);
    expect(apple.choiceValue, OnDeviceEngine.system.value);
  });

  test('the Apple entry is marked active while it is the engine in use', () {
    final entries = _entries(
      system: const SystemSpeechStatus(osSupported: true, installed: true),
      engine: OnDeviceEngine.system,
    );
    final apple = entries.singleWhere(
      (e) => e.engine == SpeechModelEngine.system,
    );

    expect(apple.state, isA<SpeechModelActive>());
  });

  test('a missing asset is not offered in the dock', () {
    final entries = _entries(
      system: const SystemSpeechStatus(osSupported: true),
    );
    final apple = entries.singleWhere(
      (e) => e.engine == SpeechModelEngine.system,
    );

    expect(apple.isInstalled, isFalse);
  });

  test('a language the system cannot take is unavailable, not offered', () {
    final entries = _entries(
      system: const SystemSpeechStatus(osSupported: true, checked: true),
    );
    final apple = entries.singleWhere(
      (e) => e.engine == SpeechModelEngine.system,
    );

    expect(apple.state, isA<SpeechModelUnavailable>());
    expect(apple.isInstalled, isFalse);
  });

  group('with the Apple engine selected', () {
    final settings = _settingsFor(OnDeviceEngine.system);
    final whisper = sttModels.first;
    const system = SystemSpeechStatus(osSupported: true, installed: true);

    test('the current choice is the Apple engine, not a Whisper model', () {
      expect(sttChoiceValue(settings), OnDeviceEngine.system.value);
    });

    test('an installed Whisper model is not marked active', () {
      final entries = _entries(
        system: system,
        engine: OnDeviceEngine.system,
        models: [whisper],
        downloaded: {whisper.id},
      );
      final active = entries.where((e) => e.state is SpeechModelActive);

      expect(active.map((e) => e.engine), [SpeechModelEngine.system]);
    });

    test('a Whisper model not on disk is not offered as missing', () {
      final entries = _entries(
        system: const SystemSpeechStatus(osSupported: true),
        engine: OnDeviceEngine.system,
        models: [whisper],
      );

      expect(missingSelectedSpeechModel(settings, entries), isNull);
    });
  });
}
