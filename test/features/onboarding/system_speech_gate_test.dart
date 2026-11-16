// The model gate (UIA-MDL-GATE) with the system speech engine chosen: it
// needs no app model, only the system language assets, and Next waits until
// they are in place (#1079).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/stt_model_readiness.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/system_speech/system_speech_status.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._value);

  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

class _NoWhisperDownload extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

class _NoParakeetDownload extends ParakeetDownloadNotifier {
  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();
}

class _System extends SystemSpeechNotifier {
  _System(this._initial);

  final SystemSpeechStatus _initial;

  @override
  SystemSpeechStatus build() => _initial;

  @override
  Future<void> refresh() async {}

  void finish() =>
      state = state.copyWith(installing: false, installed: true, fraction: 1);
}

const _checked = SystemSpeechStatus(
  osSupported: true,
  checked: true,
  localeSupported: 'en-US',
);

Future<ProviderContainer> _container({
  required AppSettings settings,
  required bool supported,
  required _System system,
  bool otherEngineReady = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _Settings(settings)),
      modelDownloadProvider.overrideWith(() => _NoWhisperDownload()),
      parakeetDownloadProvider.overrideWith(() => _NoParakeetDownload()),
      systemSpeechSupportedProvider.overrideWithValue(supported),
      systemSpeechProvider.overrideWith(() => system),
      if (otherEngineReady)
        onboardingCloudSttKeyProvider.overrideWithValue(true),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.future);
  return container;
}

void main() {
  final systemChosen = AppSettings.defaults.copyWith(sttEngine: 'system');

  test('the chosen system engine opens the gate only once installed', () async {
    final system = _System(_checked.copyWith(installing: true, fraction: 0.5));
    final container = await _container(
      settings: systemChosen,
      supported: true,
      system: system,
    );
    final sub = container.listen(
      onboardingModelStepCanAdvanceProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    expect(sub.read(), isFalse);
    system.finish();
    expect(container.read(onboardingModelStepCanAdvanceProvider), isTrue);
  });

  test('installed system assets do not open the gate for Whisper', () async {
    final container = await _container(
      settings: AppSettings.defaults,
      supported: true,
      system: _System(_checked.copyWith(installed: true)),
    );
    expect(container.read(onboardingModelStepCanAdvanceProvider), isFalse);
  });

  test('loading system assets hold the gate although another engine is '
      'ready', () async {
    final system = _System(_checked.copyWith(installing: true, fraction: 0.4));
    final container = await _container(
      settings: AppSettings.defaults,
      supported: true,
      system: system,
      otherEngineReady: true,
    );
    final sub = container.listen(
      onboardingModelStepCanAdvanceProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    expect(sub.read(), isFalse);
    system.finish();
    expect(sub.read(), isTrue);
  });

  test('a stored system choice on an OS without it falls back', () async {
    final container = await _container(
      settings: systemChosen,
      supported: false,
      system: _System(_checked.copyWith(installed: true)),
    );
    expect(container.read(onboardingSystemSpeechChosenProvider), isFalse);
    expect(container.read(onboardingModelStepCanAdvanceProvider), isFalse);
  });
}
