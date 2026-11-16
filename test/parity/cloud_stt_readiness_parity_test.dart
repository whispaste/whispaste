// The speech-model gate of the onboarding (UIA-MDL-GATE) must answer the same
// on macOS, Windows and Linux. The only platform-dependent input is the
// Linux keyring: a locked keyring leaves the API keys unread, and then no
// cloud provider counts as set up.
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/stt_model_readiness.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

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

/// Whether the onboarding's model gate lets the user on, for [settings] and
/// no model or download on disk.
Future<bool> _gateOpen(AppSettings settings) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _Settings(settings)),
      modelDownloadProvider.overrideWith(() => _NoWhisperDownload()),
      parakeetDownloadProvider.overrideWith(() => _NoParakeetDownload()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.future);
  return container.read(onboardingModelStepCanAdvanceProvider);
}

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    group('onboarding model gate on ${platform.name} (UIA-MDL-GATE)', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('OpenAI chosen with its key opens the gate', () async {
        expect(
          await _gateOpen(
            AppSettings.defaults.copyWith(
              sttProvider: SttProviderType.openAI.value,
              openAiApiKey: 'sk-test-key',
            ),
          ),
          isTrue,
        );
      });

      test('Deepgram chosen with its key opens the gate', () async {
        expect(
          await _gateOpen(
            AppSettings.defaults.copyWith(
              sttProvider: SttProviderType.deepgram.value,
              deepgramApiKey: 'dg-test-key',
            ),
          ),
          isTrue,
        );
      });

      // G1a: only the chosen provider counts.
      test(
        'a key with the local engine chosen keeps the gate closed',
        () async {
          expect(
            await _gateOpen(
              AppSettings.defaults.copyWith(openAiApiKey: 'sk-test-key'),
            ),
            isFalse,
          );
        },
      );

      test('a key for another cloud provider keeps the gate closed', () async {
        expect(
          await _gateOpen(
            AppSettings.defaults.copyWith(
              sttProvider: SttProviderType.deepgram.value,
              openAiApiKey: 'sk-test-key',
            ),
          ),
          isFalse,
        );
      });

      test('no key and no model keep the gate closed', () async {
        expect(await _gateOpen(AppSettings.defaults), isFalse);
      });
    });
  }

  group('onboarding model gate on linux keyring (UIA-MDL-GATE)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'a locked keyring leaves the key unread and the gate closed',
      () async {
        final store = SecureKeyStore(
          null,
          () async => KeyringAvailability.locked,
        );
        await expectLater(
          store.readAllApiKeys(),
          throwsA(isA<PlatformException>()),
        );
        expect(await _gateOpen(AppSettings.defaults), isFalse);
      },
    );
  });
}
