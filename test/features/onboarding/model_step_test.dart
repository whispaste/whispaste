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
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, rootBundle;
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
import 'package:whispaste/widgets/wp_button.dart';

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

  /// Pre-existing speech-recognition settings. Defaults to the factory
  /// values, which is what a first run has.
  SttSettings stt = const SttSettings(),

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
}) async {
  late _RecordingWhisperDownloadNotifier whisper;
  late _RecordingParakeetDownloadNotifier parakeet;
  final settings = _FakeSettingsNotifier(
    AppSettings(
      interface_: InterfaceSettings(locale: dictationLocale),
      stt: stt,
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
    // Real Inter metrics, not the square-glyph test font: the truncation
    // regression below is a width measurement, and with Ahem every glyph is
    // a full em square — roughly double Inter's width — so every title would
    // "overflow" and the test would pass for a reason the app never has.
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await fontLoader.load();
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

    testWidgets(
      'the download status sits under whichever engine card is selected — '
      'it used to render on the left half regardless, so with Whisper '
      '(the right card) selected it visibly belonged to the wrong card',
      (tester) async {
        await _pumpStep(tester, gpu: _appleM2, frameWidth: 720);

        final ctaFinder = find.textContaining(
          l10n.qualityTierDownloadAndContinue,
        );
        final parakeetLeft = tester
            .getTopLeft(find.byKey(kModelStepEngineParakeetCardKey))
            .dx;
        final whisperLeft = tester
            .getTopLeft(find.byKey(kModelStepEngineWhisperCardKey))
            .dx;

        // English dictation on this hardware recommends Parakeet, so the
        // CTA starts on the Parakeet card's own start edge. The button box
        // is the Expanded half itself, so the *button* edge (the text sits
        // inside its padding) has to match the card edge — compare via the
        // WpButton ancestor.
        Offset ctaButtonTopLeft() => tester.getTopLeft(
          find.ancestor(of: ctaFinder, matching: find.byType(WpButton)).first,
        );
        expect(ctaButtonTopLeft().dx, moreOrLessEquals(parakeetLeft));

        await tester.tap(find.byKey(kModelStepEngineWhisperCardKey));
        await tester.pumpAndSettle();
        expect(ctaButtonTopLeft().dx, moreOrLessEquals(whisperLeft));

        await tester.tap(find.byKey(kModelStepEngineParakeetCardKey));
        await tester.pumpAndSettle();
        expect(ctaButtonTopLeft().dx, moreOrLessEquals(parakeetLeft));
      },
    );

    testWidgets(
      'the recommended card shows its engine name in full at the real page '
      'width — the title used to ellipsise to "Schnell & e…" because it, the '
      '"recommended" badge and a Spacer split the card three ways',
      (tester) async {
        await _pumpStep(
          tester,
          gpu: _appleM2,
          // German: the longest badge of the three locales ("Empfohlen für
          // dein Gerät") against a title that has to survive it.
          dictationLocale: 'de',
          displayLocale: const Locale('de'),
          frameWidth: 720,
        );
        final localized = await L10n.delegate.load(const Locale('de'));

        // The badge must actually be on screen — without it the title has
        // the whole line to itself and this proves nothing.
        expect(find.text(localized.onboardingModelRecommended), findsOneWidget);

        final title = tester.renderObject<RenderParagraph>(
          find.text(localized.onboardingModelEngineParakeetLabel),
        );
        expect(
          title.didExceedMaxLines,
          isFalse,
          reason:
              'The engine name is ellipsised at the real page width — '
              '`TextOverflow.ellipsis` hides that silently, which is exactly '
              'how it shipped.',
        );
        expect(tester.takeException(), isNull);
      },
    );

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
        expect(
          find.text(l10n.modelReady),
          findsOneWidget,
          reason:
              'The configured model is already on disk — the step shows it '
              'as present instead of offering to download it again.',
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

        expect(
          find.text(l10n.onboardingModelRecommended),
          findsOneWidget,
          reason: 'The recommendation badge must still be on offer.',
        );

        await tester.tap(find.byKey(kModelStepEngineParakeetCardKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(l10n.qualityTierDownloadAndContinue),
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
        expect(
          find.text(l10n.modelReady),
          findsOneWidget,
          reason:
              'The model that was on disk all along must be recognised '
              'as ready, not offered up for re-download.',
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
          find.textContaining(l10n.qualityTierDownloadAndContinue),
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

  group('ModelStep — disabled engine card', () {
    testWidgets(
      'the reason a card cannot be picked keeps its full colour — it used to '
      'sit under a 50% Opacity veil together with the rest of the card, '
      'which dimmed the one line that explains the block to roughly 1.8:1',
      (tester) async {
        // Hebrew is not a Parakeet language, so the Parakeet card renders
        // disabled and carries its reason line.
        await _pumpStep(
          tester,
          gpu: _appleM2,
          dictationLocale: 'he',
          displayLocale: const Locale('he'),
        );
        final localized = await L10n.delegate.load(const Locale('he'));

        final reason = find.text(
          localized.onboardingModelEngineUnsupportedLanguage,
        );
        expect(
          reason,
          findsOneWidget,
          reason: 'the disabled branch must actually be rendered',
        );
        expect(
          find.ancestor(of: reason, matching: find.byType(Opacity)),
          findsNothing,
          reason:
              'no Opacity may sit over the disabled card: DESIGN.md forbids '
              'signalling disabled with a veil over live colours, and the '
              'veil is what made this line unreadable',
        );
      },
    );
  });
}
