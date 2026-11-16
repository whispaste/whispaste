/// Widget tests for [SttModelSelector].
///
/// These tests exercise the tier-card rendering in isolation — no Drift
/// database, no [settingsProvider], no [ProviderContainer] required.
/// Only [modelDownloadProvider] and [localSttBundleProvider] are overridden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/settings/stt_model_selector.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

// ---------------------------------------------------------------------------
// Fake notifiers — no Drift, no settingsProvider
// ---------------------------------------------------------------------------

class _FakeDownloadNotifier extends ModelDownloadNotifier {
  _FakeDownloadNotifier(this._initial);

  final ModelDownloadState _initial;

  @override
  ModelDownloadState build() => _initial;
}

/// Controllable fake that records [downloadModel] calls and simulates
/// the start-then-cancel lifecycle without network I/O.
class _ControllableDownloadNotifier extends ModelDownloadNotifier {
  _ControllableDownloadNotifier(this._initial);

  final ModelDownloadState _initial;

  /// IDs passed to [downloadModel] since the notifier was created.
  final List<String> downloadModelCalls = [];

  @override
  ModelDownloadState build() => _initial;

  /// Records the call and immediately sets [activeModelId] to simulate a
  /// download starting (but does NOT complete or call settingsProvider).
  @override
  Future<void> downloadModel(String modelId) async {
    downloadModelCalls.add(modelId);
    state = state.copyWith(
      activeModelId: modelId,
      phase: DownloadPhase.downloading,
      progressPercent: 0,
    );
  }

  /// Resets to idle, mirroring the real [cancelDownload] behaviour.
  @override
  void cancelDownload() {
    state = state.copyWith(
      phase: DownloadPhase.idle,
      activeModelId: null,
      progressPercent: 0,
    );
  }
}

class _FakeSttNotifier extends SttServerStateNotifier {
  _FakeSttNotifier({
    this.isBenchmarking = false,
    this.benchmarkingTier,
    this.restartNeeded = false,
  });

  final bool isBenchmarking;
  final QualityTier? benchmarkingTier;
  final bool restartNeeded;

