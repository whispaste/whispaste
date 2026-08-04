/// Widget tests for [ModelStep].
///
/// Verifies the two-way engine choice: card selection, the
/// language-and-hardware-driven recommendation (via [recommendEngine]),
/// per-engine download wiring, and the persistence contract: `sttEngine`/
/// `sttModel` persist exactly when the selected engine's model is confirmed
/// on disk (already-installed recommendation, completed download, or a
/// switch to an installed engine) — navigation is owned by the onboarding
/// shell and never gated here.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

class _RecordingWhisperDownloadNotifier extends ModelDownloadNotifier {
  _RecordingWhisperDownloadNotifier(this._initial);

  final ModelDownloadState _initial;
  final List<String> downloadModelCalls = [];

  @override
  ModelDownloadState build() => _initial;

  @override
  Future<void> downloadModel(String modelId) async {
    downloadModelCalls.add(modelId);
    state = state.copyWith(
      activeModelId: modelId,
      phase: DownloadPhase.downloading,
      progressPercent: 0,
    );
  }

  /// Simulates the in-flight download finishing successfully.
  void completeDownload() {
    state = state.copyWith(
      phase: DownloadPhase.done,
      progressPercent: 100,
      downloadedModels: {
        ...state.downloadedModels,
        if (state.activeModelId != null) state.activeModelId!,
      },
    );
  }
}

class _RecordingParakeetDownloadNotifier extends ParakeetDownloadNotifier {
  _RecordingParakeetDownloadNotifier(this._initial);

  final ParakeetDownloadState _initial;
  int downloadBundleCalls = 0;

  @override
  ParakeetDownloadState build() => _initial;

  @override
  Future<void> downloadBundle() async {
    downloadBundleCalls++;
    state = state.copyWith(phase: ParakeetDownloadPhase.downloading);
  }
}

late L10n l10n;

typedef _Recorders = ({
  _FakeSettingsNotifier settings,
  _RecordingWhisperDownloadNotifier whisper,
  _RecordingParakeetDownloadNotifier parakeet,
});

