/// Widget tests for [ModelStep] (onboarding step 3).
///
/// Verify that the 3-tier UI renders correctly with the current registry,
/// that hardware recommendations map to the right tier, and that tapping the
/// download CTA triggers a download of the tier representative (the only
/// model installable per [bestModelForTier]).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

class _RecordingDownloadNotifier extends ModelDownloadNotifier {
  _RecordingDownloadNotifier(this._initial);

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
}

void _noop() {}

Future<_RecordingDownloadNotifier> _pumpStep(
  WidgetTester tester, {
  required hw.GpuInfo gpu,
  ModelDownloadState initial = const ModelDownloadState(),
  Locale? locale,
}) async {
  late _RecordingDownloadNotifier captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        hw.gpuInfoProvider.overrideWith((_) async => gpu),
        modelDownloadProvider.overrideWith(() {
          captured = _RecordingDownloadNotifier(initial);
          return captured;
        }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wpDarkTheme(),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1280, 1600)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: ModelStep(onNext: _noop, onBack: _noop),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelStep', () {
    testWidgets('renders all three tier cards once GPU is detected', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.apple,
          name: 'Apple M2',
          vramMB: 8192,
        ),
      );

      expect(tester.takeException(), isNull);
      // Selected tier card + expanded alternatives reveal all 3 tier labels.
      await tester.tap(find.text('Choose a different quality level'));
      await tester.pumpAndSettle();

      expect(find.text('Quick & Compact'), findsWidgets);
      expect(find.text('Balanced'), findsWidgets);
      expect(find.text('Best Quality'), findsWidgets);
    });

    testWidgets('Apple GPU with ≥4 GB unified memory recommends Premium', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.apple,
          name: 'Apple M2',
          vramMB: 8192,
        ),
      );

      // The recommended tier should be Premium → its label is shown as the
      // pre-selected card. Tier-label uniqueness on a fresh render proves the
      // selection.
      expect(find.text('Best Quality'), findsOneWidget);
    });

    testWidgets('CPU-only fallback recommends Compact tier', (tester) async {
      await _pumpStep(
        tester,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU only'),
      );

      expect(find.text('Quick & Compact'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // GPU CPU fallback notice (issue 02-tech-gpu-detection-resilience)
    // -----------------------------------------------------------------------

    testWidgets(
      'GpuVendor.none renders the German CPU-fallback notice and keeps the '
      'Next button enabled once a model is downloaded',
      (tester) async {
        await _pumpStep(
          tester,
          gpu: const hw.GpuInfo(
            vendor: hw.GpuVendor.none,
            name: 'Detection failed — using CPU',
          ),
          // Pre-flag a downloaded model so the Next button is enabled and we
          // can verify GPU detection failure does NOT block onboarding.
          initial: const ModelDownloadState(
            downloadedModels: {'whisper-small'},
            phase: DownloadPhase.done,
          ),
          locale: const Locale('de'),
        );

        // The fallback notice is mounted via its widget key.
        expect(find.byKey(kModelStepGpuCpuFallbackKey), findsOneWidget);
        // Exact PRD-conformant string — vocabulary check covers this in CI.
        expect(
          find.text(
            'Optimierte GPU-Beschleunigung nicht verfügbar — App nutzt CPU',
          ),
          findsOneWidget,
        );

        // Next button is rendered and enabled — GpuVendor.none must NOT be
        // interpreted as „system not compatible".
        final nextButton = find.byKey(kModelStepNextButtonKey);
        expect(nextButton, findsOneWidget);
        final widget = tester.widget<WpAccentButton>(nextButton);
        expect(
          widget.onPressed,
          isNotNull,
          reason:
              'Next button must be enabled when a model is ready, '
              'regardless of GPU detection outcome.',
        );
      },
    );

    testWidgets('GpuVendor.apple does NOT render the CPU-fallback notice', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.apple,
          name: 'Apple M2',
          vramMB: 8192,
        ),
        locale: const Locale('de'),
      );

      expect(find.byKey(kModelStepGpuCpuFallbackKey), findsNothing);
    });

    testWidgets(
      'tapping the download CTA triggers exactly the tier representative',
      (tester) async {
        final notifier = await _pumpStep(
          tester,
          gpu: const hw.GpuInfo(
            vendor: hw.GpuVendor.apple,
            name: 'Apple M2',
            vramMB: 8192,
          ),
        );

        // Premium is recommended for 8GB Apple. The CTA contains the tier size.
        await tester.tap(find.textContaining('Download & Continue'));
        await tester.pumpAndSettle();

        expect(notifier.downloadModelCalls, [
          bestModelForTier(QualityTier.premium).id,
        ]);
        expect(
          notifier.downloadModelCalls.single,
          'whisper-large-v3-turbo',
          reason:
              'Premium tier downloads exactly the registry representative — '
              'no legacy IDs leak through.',
        );
      },
    );

    testWidgets(
      'after selecting Balanced via alternatives, CTA downloads whisper-medium',
      (tester) async {
        final notifier = await _pumpStep(
          tester,
          gpu: const hw.GpuInfo(
            vendor: hw.GpuVendor.apple,
            name: 'Apple M2',
            vramMB: 8192,
          ),
        );

        // Open alternative tiers (collapsed by default), pick Balanced.
        await tester.tap(find.text('Choose a different quality level'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Balanced').last);
        await tester.pumpAndSettle();

        // Tap CTA — now points at Balanced tier.
        await tester.tap(find.textContaining('Download & Continue'));
        await tester.pumpAndSettle();

        expect(notifier.downloadModelCalls, [
          bestModelForTier(QualityTier.balanced).id,
        ]);
        expect(notifier.downloadModelCalls.single, 'whisper-medium');
      },
    );

    testWidgets(
      'after selecting Compact via alternatives, CTA downloads whisper-small',
      (tester) async {
        final notifier = await _pumpStep(
          tester,
          gpu: const hw.GpuInfo(
            vendor: hw.GpuVendor.apple,
            name: 'Apple M2',
            vramMB: 8192,
          ),
        );

        await tester.tap(find.text('Choose a different quality level'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quick & Compact').last);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Download & Continue'));
        await tester.pumpAndSettle();

        expect(notifier.downloadModelCalls, [
          bestModelForTier(QualityTier.compact).id,
        ]);
        expect(notifier.downloadModelCalls.single, 'whisper-small');
      },
    );
  });
}