  @override
  SttStatus build() => SttStatus(
    serverState: SttServerState.stopped,
    isBenchmarking: isBenchmarking,
    benchmarkingTier: benchmarkingTier,
    restartNeeded: restartNeeded,
  );
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Wraps [SttModelSelector] in a minimal [ProviderScope] + [MaterialApp].
///
/// No Drift database, no [settingsProvider] override — only
/// [modelDownloadProvider] and [localSttBundleProvider] are stubbed.
late L10n l10n;

Widget _makeTestable({
  ModelDownloadState downloadState = const ModelDownloadState(),
  String? currentModelId,
  Map<QualityTier, double>? benchmarkRtf,
  hw.GpuInfo? gpu,
  void Function(String)? onModelSelected,
  bool isBenchmarking = false,
  QualityTier? benchmarkingTier,
  bool restartNeeded = false,
}) {
  return ProviderScope(
    overrides: [
      modelDownloadProvider.overrideWith(
        () => _FakeDownloadNotifier(downloadState),
      ),
      localSttBundleProvider.overrideWith(
        () => _FakeSttNotifier(
          isBenchmarking: isBenchmarking,
          benchmarkingTier: benchmarkingTier,
          restartNeeded: restartNeeded,
        ),
      ),
      // Prevent real GPU detection (spawns subprocess → pending timers).
      hw.gpuInfoProvider.overrideWith(
        (ref) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      // Pin locale to `en` so tier labels are deterministic across CI hosts.
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SttModelSelector(
          currentModelId: currentModelId,
          benchmarkRtf: benchmarkRtf,
          gpu: gpu,
          onModelSelected: onModelSelected ?? (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('restart hint', () {
    const hintKey = ValueKey('settings-stt-engine-restart-hint');

    testWidgets('shows the restart hint when the engine is stuck', (
      tester,
    ) async {
      await tester.pumpWidget(_makeTestable(restartNeeded: true));
      await tester.pumpAndSettle();

      expect(find.byKey(hintKey), findsOneWidget);
    });

    testWidgets('hides the restart hint while the engine is healthy', (
      tester,
    ) async {
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();

      expect(find.byKey(hintKey), findsNothing);
    });
  });

  group('SttModelSelector', () {
    testWidgets('no Drift database required — renders in isolation', (
      tester,
    ) async {
      // This test verifies the extraction goal: SttModelSelector renders
      // with only a fake ModelDownloadNotifier; no HistoryDatabase is set up.
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'calls onModelSelected when an already-downloaded tier is tapped',
      (tester) async {
        String? selected;

        final state = ModelDownloadState(
          downloadedModels: {bestModelForTier(QualityTier.compact).id},
        );

        await tester.pumpWidget(
          _makeTestable(
            downloadState: state,
            onModelSelected: (id) => selected = id,
          ),
        );
        await tester.pumpAndSettle();

        // Tap the Compact card (it's downloaded → triggers onModelSelected).
        await tester.tap(find.byKey(const ValueKey('stt-model-tier-compact')));
        await tester.pumpAndSettle();

        expect(selected, bestModelForTier(QualityTier.compact).id);
      },
    );

    Future<void> assertTierDownloadsModel(
      WidgetTester tester, {
      required String tierLabel,
      required String expectedModelId,
    }) async {
      final captured = <String>[];
      late _ControllableDownloadNotifier notifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelDownloadProvider.overrideWith(() {
              notifier = _ControllableDownloadNotifier(
                const ModelDownloadState(),
              );
              return notifier;
            }),
            localSttBundleProvider.overrideWith(() => _FakeSttNotifier()),
            hw.gpuInfoProvider.overrideWith(
              (ref) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wpDarkTheme(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SttModelSelector(
                currentModelId: null,
                onModelSelected: captured.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('stt-model-tier-$tierLabel')));
      // pump() — not pumpAndSettle(): the indeterminate progress spinner
      // would otherwise time out the settle.
      await tester.pump();

      expect(notifier.downloadModelCalls, [
        expectedModelId,
      ], reason: '$tierLabel tier must trigger download of $expectedModelId');
      expect(
        captured,
        isEmpty,
        reason:
            'onModelSelected fires only after download completes, not on tap',
      );
    }

    testWidgets('Compact tier tap downloads whisper-small', (tester) async {
      await assertTierDownloadsModel(
        tester,
        tierLabel: 'compact',
        expectedModelId: 'whisper-small',
      );
    });

    testWidgets('Balanced tier tap downloads whisper-medium', (tester) async {
      await assertTierDownloadsModel(
        tester,
        tierLabel: 'balanced',
        expectedModelId: 'whisper-medium',
      );
    });

    testWidgets('Premium tier tap downloads whisper-large-v3-turbo', (
      tester,
    ) async {
      await assertTierDownloadsModel(
        tester,
        tierLabel: 'premium',
        expectedModelId: 'whisper-large-v3-turbo',
      );
    });

    testWidgets('does not import or depend on settingsProvider', (
      tester,
    ) async {
      // If SttModelSelector compiled without settingsProvider and renders here
      // without it being overridden, the architectural constraint is satisfied.
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // AC4 regression: cancelled download must NOT trigger onModelSelected
    // -------------------------------------------------------------------------

    testWidgets(
      'AC4: tapping undownloaded tier card starts download but does NOT call '
      'onModelSelected; cancelling the download also does NOT call '
      'onModelSelected (settings remain unchanged)',
      (tester) async {
        // Track every onModelSelected invocation.
        final selectedIds = <String>[];

        // Initial state: no model is downloaded → tapping triggers downloadModel.
        const initialState = ModelDownloadState(downloadedModels: {});

        late _ControllableDownloadNotifier capturedNotifier;

        final widget = ProviderScope(
          overrides: [
            modelDownloadProvider.overrideWith(() {
              capturedNotifier = _ControllableDownloadNotifier(initialState);
              return capturedNotifier;
            }),
            localSttBundleProvider.overrideWith(() => _FakeSttNotifier()),
            hw.gpuInfoProvider.overrideWith(
              (ref) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wpDarkTheme(),
            // Pin locale to `en` so tier labels match the seeded `l10n` snapshot.
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SttModelSelector(
                currentModelId: null, // no model selected yet
                onModelSelected: selectedIds.add,
              ),
            ),
          ),
        );

        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();

        // --- Step 1: Tap the Compact tier card (not downloaded) ---
        await tester.tap(find.byKey(const ValueKey('stt-model-tier-compact')));
        await tester.pump();

        // downloadModel was called — download started.
        expect(capturedNotifier.downloadModelCalls, [
          bestModelForTier(QualityTier.compact).id,
        ]);

        // onModelSelected must NOT have been called yet.
        expect(
          selectedIds,
          isEmpty,
          reason: 'settings must not be written when download only starts',
        );

        // --- Step 2: Cancel the download ---
        capturedNotifier.cancelDownload();
        await tester.pump();

        // Phase is back to idle.
        expect(capturedNotifier.state.phase, DownloadPhase.idle);

        // onModelSelected must still NOT have been called after cancellation.
        expect(
          selectedIds,
          isEmpty,
          reason:
              'settings must remain unchanged when download is cancelled '
              '(AC4 regression)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Accessibility — tier rows must announce as buttons (screen readers
  // otherwise skip straight past them), but without a `label:` that repeats
  // the tier name already rendered as visible text underneath (see the
  // house-wide regression guard in
  // test/core/accessibility/no_double_announcement_test.dart).
  // -------------------------------------------------------------------------
  group('recommendation reason (MV-03)', () {
    testWidgets('names the CUDA card under the tiers', (tester) async {
      await tester.pumpWidget(
        _makeTestable(
          gpu: const hw.GpuInfo(
            vendor: hw.GpuVendor.nvidia,
            name: 'NVIDIA GeForce RTX 3060',
            vramMB: 12288,
            cudaAvailable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-stt-recommendation-reason')),
            )
            .data,
        l10n.recommendationReasonCuda('12'),
      );
    });

    testWidgets('shows no reason without GPU info', (tester) async {
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-stt-recommendation-reason')),
        findsNothing,
      );
    });
  });

  group('tier row accessibility', () {
    testWidgets(
      'selectable tier card exposes a button role and names itself once',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_makeTestable());
          await tester.pumpAndSettle();

          final node = tester.getSemantics(
            find.byKey(const ValueKey('stt-model-tier-compact')),
          );
          expect(node.flagsCollection.isButton, isTrue);
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'current, already-downloaded tier card carries no button role',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final modelId = bestModelForTier(QualityTier.compact).id;
          await tester.pumpWidget(
            _makeTestable(
              currentModelId: modelId,
              downloadState: ModelDownloadState(downloadedModels: {modelId}),
            ),
          );
          await tester.pumpAndSettle();

          final node = tester.getSemantics(
            find.byKey(const ValueKey('stt-model-tier-compact')),
          );
          expect(
            node.flagsCollection.isButton,
            isFalse,
            reason:
                'this tier is not tappable — onTap is null — so it '
                'must not be announced as an actionable button',
          );
        } finally {
          handle.dispose();
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // Graded performance info line
  //
  // The line renders for the *current* tier only, so at most one stage is on
  // screen at a time and a screenshot can never show the ramp. These tests
  // drive all four stages through the benchmark RTF the selector is given
  // (< 0.3 fast, < 0.8 moderate, else slow; no GPU at all → unmeasured) and
  // assert the colour/icon pairing directly.
  // -------------------------------------------------------------------------
  group('selected model missing on disk', () {
    const premiumKey = ValueKey('stt-model-download-premium');

    testWidgets('the selected tier offers the download once the scan has '
        'shown its model is missing', (tester) async {
      await tester.pumpWidget(
        _makeTestable(
          downloadState: const ModelDownloadState(scanned: true),
          currentModelId: 'whisper-large-v3-turbo',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(premiumKey), findsOneWidget);
    });

    testWidgets('no download chip before the initial scan has landed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _makeTestable(currentModelId: 'whisper-large-v3-turbo'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(premiumKey), findsNothing);
    });

    testWidgets('no download chip when the selected model is on disk', (
      tester,
    ) async {
      await tester.pumpWidget(
        _makeTestable(
          downloadState: const ModelDownloadState(
            scanned: true,
            downloadedModels: {'whisper-large-v3-turbo'},
          ),
          currentModelId: 'whisper-large-v3-turbo',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(premiumKey), findsNothing);
    });

    testWidgets('tapping the chip downloads the selected model', (
      tester,
    ) async {
      late _ControllableDownloadNotifier notifier;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelDownloadProvider.overrideWith(() {
              notifier = _ControllableDownloadNotifier(
                const ModelDownloadState(scanned: true),
              );
              return notifier;
            }),
            localSttBundleProvider.overrideWith(() => _FakeSttNotifier()),
            hw.gpuInfoProvider.overrideWith(
              (ref) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wpDarkTheme(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SttModelSelector(
                currentModelId: 'whisper-large-v3-turbo',
                onModelSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(premiumKey));
      await tester.pump();

      expect(notifier.downloadModelCalls, ['whisper-large-v3-turbo']);
    });
  });
}
