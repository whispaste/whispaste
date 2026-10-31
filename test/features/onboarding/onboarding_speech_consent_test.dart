/// Guards for the start page's consent (Onboarding v6, V02, S6): the speech
/// model download starts only after the consent, at most once, and never over
/// a declined disk-space warning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/onboarding_speech_consent.dart';
import 'package:whispaste/services/free_disk_space.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

import '../../fixtures/test_helpers.dart';

/// Records the Whisper downloads asked for. Never fetches.
class _RecordingDownload extends ModelDownloadNotifier {
  _RecordingDownload(this.started, {this.downloaded = const {}});

  final List<String> started;
  final Set<String> downloaded;

  @override
  ModelDownloadState build() =>
      ModelDownloadState(downloadedModels: downloaded);

  @override
  Future<void> downloadModel(String modelId) async {
    started.add(modelId);
    state = state.copyWith(
      phase: DownloadPhase.downloading,
      activeModelId: modelId,
    );
  }
}

/// Records the Parakeet bundle downloads asked for. Never fetches.
class _RecordingParakeet extends ParakeetDownloadNotifier {
  _RecordingParakeet(this.bundleStarts);

  final List<int> bundleStarts;

  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();

  @override
  Future<void> downloadBundle() async {
    bundleStarts.add(bundleStarts.length + 1);
    state = state.copyWith(phase: ParakeetDownloadPhase.downloading);
  }
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

const _offer = WelcomeSpeechOffer(
  engine: OnDeviceEngine.whisper,
  whisperModelId: 'whisper-medium',
  sizeBytes: 1536 * 1024 * 1024,
);

const _consentKey = Key('consent-button');

/// Stands in for the start page's "Einrichten" action.
class _ConsentButton extends ConsumerWidget {
  const _ConsentButton({
    required this.settingsAlreadySet,
    required this.onResult,
  });

  final bool settingsAlreadySet;
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      key: _consentKey,
      onPressed: () async {
        final proceed = await startWelcomeSpeechDownload(
          context: context,
          ref: ref,
          settingsAlreadySet: settingsAlreadySet,
        );
        onResult(proceed);
      },
      child: const Text('consent'),
    );
  }
}

late L10n l10n;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    await loadAppFonts();
  });

  Future<void> pumpConsent(
    WidgetTester tester, {
    required List<String> started,
    required _FakeSettingsNotifier settings,
    required List<bool> results,
    bool settingsAlreadySet = false,
    Set<String> downloaded = const {},
    int freeBytes = 500 * 1024 * 1024 * 1024,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: _ConsentButton(
            settingsAlreadySet: settingsAlreadySet,
            onResult: results.add,
          ),
        ),
        overrides: [
          settingsProvider.overrideWith(() => settings),
          modelDownloadProvider.overrideWith(
            () => _RecordingDownload(started, downloaded: downloaded),
          ),
          welcomeSpeechOfferProvider.overrideWith((ref) async => _offer),
          freeDiskSpaceProbeProvider.overrideWithValue((_) async => freeBytes),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  group('startWelcomeSpeechDownload (start page consent)', () {
    testWidgets('no download without the consent', (tester) async {
      final started = <String>[];
      await pumpConsent(
        tester,
        started: started,
        settings: _FakeSettingsNotifier(AppSettings.defaults),
        results: [],
      );

      expect(started, isEmpty);
    });

    testWidgets('repeated consents start the recommended model exactly once', (
      tester,
    ) async {
      final started = <String>[];
      final results = <bool>[];
      await pumpConsent(
        tester,
        started: started,
        settings: _FakeSettingsNotifier(AppSettings.defaults),
        results: results,
      );

      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();

      expect(started, ['whisper-medium']);
      expect(results, [true, true]);
    });

    testWidgets('first start saves the recommendation before downloading it', (
      tester,
    ) async {
      final started = <String>[];
      final settings = _FakeSettingsNotifier(
        AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
      );
      await pumpConsent(
        tester,
        started: started,
        settings: settings,
        results: [],
      );

      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();

      expect(settings.state.value!.stt.model, 'whisper-medium');
      expect(started, ['whisper-medium']);
    });

    testWidgets('after the other-model page, the saved choice is downloaded '
        'instead of the recommendation', (tester) async {
      final started = <String>[];
      await pumpConsent(
        tester,
        started: started,
        settings: _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        ),
        results: [],
        settingsAlreadySet: true,
      );

      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();

      expect(started, ['whisper-small']);
    });

    testWidgets('a model already on disk starts nothing', (tester) async {
      final started = <String>[];
      await pumpConsent(
        tester,
        started: started,
        settings: _FakeSettingsNotifier(AppSettings.defaults),
        results: [],
        downloaded: const {'whisper-medium'},
      );

      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();

      expect(started, isEmpty);
    });

    testWidgets('declining the disk-space warning starts nothing and keeps '
        'the user on the start page', (tester) async {
      final started = <String>[];
      final results = <bool>[];
      await pumpConsent(
        tester,
        started: started,
        settings: _FakeSettingsNotifier(AppSettings.defaults),
        results: results,
        freeBytes: 1024,
      );

      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pumpAndSettle();

      expect(started, isEmpty);
      expect(results, [false]);
    });
  });

  group('start page consent on this machine (Parakeet recommendation)', () {
    testWidgets('Einrichten starts the Parakeet bundle download', (
      tester,
    ) async {
      final bundleStarts = <int>[];
      final settings = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: _ConsentButton(settingsAlreadySet: false, onResult: (_) {}),
          ),
          overrides: [
            settingsProvider.overrideWith(() => settings),
            modelDownloadProvider.overrideWith(() => _RecordingDownload([])),
            parakeetDownloadProvider.overrideWith(
              () => _RecordingParakeet(bundleStarts),
            ),
            welcomeSpeechOfferProvider.overrideWith(
              (ref) async => const WelcomeSpeechOffer(
                engine: OnDeviceEngine.parakeet,
                sizeBytes: 639 * 1024 * 1024,
              ),
            ),
            freeDiskSpaceProbeProvider.overrideWithValue(
              (_) async => 500 * 1024 * 1024 * 1024,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_consentKey));
      await tester.pumpAndSettle();

      expect(bundleStarts, hasLength(1));
      expect(settings.state.value!.stt.engine, OnDeviceEngine.parakeet.value);
    });
  });
}
