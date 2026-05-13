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
  @override
  SttStatus build() => const SttStatus(serverState: SttServerState.stopped);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Wraps [SttModelSelector] in a minimal [ProviderScope] + [MaterialApp].
///
/// No Drift database, no [settingsProvider] override — only
/// [modelDownloadProvider] and [localSttBundleProvider] are stubbed.
Widget _makeTestable({
  ModelDownloadState downloadState = const ModelDownloadState(),
  String? currentModelId,
  Map<QualityTier, double>? benchmarkRtf,
  hw.GpuInfo? gpu,
  void Function(String)? onModelSelected,
}) {
  return ProviderScope(
    overrides: [
      modelDownloadProvider.overrideWith(
        () => _FakeDownloadNotifier(downloadState),
      ),
      localSttBundleProvider.overrideWith(() => _FakeSttNotifier()),
      // Prevent real GPU detection (spawns subprocess → pending timers).
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
  group('SttModelSelector', () {
    testWidgets('renders all three tier cards', (tester) async {
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Quick & Compact'), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('Best Quality'), findsOneWidget);
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
        await tester.tap(find.text('Quick & Compact'));
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

    testWidgets('does not import or depend on settingsProvider', (
      tester,
    ) async {
      // If SttModelSelector compiled without settingsProvider and renders here
      // without it being overridden, the architectural constraint is satisfied.
      await tester.pumpWidget(_makeTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

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
        await tester.tap(find.text('Quick & Compact'));
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
}
