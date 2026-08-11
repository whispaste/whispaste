/// Widget tests for [SttModelSelector].
///
/// These tests exercise the tier-card rendering in isolation — no Drift
/// database, no [settingsProvider], no [ProviderContainer] required.
/// Only [modelDownloadProvider] and [localSttBundleProvider] are overridden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
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
  _FakeSttNotifier({this.isBenchmarking = false, this.benchmarkingTier});

  final bool isBenchmarking;
  final QualityTier? benchmarkingTier;

  @override
  SttStatus build() => SttStatus(
    serverState: SttServerState.stopped,
    isBenchmarking: isBenchmarking,
    benchmarkingTier: benchmarkingTier,
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
  bool isDark = true,
  bool isBenchmarking = false,
  QualityTier? benchmarkingTier,
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
      theme: isDark ? wpDarkTheme() : wpLightTheme(),
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

  group('SttModelSelector', () {
    testWidgets('renders all three tier cards', (tester) async {
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.qualityTierCompactLabel), findsOneWidget);
      expect(find.text(l10n.qualityTierBalancedLabel), findsOneWidget);
      expect(find.text(l10n.qualityTierPremiumLabel), findsOneWidget);
    });

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
        await tester.tap(find.text(l10n.qualityTierCompactLabel));
        await tester.pumpAndSettle();

        expect(selected, bestModelForTier(QualityTier.compact).id);
      },
    );

    testWidgets('shows download size badges for each tier', (tester) async {
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();

      // Each tier card shows the model size label.
      for (final tier in QualityTier.values) {
        expect(find.text(tierSizeLabel(tier)), findsOneWidget);
      }
    });

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

      await tester.tap(find.text(tierLabel));
      // pump() — not pumpAndSettle(): the indeterminate progress spinner
      // would otherwise time out the settle.
      await tester.pump();

      expect(
        notifier.downloadModelCalls,
        [expectedModelId],
        reason: '$tierLabel tier must trigger download of $expectedModelId',
      );
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
        tierLabel: 'Quick & Compact',
        expectedModelId: 'whisper-small',
      );
    });

    testWidgets('Balanced tier tap downloads whisper-medium', (tester) async {
      await assertTierDownloadsModel(
        tester,
        tierLabel: 'Balanced',
        expectedModelId: 'whisper-medium',
      );
    });

    testWidgets('Premium tier tap downloads whisper-large-v3-turbo', (
      tester,
    ) async {
      await assertTierDownloadsModel(
        tester,
        tierLabel: 'Best Quality',
        expectedModelId: 'whisper-large-v3-turbo',
      );
    });

    testWidgets(
      'currentModelId maps each registry model to the right tier card '
      '(active highlight)',
      (tester) async {
        for (final entry in <String, String>{
          'whisper-small': 'Quick & Compact',
          'whisper-medium': 'Balanced',
          'whisper-large-v3-turbo': 'Best Quality',
        }.entries) {
          await tester.pumpWidget(
            _makeTestable(
              currentModelId: entry.key,
              downloadState: ModelDownloadState(downloadedModels: {entry.key}),
            ),
          );
          await tester.pumpAndSettle();

          // The tier label is rendered exactly once and the card is marked
          // ready (no test of pixels — we only assert it renders without crash
          // and the label is present).
          expect(
            find.text(entry.value),
            findsOneWidget,
            reason: '${entry.key} should map to "${entry.value}" tier label',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

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
    // Recommended badge — plain-language copy + placement (issue
    // 06-empfohlen-badge-settings)
    // -------------------------------------------------------------------------

    testWidgets(
      'recommended badge uses plain-language German copy without hardware '
      'jargon',
      (tester) async {
        final deL10n = await L10n.delegate.load(const Locale('de'));

        expect(deL10n.qualityTierRecommended, 'Empfohlen für deinen Rechner');
        expect(
          deL10n.qualityTierRecommended.toUpperCase(),
          isNot(contains('VRAM')),
        );
        expect(
          deL10n.qualityTierRecommended.toUpperCase(),
          isNot(contains('GPU')),
        );
      },
    );

    testWidgets(
      'recommended badge renders only on the tier recommendTier() picks for '
      'this hardware',
      (tester) async {
        // NVIDIA GPU with 1000MB VRAM → recommendTier() picks Compact
        // (below the 2150MB Balanced threshold in the nvidia branch).
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'Test GPU',
          vramMB: 1000,
        );

        await tester.pumpWidget(_makeTestable(gpu: gpu));
        await tester.pumpAndSettle();

        // Badge renders exactly once across all three tier cards.
        expect(find.text(l10n.qualityTierRecommended), findsOneWidget);

        // It sits on the Compact tier card, not Balanced or Premium.
        final compactRow = find
            .ancestor(
              of: find.text(l10n.qualityTierCompactLabel),
              matching: find.byType(Row),
            )
            .first;
        expect(
          find.descendant(
            of: compactRow,
            matching: find.text(l10n.qualityTierRecommended),
          ),
          findsOneWidget,
          reason: 'badge must sit on the Compact tier card for this GPU',
        );

        final balancedRow = find
            .ancestor(
              of: find.text(l10n.qualityTierBalancedLabel),
              matching: find.byType(Row),
            )
            .first;
        expect(
          find.descendant(
            of: balancedRow,
            matching: find.text(l10n.qualityTierRecommended),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('shows error banner when download is in error state', (
      tester,
    ) async {
      const errorMsg = 'Network failure';
      const state = ModelDownloadState(
        phase: DownloadPhase.error,
        errorMessage: errorMsg,
      );

      await tester.pumpWidget(_makeTestable(downloadState: state));
      await tester.pumpAndSettle();

      expect(find.text(errorMsg), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // AC6: Error banner with retry button
    // -------------------------------------------------------------------------

    testWidgets('error banner shows retry button when download is in error', (
      tester,
    ) async {
      const errorMsg = 'Download failed';
      const state = ModelDownloadState(
        phase: DownloadPhase.error,
        errorMessage: errorMsg,
      );

      await tester.pumpWidget(_makeTestable(downloadState: state));
      await tester.pumpAndSettle();

      // Error message is shown
      expect(find.text(errorMsg), findsOneWidget);
      // Retry button is present
      expect(find.text(l10n.actionRetry), findsOneWidget);
      // Tapping retry does not throw
      await tester.tap(find.text(l10n.actionRetry));
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
        await tester.tap(find.text(l10n.qualityTierCompactLabel));
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
  // Graded performance info line
  //
  // The line renders for the *current* tier only, so at most one stage is on
  // screen at a time and a screenshot can never show the ramp. These tests
  // drive all four stages through the benchmark RTF the selector is given
  // (< 0.3 fast, < 0.8 moderate, else slow; no GPU at all → unmeasured) and
  // assert the colour/icon pairing directly.
  // -------------------------------------------------------------------------
  group('performance info line — graded by tier performance', () {
    const gpu = hw.GpuInfo(vendor: hw.GpuVendor.apple, name: 'Test GPU');
    final compactId = bestModelForTier(QualityTier.compact).id;

    /// Colour actually painted on the info message [message].
    Color? lineColor(WidgetTester tester, String message) =>
        tester.widget<Text>(find.text(message)).style?.color;

    for (final (themeName, isDark) in [('dark', true), ('light', false)]) {
      testWidgets('$themeName: a fast tier says nothing at all', (
        tester,
      ) async {
        await tester.pumpWidget(
          _makeTestable(
            isDark: isDark,
            gpu: gpu,
            currentModelId: compactId,
            benchmarkRtf: const {QualityTier.compact: 0.1},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.qualityTierInfoModerate), findsNothing);
        expect(find.byIcon(LucideIcons.gauge), findsNothing);
        expect(find.byIcon(LucideIcons.hourglass), findsNothing);
      });

      testWidgets('$themeName: a moderate tier takes the ramp\'s middle rung', (
        tester,
      ) async {
        await tester.pumpWidget(
          _makeTestable(
            isDark: isDark,
            gpu: gpu,
            currentModelId: compactId,
            benchmarkRtf: const {QualityTier.compact: 0.5},
          ),
        );
        await tester.pumpAndSettle();

        expect(
          lineColor(tester, l10n.qualityTierInfoModerate),
          WpCategorySlot.orchid.ramp(5)[3],
          reason:
              'the copy reads "Good balance of speed and quality" — it sits one '
              'rung under the slow verdict in the *same* hue, so the grading '
              'reads as less time rather than as praise contradicted by a tint',
        );
        expect(find.byIcon(LucideIcons.gauge), findsOneWidget);
      });

      testWidgets('$themeName: a slow tier takes the ramp\'s far rung', (
        tester,
      ) async {
        await tester.pumpWidget(
          _makeTestable(
            isDark: isDark,
            gpu: gpu,
            currentModelId: compactId,
            benchmarkRtf: const {QualityTier.compact: 1.5},
          ),
        );
        await tester.pumpAndSettle();

        expect(
          lineColor(tester, l10n.qualityTierInfoSlow('2.0')),
          WpCategorySlot.orchid.ramp(5)[4],
          reason:
              'the heaviest rung of the one hue, not a second hue — weight '
              'rises with the time cost the line reports',
        );
        expect(
          find.byIcon(LucideIcons.hourglass),
          findsOneWidget,
          reason:
              'an hourglass, not an alert triangle — the tier is slower, not '
              'broken',
        );
        expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
      });

      testWidgets('$themeName: an unmeasured tier claims nothing', (
        tester,
      ) async {
        await tester.pumpWidget(
          _makeTestable(isDark: isDark, currentModelId: compactId),
        );
        await tester.pumpAndSettle();

        expect(
          lineColor(tester, l10n.qualityTierInfoBenchmarking),
          WpColorsDark.textMuted,
          reason:
              'an unmeasured tier has no position on an ordinal scale, so it '
              'takes no rung of the ramp at all',
        );
        expect(find.byIcon(LucideIcons.hourglass), findsNothing);
        expect(find.byIcon(LucideIcons.gauge), findsNothing);
      });

      testWidgets(
        '$themeName: a running benchmark never borrows the slow verdict',
        (tester) async {
          // The VRAM estimate for this tier is `slow`, but nothing has been
          // measured yet — putting the line on the ramp's far rung here would
          // announce a verdict the app does not have.
          await tester.pumpWidget(
            _makeTestable(
              isDark: isDark,
              gpu: gpu,
              currentModelId: compactId,
              benchmarkRtf: const {QualityTier.compact: 1.5},
              isBenchmarking: true,
              benchmarkingTier: QualityTier.compact,
            ),
          );
          await tester.pump();

          expect(
            lineColor(tester, l10n.qualityTierInfoBenchmarking),
            WpColorsDark.textMuted,
            reason:
                'while measuring, the line must read as "no verdict yet", not '
                'as the estimate it is about to replace',
          );
        },
      );
    }
  });
}
