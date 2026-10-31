import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/features/onboarding/onboarding_download_provider.dart';
import 'package:whispaste/features/onboarding/onboarding_download_status.dart';
import 'package:whispaste/features/onboarding/stt_model_readiness.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

const _mb = 1000000;

class _FakeWhisper extends ModelDownloadNotifier {
  _FakeWhisper(this._initial);
  final ModelDownloadState _initial;

  @override
  ModelDownloadState build() => _initial;

  void emit(ModelDownloadState s) => state = s;
}

class _FakeParakeet extends ParakeetDownloadNotifier {
  _FakeParakeet(this._initial);
  final ParakeetDownloadState _initial;

  @override
  ParakeetDownloadState build() => _initial;

  void emit(ParakeetDownloadState s) => state = s;
}

void main() {
  late _FakeWhisper whisper;
  late _FakeParakeet parakeet;
  late ProviderContainer container;

  void setUpWith({
    OnDeviceEngine? engine = OnDeviceEngine.whisper,
    bool cloudKey = false,
    ModelDownloadState w = const ModelDownloadState(),
    ParakeetDownloadState p = const ParakeetDownloadState(),
  }) {
    whisper = _FakeWhisper(w);
    parakeet = _FakeParakeet(p);
    container = ProviderContainer(
      overrides: [
        modelDownloadProvider.overrideWith(() => whisper),
        parakeetDownloadProvider.overrideWith(() => parakeet),
        onboardingSelectedEngineProvider.overrideWithValue(engine),
        onboardingCloudSttKeyProvider.overrideWithValue(cloudKey),
      ],
    );
    addTearDown(container.dispose);
    // Build both notifiers so that emit() may set their state.
    container.read(modelDownloadProvider);
    container.read(parakeetDownloadProvider);
  }

  OnboardingDownloadStatus read() =>
      container.read(onboardingDownloadStatusProvider);

  test('nothing downloaded and nothing running is idle and locked', () {
    setUpWith();
    expect(read().phase, OnboardingDownloadPhase.idle);
    expect(read().practiceUnlocked, isFalse);
  });

  test('a running download keeps practice locked and reports bytes', () {
    setUpWith();
    whisper.emit(
      const ModelDownloadState(
        activeModelId: 'base',
        phase: DownloadPhase.downloading,
        bytesDownloaded: 25 * _mb,
        totalBytes: 100 * _mb,
      ),
    );
    final s = read();
    expect(s.phase, OnboardingDownloadPhase.running);
    expect(s.practiceUnlocked, isFalse);
    expect(s.fraction, closeTo(0.25, 1e-9));
    // Under the 3 s minimum span there is no estimate yet.
    expect(s.remaining, isNull);
  });

  test('a finished download unlocks practice', () {
    setUpWith();
    whisper.emit(
      const ModelDownloadState(
        phase: DownloadPhase.done,
        downloadedModels: {'base'},
      ),
    );
    expect(read().practiceUnlocked, isTrue);
  });

  test('a download of the other engine does not change the status', () {
    setUpWith(engine: OnDeviceEngine.parakeet);
    whisper.emit(
      const ModelDownloadState(
        phase: DownloadPhase.downloading,
        bytesDownloaded: 25 * _mb,
        totalBytes: 100 * _mb,
      ),
    );
    expect(read().phase, OnboardingDownloadPhase.idle);
    expect(read().practiceUnlocked, isFalse);
  });

  test('the selected parakeet engine reports its own error', () {
    setUpWith(
      engine: OnDeviceEngine.parakeet,
      p: const ParakeetDownloadState(
        phase: ParakeetDownloadPhase.error,
        bytesDownloaded: 10 * _mb,
        totalBytes: 50 * _mb,
      ),
    );
    final s = read();
    expect(s.phase, OnboardingDownloadPhase.failed);
    expect(s.practiceUnlocked, isFalse);
    expect(s.bytesDone, 10 * _mb);
  });

  test('a retry after a failure runs again and locks practice again', () {
    setUpWith(
      engine: OnDeviceEngine.parakeet,
      p: const ParakeetDownloadState(phase: ParakeetDownloadPhase.error),
    );
    expect(read().phase, OnboardingDownloadPhase.failed);
    parakeet.emit(
      const ParakeetDownloadState(
        phase: ParakeetDownloadPhase.downloading,
        bytesDownloaded: 0,
        totalBytes: 50 * _mb,
      ),
    );
    expect(read().phase, OnboardingDownloadPhase.running);
    expect(read().remaining, isNull);
  });

  test('a cloud provider with a saved key is ready without a download', () {
    setUpWith(engine: null, cloudKey: true);
    expect(read().practiceUnlocked, isTrue);
  });

  test('a cloud provider without a key is idle', () {
    setUpWith(engine: null);
    expect(read().phase, OnboardingDownloadPhase.idle);
  });
}
