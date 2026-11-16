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

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/help/manual/user_manual_view.dart'
    show kManualSectionDialogKey;
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/services/connection_return_watcher.dart';
import 'package:whispaste/services/download_error_kind.dart';
import 'package:whispaste/services/free_disk_space.dart';
import 'package:whispaste/services/short_model_benchmark.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/speech_recommendation.dart'
    show RamMB, ramMBProvider, systemLanguageCodesProvider;
import 'package:whispaste/services/stt/backend_utilization_notifier.dart'
    show processorCountProvider;
import 'package:whispaste/services/stt/benchmark_freshness.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/system_speech/system_speech_status.dart';
import '../../fixtures/app_fonts.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  /// How often the step asked for a write at all. Ticket 05's "an untouched
  /// visit writes nothing" is about the *absence* of a write, which equal
  /// before/after values alone would not prove.
  int updateCalls = 0;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    updateCalls++;
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

  int cancelCalls = 0;

  @override
  void cancelDownload() {
    cancelCalls++;
    state = state.copyWith(
      phase: DownloadPhase.idle,
      activeModelId: null,
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

/// Simulates the deferred initial disk scan without touching real
/// `dart:io` — [build] starts in the pre-scan empty state, and
/// [awaitInitialScan] parks on [releaseScan] before revealing [scanResult],
/// exactly like the real notifier parks on its disk scan's completer. Lets
/// tests control the race between hardware detection and the scan directly,
/// via plain `Completer`-based futures (safe under `testWidgets`, unlike the
/// real notifier's `Directory`/`File` calls — see the "initial disk scan
/// race" group below).
class _RaceableWhisperDownloadNotifier extends ModelDownloadNotifier {
  _RaceableWhisperDownloadNotifier(this.scanResult);

  final ModelDownloadState scanResult;
  final _scanCompleter = Completer<void>();

  @override
  ModelDownloadState build() => const ModelDownloadState();

  @override
  Future<void> awaitInitialScan() async {
    await _scanCompleter.future;
    state = scanResult;
  }

  void releaseScan() {
    if (!_scanCompleter.isCompleted) _scanCompleter.complete();
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

  int cancelCalls = 0;

  @override
  void cancelDownload() {
    cancelCalls++;
    state = state.copyWith(
      phase: ParakeetDownloadPhase.idle,
      progressPercent: 0,
    );
  }
}

/// The system engine's status without the native channel: [build] answers a
/// fixed status, [install] counts and marks the assets as loading.
class _FakeSystemSpeechNotifier extends SystemSpeechNotifier {
  _FakeSystemSpeechNotifier(this._initial);

  final SystemSpeechStatus _initial;
  int installCalls = 0;

  @override
  SystemSpeechStatus build() => _initial;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> install() async {
    installCalls++;
    state = state.copyWith(installing: true, fraction: 0.4);
  }

  /// Simulates the system finishing the language assets.
  void completeInstall() {
    state = state.copyWith(installing: false, installed: true, fraction: 1);
  }
}

late L10n l10n;

typedef _Recorders = ({
  _FakeSettingsNotifier settings,
  _RecordingWhisperDownloadNotifier whisper,
  _RecordingParakeetDownloadNotifier parakeet,
  _FakeSystemSpeechNotifier system,
});

/// The machine's RAM, so the host running the test never decides it.
class _FixedRam extends RamMB {
  _FixedRam(this._mb);
  final int? _mb;

  @override
  int? build() => _mb;
}

Future<_Recorders> _pumpStep(
  WidgetTester tester, {
  required hw.GpuInfo gpu,
  String dictationLocale = 'en',

  /// Total RAM; null reads as "RAM unknown".
  int? ramMB = 16384,
  ModelDownloadState whisperInitial = const ModelDownloadState(),
  ParakeetDownloadState parakeetInitial = const ParakeetDownloadState(),
  Locale displayLocale = const Locale('en'),

  /// Pre-existing speech-recognition settings. Defaults to the factory
  /// values, which is what a first run has.
  SttSettings stt = const SttSettings(),

  /// Stored benchmark results; the step only uses the ones that describe this
  /// machine and build (UIA-RT-03).
  BenchmarkSettings benchmark = const BenchmarkSettings(),

  /// Whether the user already finished the first-run setup — the signal
  /// [ModelStep] treats as "everything in settings is this user's own
  /// choice" (Ticket 05).
  bool onboardingCompleted = false,

  /// Width the step is laid out at. `null` lets it take the whole test
  /// surface (1280 px), which is what most assertions here want. The
  /// truncation regression below needs the *real* onboarding page frame
  /// (720 px) instead: the engine cards only compete for width once each of
  /// them is ~344 px, and at 1280 the bug it guards is invisible.
  double? frameWidth,

  /// Replaces the immediate [gpu] answer, e.g. with a future that never
  /// completes to hold the step in hardware detection. The spinner then
  /// animates forever, so the pump does not settle.
  Future<hw.GpuInfo>? gpuFuture,

  /// What the free-disk-space probe answers; `null` is "unknown", which the
  /// step treats as enough (fail-open, UIA-ONB-09).
  int? freeDiskBytes,

  /// What the connection-back probe answers; offline by default, so no test
  /// reaches the network.
  ConnectionProbe? connectionProbe,

  /// Whether the OS offers the system engine; off by default, so the host the
  /// suite runs on never adds the third card.
  bool systemSupported = false,

  /// The system engine's status while [systemSupported] is on.
  SystemSpeechStatus? systemInitial,

  /// Pins a short-benchmark result so the step does not download
  /// whisper-small to measure; for tests that count the user's own downloads.
  bool skipShortBenchmark = false,
}) async {
  final system = _FakeSystemSpeechNotifier(
    systemInitial ?? SystemSpeechStatus(osSupported: systemSupported),
  );
  late _RecordingWhisperDownloadNotifier whisper;
  late _RecordingParakeetDownloadNotifier parakeet;
  final settings = _FakeSettingsNotifier(
    AppSettings(
      interface_: InterfaceSettings(locale: dictationLocale),
      stt: stt,
      benchmark: benchmark,
      onboarding: OnboardingSettings(onboardingCompleted: onboardingCompleted),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        hw.gpuInfoProvider.overrideWith((_) => gpuFuture ?? Future.value(gpu)),
        // The recommendation also weighs the system languages and the CPU;
        // pin both so the host the suite runs on never decides it.
        systemLanguageCodesProvider.overrideWithValue([dictationLocale]),
        processorCountProvider.overrideWithValue(8),
        ramMBProvider.overrideWith(() => _FixedRam(ramMB)),
        freeDiskSpaceProbeProvider.overrideWithValue(
          (_) async => freeDiskBytes,
        ),
        connectionProbeProvider.overrideWithValue(
          connectionProbe ?? () async => false,
        ),
        settingsProvider.overrideWith(() => settings),
        modelDownloadProvider.overrideWith(() {
          whisper = _RecordingWhisperDownloadNotifier(whisperInitial);
          return whisper;
        }),
        parakeetDownloadProvider.overrideWith(() {
          parakeet = _RecordingParakeetDownloadNotifier(parakeetInitial);
          return parakeet;
        }),
        systemSpeechSupportedProvider.overrideWithValue(systemSupported),
        systemSpeechProvider.overrideWith(() => system),
        // Without a result the step downloads whisper-small by itself to
        // measure, which tests of the user's own download taps must not count.
        if (skipShortBenchmark)
          shortModelBenchmarkRtfProvider.overrideWith(_PinnedBenchmarkRtf.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wpDarkTheme(),
        locale: displayLocale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 1600)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(width: frameWidth, child: const ModelStep()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (gpuFuture == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return (
    settings: settings,
    whisper: whisper,
    parakeet: parakeet,
    system: system,
  );
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
    // Real Inter metrics, not the square-glyph test font: the truncation
    // regression below is a width measurement, and with Ahem every glyph is
    // a full em square — roughly double Inter's width — so every title would
    // "overflow" and the test would pass for a reason the app never has.
    await loadAppFontsOnce();
  });

  testWidgets('hardware detection says what it is doing (UIA-ONB-13)', (
    tester,
  ) async {
    await _pumpStep(
      tester,
      gpu: _appleM2,
      gpuFuture: Completer<hw.GpuInfo>().future,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // MV-03/04: the recommendation carries a one-line reason, the same text
  // Settings shows under its tiers for the same hardware.
  group('ModelStep — the recommendation names its reason (MV-03)', () {
    testWidgets('a CUDA GPU names the card and its video memory', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        dictationLocale: 'he',
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce RTX 3060',
          vramMB: 12288,
          cudaAvailable: true,
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(kModelStepRecommendationReasonKey)).data,
        l10n.recommendationReasonCuda('12'),
      );
    });

    testWidgets('llvmpipe is named as software graphics on the processor', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        dictationLocale: 'he',
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.none,
          name: 'llvmpipe (LLVM 15.0.7, 256 bits)',
        ),
        ramMB: null,
      );

      final reason = tester
          .widget<Text>(find.byKey(kModelStepRecommendationReasonKey))
          .data!;
      expect(reason, contains('llvmpipe'));
      expect(reason, contains(l10n.recommendationMemoryUnknown));
    });

    testWidgets('a language Parakeet covers names the language', (
      tester,
    ) async {
      await _pumpStep(tester, dictationLocale: 'de', gpu: _cpuOnly);

      expect(
        tester.widget<Text>(find.byKey(kModelStepRecommendationReasonKey)).data,
        l10n.recommendationReasonLanguage,
      );
    });
  });

  group('ModelStep — offline download error (#235)', () {
    const retryKey = ValueKey('onboarding-speech-retry');
    const manualKey = ValueKey('onboarding-speech-manual-install');

    Future<_Recorders> pumpWithError(
      WidgetTester tester,
      DownloadErrorKind kind, {
      ConnectionProbe? connectionProbe,
    }) => _pumpStep(
      tester,
      gpu: _appleM2,
      connectionProbe: connectionProbe,
      whisperInitial: ModelDownloadState(
        phase: DownloadPhase.error,
        errorMessage: 'SocketException',
        errorKind: kind,
      ),
      parakeetInitial: ParakeetDownloadState(
        phase: ParakeetDownloadPhase.error,
        errorMessage: 'SocketException',
        errorKind: kind,
      ),
    );

    testWidgets('offers retry and the manual install guide, which opens', (
      tester,
    ) async {
      await pumpWithError(tester, DownloadErrorKind.offline);

      expect(find.byKey(retryKey), findsOneWidget);
      expect(find.byKey(manualKey), findsOneWidget);
      expect(find.byKey(kManualSectionDialogKey), findsNothing);

      await tester.tap(find.byKey(manualKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kManualSectionDialogKey), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('manual-section-dialog-close')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(kManualSectionDialogKey), findsNothing);
    });

    testWidgets('a returned connection is announced, the download waits for '
        'retry', (tester) async {
      final rec = await pumpWithError(
        tester,
        DownloadErrorKind.offline,
        connectionProbe: () async => true,
      );
      const hintKey = ValueKey('onboarding-speech-connection-back');
      expect(find.byKey(hintKey), findsNothing);

      await tester.pump(kConnectionProbeInterval);
      await tester.pump();

      expect(find.byKey(hintKey), findsOneWidget);
      expect(find.byKey(retryKey), findsOneWidget);
      expect(rec.whisper.downloadModelCalls, isEmpty);
    });

    testWidgets('other failures keep retry only', (tester) async {
      await pumpWithError(tester, DownloadErrorKind.network);

      expect(find.byKey(retryKey), findsOneWidget);
      expect(find.byKey(manualKey), findsNothing);
    });
  });

  group('ModelStep — free disk space before the download (UIA-ONB-09)', () {
    for (final gpu in [_appleM2, _cpuOnly]) {
      testWidgets('too little space warns with needed/free and only starts '
          'on "Download anyway" (${gpu.name})', (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: gpu,
          skipShortBenchmark: true,
          freeDiskBytes: 1024,
        );
        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();

        expect(rec.whisper.downloadModelCalls, isEmpty);
        expect(rec.parakeet.downloadBundleCalls, 0);

        await tester.tap(find.bySemanticsIdentifier('confirm-dialog-confirm'));
        await tester.pumpAndSettle();
        expect(
          rec.whisper.downloadModelCalls.length +
              rec.parakeet.downloadBundleCalls,
          1,
        );
      });

      testWidgets('cancelling the warning starts nothing (${gpu.name})', (
        tester,
      ) async {
        final rec = await _pumpStep(
          tester,
          gpu: gpu,
          skipShortBenchmark: true,
          freeDiskBytes: 1024,
        );
        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('confirm-dialog-cancel'));
        await tester.pumpAndSettle();

        expect(rec.whisper.downloadModelCalls, isEmpty);
        expect(rec.parakeet.downloadBundleCalls, 0);
      });

      for (final free in [null, 1 << 50]) {
        testWidgets('${free == null ? 'unknown' : 'enough'} space starts '
            'without a warning (${gpu.name})', (tester) async {
          final rec = await _pumpStep(
            tester,
            gpu: gpu,
            skipShortBenchmark: true,
            freeDiskBytes: free,
          );
          await tester.tap(
            find.bySemanticsIdentifier('onboarding-speech-start-download'),
          );
          await tester.pump();

          expect(
            rec.whisper.downloadModelCalls.length +
                rec.parakeet.downloadBundleCalls,
            1,
          );
        });
      }
    }
  });

  group('ModelStep — cancelling a download (UIA-ONB-02)', () {
    for (final gpu in [_appleM2, _cpuOnly]) {
      testWidgets('a running download can be cancelled and the page returns '
          'to its choice state (${gpu.name})', (tester) async {
        final rec = await _pumpStep(tester, gpu: gpu);
        final cta = find.bySemanticsIdentifier(
          'onboarding-speech-start-download',
        );
        expect(cta, findsOneWidget);
        expect(find.byKey(kModelStepDownloadCancelKey), findsNothing);

        await tester.tap(cta);
        await tester.pump();
        expect(find.byKey(kModelStepDownloadCancelKey), findsOneWidget);

        await tester.tap(find.byKey(kModelStepDownloadCancelKey));
        await tester.pump();

        expect(rec.whisper.cancelCalls + rec.parakeet.cancelCalls, 1);
        expect(find.byKey(kModelStepDownloadCancelKey), findsNothing);
        expect(cta, findsOneWidget);
      });
    }
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

        // Tapping the disabled Parakeet card must not select it — the CTA
        // stays wired to Whisper. Downloading confirms which engine is
        // actually selected.
        await tester.tap(find.byKey(kModelStepEngineParakeetCardKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
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
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();

        expect(rec.whisper.downloadModelCalls, [
          bestModelForTier(QualityTier.premium).id,
        ]);
        expect(rec.parakeet.downloadBundleCalls, 0);
      },
    );
  });

  group('ModelStep — tier follows this machine\'s measurement (UIA-RT-03)', () {
    testWidgets(
      'a measured fast tier beats the VRAM estimate, as in Settings',
      (tester) async {
        // 24 GB NVIDIA: VRAM alone recommends Premium. This machine's
        // measurement says Compact is fast enough, and Settings already shows
        // that verdict, so onboarding must download the same model.
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'Test GPU',
          vramMB: 24576,
          cudaAvailable: true,
        );
        final rec = await _pumpStep(
          tester,
          gpu: gpu,
          dictationLocale: 'he',
          benchmark: BenchmarkSettings(
            tierBenchmarkRtf: const {QualityTier.compact: 0.2},
            benchmarkHardwareId: benchmarkMachineKey(
              hardwareKey: benchmarkHardwareKey(gpu),
              appVersion: app.appVersion,
            ),
          ),
        );

        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();

        expect(rec.whisper.downloadModelCalls, [
          bestModelForTier(QualityTier.compact).id,
        ]);
      },
    );

    testWidgets('a measurement taken on other hardware is ignored', (
      tester,
    ) async {
      const gpu = hw.GpuInfo(
        vendor: hw.GpuVendor.nvidia,
        name: 'Test GPU',
        vramMB: 24576,
        cudaAvailable: true,
      );
      final rec = await _pumpStep(
        tester,
        gpu: gpu,
        dictationLocale: 'he',
        benchmark: const BenchmarkSettings(
          tierBenchmarkRtf: {QualityTier.compact: 0.2},
          benchmarkHardwareId: 'nvidia_1000|0.0.0',
        ),
      );

      await tester.tap(
        find.bySemanticsIdentifier('onboarding-speech-start-download'),
      );
      await tester.pumpAndSettle();

      expect(rec.whisper.downloadModelCalls, [
        bestModelForTier(QualityTier.premium).id,
      ]);
    });
  });

  group('ModelStep — Parakeet download path', () {
    testWidgets(
      'selecting Parakeet (recommended for German) and tapping download '
      'calls parakeetDownloadProvider.downloadBundle',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _cpuOnly,
          skipShortBenchmark: true,
          dictationLocale: 'de',
        );

        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
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
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();

        expect(rec.parakeet.downloadBundleCalls, 0);
        expect(rec.whisper.downloadModelCalls, [
          bestModelForTier(QualityTier.premium).id,
        ]);
      },
    );
  });

  group('ModelStep — system engine (macOS 26+)', () {
    const checkedEn = SystemSpeechStatus(
      osSupported: true,
      checked: true,
      localeSupported: 'en-US',
    );
    Finder appleCard() =>
        find.bySemanticsIdentifier('onboarding-speech-engine-apple');
    Finder startButton() =>
        find.bySemanticsIdentifier('onboarding-speech-start-download');

    testWidgets('without OS support the third card is missing', (tester) async {
      await _pumpStep(tester, gpu: _appleM2);

      expect(appleCard(), findsNothing);
      expect(
        find.bySemanticsIdentifier('onboarding-speech-engine-whisper'),
        findsOneWidget,
      );
    });

    testWidgets('the hardware recommendation stays preselected next to the '
        'system card', (tester) async {
      final rec = await _pumpStep(
        tester,
        gpu: _appleM2,
        dictationLocale: 'he',
        stt: const SttSettings(language: 'he'),
        systemSupported: true,
        systemInitial: checkedEn,
      );

      expect(appleCard(), findsOneWidget);
      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(rec.whisper.downloadModelCalls, isNotEmpty);
      expect(rec.system.installCalls, 0);
    });

    testWidgets('picking the system card loads the language assets and '
        'persists the engine once they are ready', (tester) async {
      final rec = await _pumpStep(
        tester,
        gpu: _appleM2,
        stt: const SttSettings(language: 'en'),
        systemSupported: true,
        systemInitial: checkedEn,
      );

      await tester.tap(appleCard());
      await tester.pumpAndSettle();
      await tester.tap(startButton());
      await tester.pump();

      expect(rec.system.installCalls, 1);
      expect(rec.whisper.downloadModelCalls, isEmpty);
      expect(rec.parakeet.downloadBundleCalls, 0);

      rec.system.completeInstall();
      await tester.pumpAndSettle();

      expect(rec.settings.state.value!.stt.engine, 'system');
    });

    testWidgets('with an automatic language the system card is locked and a '
        'tap keeps the recommendation', (tester) async {
      final rec = await _pumpStep(
        tester,
        gpu: _appleM2,
        stt: const SttSettings(language: 'auto'),
        systemSupported: true,
        systemInitial: const SystemSpeechStatus(
          osSupported: true,
          checked: true,
        ),
      );

      await tester.tap(appleCard(), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(rec.system.installCalls, 0);
      expect(
        rec.whisper.downloadModelCalls.length +
            rec.parakeet.downloadBundleCalls,
        greaterThan(0),
      );
    });
  });

  group('ModelStep — persistence when the selected engine is on disk', () {
    testWidgets(
      'already-installed recommended Parakeet persists sttEngine=parakeet '
      'on mount, leaves sttModel untouched',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _cpuOnly,
          skipShortBenchmark: true,
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
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
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
      'on a first run without any download the recommendation is saved, so '
      'the dock names the engine onboarding recommended (UIA-RT-03, E1a)',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'en',
        );

        expect(rec.settings.state.value!.stt.engine, 'parakeet');
        expect(rec.whisper.downloadModelCalls, isEmpty);
        expect(rec.parakeet.downloadBundleCalls, 0);
      },
    );

    testWidgets('a Whisper recommendation is saved with its tier model '
        '(UIA-RT-03, E1a)', (tester) async {
      final rec = await _pumpStep(tester, gpu: _appleM2, dictationLocale: 'he');

      expect(rec.settings.state.value!.stt.engine, 'whisper');
      expect(
        rec.settings.state.value!.stt.model,
        bestModelForTier(QualityTier.premium).id,
      );
    });

    testWidgets('after the first run nothing is saved on its own, so a '
        'stored value is never overwritten (UIA-RT-03, E1a)', (tester) async {
      final rec = await _pumpStep(
        tester,
        gpu: _appleM2,
        dictationLocale: 'de',
        onboardingCompleted: true,
        stt: const SttSettings(engine: 'whisper', model: 'whisper-small'),
      );

      expect(rec.settings.updateCalls, 0);
      expect(rec.settings.state.value!.stt.engine, 'whisper');
      expect(rec.settings.state.value!.stt.model, 'whisper-small');
    });
  });

  // -------------------------------------------------------------------------
  // UIA-RT-01: the chosen engine is the active one, even before its download
  // finishes. The preflight reads these settings, so a choice that is only
  // saved after the download makes it check the wrong model.
  // -------------------------------------------------------------------------
  group('ModelStep — a chosen engine is saved before its download ends', () {
    testWidgets('choosing Whisper saves it at once, before any download', (
      tester,
    ) async {
      final rec = await _pumpStep(tester, gpu: _appleM2, dictationLocale: 'en');
      // The first run saves the recommendation, Parakeet for English (E1a);
      // for any other language a premium Whisper wins on this machine.
      expect(rec.settings.state.value!.stt.engine, 'parakeet');
      await tester.pumpAndSettle();
      expect(rec.settings.state.value!.stt.engine, 'parakeet');

      await tester.tap(find.byKey(kModelStepEngineWhisperCardKey));
      await tester.pumpAndSettle();

      expect(
        rec.settings.state.value!.stt.engine,
        'whisper',
        reason: 'The preflight reads the saved engine, not the card.',
      );
      expect(
        rec.settings.state.value!.stt.model,
        bestModelForTier(QualityTier.premium).id,
        reason: 'Whisper saves the model it will download, too.',
      );
      expect(rec.whisper.downloadModelCalls, isEmpty);
    });

    testWidgets('starting the Parakeet download saves the engine while it is '
        'still downloading', (tester) async {
      final rec = await _pumpStep(tester, gpu: _cpuOnly, dictationLocale: 'de');

      await tester.tap(
        find.bySemanticsIdentifier('onboarding-speech-start-download'),
      );
      await tester.pumpAndSettle();

      expect(rec.parakeet.downloadBundleCalls, 1);
      expect(
        rec.settings.state.value!.stt.engine,
        'parakeet',
        reason: 'Still downloading, so the engine must already be saved.',
      );
      expect(
        rec.settings.state.value!.sttModel,
        AppSettings.defaults.sttModel,
        reason: 'Parakeet selection must not touch the whisper model id',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Ticket 05 — a configured choice survives an untouched visit.
  //
  // Every case here runs with `onboardingCompleted: true`, i.e. the page as a
  // returning user sees it (the manually reopened flow). The groups above
  // cover the same page during the first run, where nothing is configured yet
  // and the recommendation is what preselects — they must stay untouched.
  // -------------------------------------------------------------------------
  group('ModelStep — a configured choice is not overwritten', () {
    testWidgets(
      'a deliberately chosen Whisper model survives a visit that changes '
      'nothing, even where the hardware tier would resolve higher',
      (tester) async {
        // Premium hardware, so the tier alone resolves to Large v3 Turbo —
        // and both models are on disk, which is what used to make the
        // untouched visit persist the tier model over the chosen one.
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'he',
          onboardingCompleted: true,
          stt: const SttSettings(engine: 'whisper', model: 'whisper-medium'),
          whisperInitial: const ModelDownloadState(
            downloadedModels: {'whisper-medium', 'whisper-large-v3-turbo'},
          ),
        );

        expect(rec.settings.state.value!.stt.engine, 'whisper');
        expect(
          rec.settings.state.value!.stt.model,
          'whisper-medium',
          reason:
              'The configured model must survive — the tier is a '
              'recommendation, not an override.',
        );
        expect(
          rec.settings.updateCalls,
          0,
          reason: 'An untouched visit must not write at all.',
        );
        expect(rec.whisper.downloadModelCalls, isEmpty);
      },
    );

    testWidgets('a configured Parakeet engine stays selected even where the '
        'recommendation would pick Whisper', (tester) async {
      final rec = await _pumpStep(
        tester,
        gpu: _appleM2,
        dictationLocale: 'he',
        onboardingCompleted: true,
        stt: const SttSettings(engine: 'parakeet'),
        parakeetInitial: const ParakeetDownloadState(installed: true),
        // On disk, so the old "recommendation wins" path would have had
        // everything it needed to persist Whisper over the user's choice.
        whisperInitial: const ModelDownloadState(
          downloadedModels: {'whisper-large-v3-turbo'},
        ),
      );

      expect(rec.settings.state.value!.stt.engine, 'parakeet');
      expect(rec.settings.updateCalls, 0);
    });

    testWidgets(
      'the recommendation stays visible next to a diverging configured '
      'choice and is one tap away',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          // German on a CPU-only machine recommends Parakeet, while this
          // user has Whisper configured — exactly the divergence the user
          // should get to see and be able to adopt.
          gpu: _cpuOnly,
          dictationLocale: 'de',
          onboardingCompleted: true,
          stt: const SttSettings(engine: 'whisper', model: 'whisper-medium'),
          whisperInitial: const ModelDownloadState(
            downloadedModels: {'whisper-medium'},
          ),
        );

        await tester.tap(find.byKey(kModelStepEngineParakeetCardKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();

        expect(
          rec.parakeet.downloadBundleCalls,
          1,
          reason: 'One tap adopts the recommendation.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Initial disk scan race (issue #78 root cause)
  // -------------------------------------------------------------------------

  group('ModelStep — initial disk scan race', () {
    testWidgets(
      'an already-downloaded configured Whisper model is still recognised '
      'when the disk scan resolves after hardware detection would otherwise '
      'have read the pre-scan empty state',
      (tester) async {
        // The configured model (whisper-medium) is genuinely already
        // downloaded — this is the "already downloaded before onboarding
        // ever scanned" case from issue #78 — but [notifier] withholds it
        // from `downloadedModels` until [_RaceableWhisperDownloadNotifier
        // .releaseScan] is called, reproducing the exact window in which
        // `_detectHardware()` used to read the still-empty pre-scan state.
        final notifier = _RaceableWhisperDownloadNotifier(
          const ModelDownloadState(downloadedModels: {'whisper-medium'}),
        );
        final parakeet = _RecordingParakeetDownloadNotifier(
          const ParakeetDownloadState(),
        );
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            interface_: InterfaceSettings(locale: 'de'),
            stt: SttSettings(model: 'whisper-medium'),
            onboarding: OnboardingSettings(onboardingCompleted: false),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              historyDatabaseProvider.overrideWith((ref) {
                final db = HistoryDatabase.forTesting(NativeDatabase.memory());
                ref.onDispose(db.close);
                return db;
              }),
              // German dictation recommends Parakeet — deliberately the
              // opposite of the configured Whisper engine, so a race that
              // discards the configured choice is visible as "wrong engine
              // selected" rather than a coincidental match.
              hw.gpuInfoProvider.overrideWith((_) async => _cpuOnly),
              settingsProvider.overrideWith(() => settings),
              modelDownloadProvider.overrideWith(() => notifier),
              parakeetDownloadProvider.overrideWith(() => parakeet),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wpDarkTheme(),
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: const Scaffold(
                body: Center(child: SizedBox(width: 720, child: ModelStep())),
              ),
            ),
          ),
        );
        await tester.pump();

        // Still parked on the scan — the step must not have decided on an
        // engine yet (the pre-fix bug decided here, wrongly, on Parakeet).
        expect(
          find.byKey(kModelStepEngineWhisperCardKey),
          findsNothing,
          reason:
              'ModelStep must wait for the disk scan before rendering a '
              'decision, not resolve on the pre-scan empty state.',
        );

        notifier.releaseScan();
        await tester.pumpAndSettle();

        expect(
          find.byKey(kModelStepEngineWhisperCardKey),
          findsOneWidget,
          reason:
              'The scan has now resolved and hardware detection can '
              'proceed.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Keyboard access
  // -------------------------------------------------------------------------

  group('ModelStep — keyboard access', () {
    testWidgets(
      'both engine cards take keyboard focus — they used to be a bare '
      'MouseRegion + GestureDetector, so the one page whose whole purpose is '
      'a binary choice could not be reached with Tab at all',
      (tester) async {
        // German on a premium machine: Whisper is recommended, and the
        // Parakeet card still has to be a choice.
        await _pumpStep(tester, gpu: _appleM2, dictationLocale: 'de');

        for (final entry in {
          'Parakeet': kModelStepEngineParakeetCardKey,
          'Whisper': kModelStepEngineWhisperCardKey,
        }.entries) {
          final inkWell = tester.widget<InkWell>(
            find.descendant(
              of: find.byKey(entry.value),
              matching: find.byType(InkWell),
            ),
          );
          expect(
            inkWell.focusNode?.canRequestFocus,
            isTrue,
            reason:
                'the ${entry.key} card must own a focusable node — without '
                'one there is no keyboard path to the engine choice',
          );
        }
      },
    );

    testWidgets(
      'activating the focused Whisper card with Enter selects it, exactly '
      'like a tap does',
      (tester) async {
        final rec = await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'de',
        );

        final whisperInk = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(kModelStepEngineWhisperCardKey),
            matching: find.byType(InkWell),
          ),
        );
        whisperInk.focusNode!.requestFocus();
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        await tester.tap(
          find.bySemanticsIdentifier('onboarding-speech-start-download'),
        );
        await tester.pumpAndSettle();

        expect(
          rec.parakeet.downloadBundleCalls,
          0,
          reason:
              'Enter on the Whisper card must move the selection off '
              'the recommended Parakeet card',
        );
        expect(rec.whisper.downloadModelCalls, [
          bestModelForTier(QualityTier.premium).id,
        ]);
      },
    );
  });

  group('ModelStep — disabled engine card', () {});
}

/// The short benchmark's session result, pinned so the step never runs it.
class _PinnedBenchmarkRtf extends ShortBenchmarkRtf {
  @override
  double? build() => 0.2;
}