Future<_Recorders> _pumpStep(
  WidgetTester tester, {
  required hw.GpuInfo gpu,
  String dictationLocale = 'en',
  ModelDownloadState whisperInitial = const ModelDownloadState(),
  ParakeetDownloadState parakeetInitial = const ParakeetDownloadState(),
  Locale displayLocale = const Locale('en'),
}) async {
  late _RecordingWhisperDownloadNotifier whisper;
  late _RecordingParakeetDownloadNotifier parakeet;
  final settings = _FakeSettingsNotifier(
    AppSettings(interface_: InterfaceSettings(locale: dictationLocale)),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        hw.gpuInfoProvider.overrideWith((_) async => gpu),
        settingsProvider.overrideWith(() => settings),
        modelDownloadProvider.overrideWith(() {
          whisper = _RecordingWhisperDownloadNotifier(whisperInitial);
          return whisper;
        }),
        parakeetDownloadProvider.overrideWith(() {
          parakeet = _RecordingParakeetDownloadNotifier(parakeetInitial);
          return parakeet;
        }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wpDarkTheme(),
        locale: displayLocale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1280, 1600)),
          child: Scaffold(body: SingleChildScrollView(child: ModelStep())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (settings: settings, whisper: whisper, parakeet: parakeet);
}

const _appleM2 = hw.GpuInfo(
  vendor: hw.GpuVendor.apple,
  name: 'Apple M2',
  vramMB: 8192,
);
const _cpuOnly = hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU only');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('ModelStep — rendering', () {
    testWidgets('renders both engine cards once hardware is detected', (
      tester,
    ) async {
      await _pumpStep(tester, gpu: _appleM2);

      expect(tester.takeException(), isNull);
      expect(find.byKey(kModelStepEngineParakeetCardKey), findsOneWidget);
      expect(find.byKey(kModelStepEngineWhisperCardKey), findsOneWidget);
    });

    testWidgets('GpuVendor.none renders the CPU-fallback notice', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        gpu: _cpuOnly,
        // 'he' forces the Whisper recommendation so `whisperInitial` below
        // is actually the engine `isDone` checks — 'en' (the default) would
        // recommend Parakeet regardless of GPU (language decides, not
        // hardware), leaving the Whisper download state irrelevant.
        dictationLocale: 'he',
        whisperInitial: const ModelDownloadState(
          downloadedModels: {'whisper-small'},
          phase: DownloadPhase.done,
        ),
      );

      expect(find.byKey(kModelStepGpuCpuFallbackKey), findsOneWidget);
      // The ready state renders regardless of GPU detection outcome.
      expect(find.text(l10n.modelReady), findsOneWidget);
    });

    testWidgets('GpuVendor.apple does NOT render the CPU-fallback notice', (
      tester,
    ) async {
      await _pumpStep(tester, gpu: _appleM2);

      expect(find.byKey(kModelStepGpuCpuFallbackKey), findsNothing);
    });
  });

  group('ModelStep — recommendation', () {
    testWidgets('European dictation language (de) recommends Parakeet; the '
        'already-installed bundle is reflected as ready immediately', (
      tester,
    ) async {
      final rec = await _pumpStep(
        tester,
        gpu: _cpuOnly,
        dictationLocale: 'de',
        parakeetInitial: const ParakeetDownloadState(
          installed: true,
          phase: ParakeetDownloadPhase.done,
        ),
      );

      expect(
        find.text(l10n.modelReady),
        findsOneWidget,
        reason:
            'Parakeet is recommended (and preselected) for German — the '
            'ready state must reflect the already-installed bundle '
            'immediately, no tap needed.',
      );
      expect(rec.whisper.downloadModelCalls, isEmpty);
    });

    testWidgets(
      'Non-European dictation language (he) recommends Whisper; Parakeet '
      'card is disabled, shows the unsupported-language note, and tapping '
      'it is a no-op',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'he',
        );

        expect(
          find.text(l10n.onboardingModelEngineUnsupportedLanguage),
          findsOneWidget,
        );

        // Tapping the disabled Parakeet card must not select it — the CTA
        // stays wired to Whisper. Downloading confirms which engine is
        // actually selected.
        await tester.tap(find.byKey(kModelStepEngineParakeetCardKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(l10n.qualityTierDownloadAndContinue),
        );
        await tester.pumpAndSettle();

        expect(
          rec.parakeet.downloadBundleCalls,
          0,
          reason:
              'Tapping a disabled card must be a no-op — CTA stays on '
              'Whisper',
        );
        expect(rec.whisper.downloadModelCalls, isNotEmpty);
      },
    );
  });

  group('ModelStep — Whisper download path', () {
    testWidgets(
      'selecting Whisper and tapping download calls modelDownloadProvider '
      'with the hardware-recommended tier model',
      (tester) async {
        // 'he' forces the Whisper recommendation regardless of GPU, keeping
        // this test independent from the recommendation test above.
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'he',
        );

        await tester.tap(
          find.textContaining(l10n.qualityTierDownloadAndContinue),
        );
        await tester.pumpAndSettle();

        expect(rec.whisper.downloadModelCalls, [
          bestModelForTier(QualityTier.premium).id,
        ]);
        expect(rec.parakeet.downloadBundleCalls, 0);
      },
    );
  });

  group('ModelStep — Parakeet download path', () {
    testWidgets(
      'selecting Parakeet (recommended for German) and tapping download '
      'calls parakeetDownloadProvider.downloadBundle',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _cpuOnly,
          dictationLocale: 'de',
        );

        await tester.tap(
          find.textContaining(l10n.qualityTierDownloadAndContinue),
        );
        await tester.pumpAndSettle();

        expect(rec.parakeet.downloadBundleCalls, 1);
        expect(rec.whisper.downloadModelCalls, isEmpty);
      },
    );

    testWidgets(
      'switching from the recommended Parakeet to Whisper downloads Whisper '
      'instead',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'de',
        );

        await tester.tap(find.byKey(kModelStepEngineWhisperCardKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(l10n.qualityTierDownloadAndContinue),
        );
        await tester.pumpAndSettle();

        expect(rec.parakeet.downloadBundleCalls, 0);
        expect(rec.whisper.downloadModelCalls, [
          bestModelForTier(QualityTier.premium).id,
        ]);
      },
    );
  });

  group('ModelStep — persistence when the selected engine is on disk', () {
    testWidgets(
      'already-installed recommended Parakeet persists sttEngine=parakeet '
      'on mount, leaves sttModel untouched',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _cpuOnly,
          dictationLocale: 'de',
          parakeetInitial: const ParakeetDownloadState(
            installed: true,
            phase: ParakeetDownloadPhase.done,
          ),
        );

        expect(rec.settings.state.value!.stt.engine, 'parakeet');
        expect(
          rec.settings.state.value!.sttModel,
          AppSettings.defaults.sttModel,
          reason: 'Parakeet selection must not touch the whisper model id',
        );
      },
    );

    testWidgets('already-downloaded Whisper persists sttEngine=whisper and the '
        'resolved tier model on mount', (tester) async {
      final rec = await _pumpStep(
        tester,
        gpu: _appleM2,
        dictationLocale: 'he',
        whisperInitial: const ModelDownloadState(
          downloadedModels: {'whisper-large-v3-turbo'},
          phase: DownloadPhase.done,
        ),
      );

      expect(rec.settings.state.value!.stt.engine, 'whisper');
      expect(
        rec.settings.state.value!.sttModel,
        bestModelForTier(QualityTier.premium).id,
      );
    });

    testWidgets(
      'a download completing mid-page persists the engine without any '
      'further tap (the shell-owned Next must not need to know engines)',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'he',
        );
        final originalEngine = rec.settings.state.value!.stt.engine;

        await tester.tap(
          find.textContaining(l10n.qualityTierDownloadAndContinue),
        );
        await tester.pumpAndSettle();
        // Still downloading — nothing persisted yet.
        expect(rec.settings.state.value!.stt.engine, originalEngine);

        rec.whisper.completeDownload();
        await tester.pumpAndSettle();

        expect(rec.settings.state.value!.stt.engine, 'whisper');
        expect(
          rec.settings.state.value!.sttModel,
          bestModelForTier(QualityTier.premium).id,
        );
      },
    );

    testWidgets(
      'without any download nothing is written — a user who continues '
      'without downloading (e.g. to use a cloud provider) keeps the '
      'defaults untouched',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'de',
        );

        expect(
          rec.settings.state.value!.stt.engine,
          AppSettings.defaults.stt.engine,
        );
        expect(rec.whisper.downloadModelCalls, isEmpty);
        expect(rec.parakeet.downloadBundleCalls, 0);
      },
    );
  });
}
