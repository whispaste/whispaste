/// Widget tests for the speech-section benchmark row.
///
/// The row reports a run in place: progress with cancel while running, the
/// last persisted result afterwards (with the hardware path and a switch when
/// the measured recommendation differs), and an inline error with retry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/benchmark_row.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt/benchmark_freshness.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._s);
  final AppSettings _s;

  @override
  Future<AppSettings> build() async => _s;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _s));
  }
}

class _Run extends BenchmarkRunNotifier {
  _Run(this._initial);
  final BenchmarkRunState _initial;

  @override
  BenchmarkRunState build() => _initial;
}

class _Downloads extends ModelDownloadNotifier {
  _Downloads(this._installed);
  final Set<String> _installed;

  @override
  ModelDownloadState build() =>
      ModelDownloadState(downloadedModels: _installed);
}

AppSettings _settings({
  String model = 'whisper-small',
  Map<QualityTier, double>? rtf,
  DateTime? at,
  String? backend,
  String locale = 'en',
}) => AppSettings(
  interface_: InterfaceSettings(locale: locale),
  stt: AppSettings.defaults.stt.copyWith(model: model),
  benchmark: BenchmarkSettings(
    tierBenchmarkRtf: rtf,
    benchmarkTimestamp: at,
    benchmarkBackend: backend,
    benchmarkHardwareId: benchmarkMachineKey(
      hardwareKey: 'cpu',
      appVersion: app.appVersion,
    ),
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required AppSettings settings,
  BenchmarkRunState run = const BenchmarkRunState(),
  Set<String> installed = const {},
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _Settings(settings)),
      sttBenchmarkRunProvider.overrideWith(() => _Run(run)),
      modelDownloadProvider.overrideWith(() => _Downloads(installed)),
      hw.gpuInfoProvider.overrideWith(
        (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('de'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: SttBenchmarkRow())),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final measuredAt = DateTime(2026, 10, 19, 14, 32);

  testWidgets('idle with a stored result shows it in place', (tester) async {
    await _pump(
      tester,
      settings: _settings(
        rtf: {QualityTier.compact: 0.0288, QualityTier.balanced: 0.2},
        at: measuredAt,
        backend: 'metal',
      ),
      installed: {'whisper-small', 'whisper-medium'},
    );

    expect(find.byKey(const ValueKey('settings-benchmark-result')), findsOne);
    expect(find.textContaining('Zuletzt gemessen: 19.10.2026'), findsOneWidget);
    expect(find.textContaining('Grafikkarte (Metal)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-benchmark-tier-compact')),
      findsOneWidget,
    );
    expect(find.textContaining('0,03 s Rechenzeit'), findsOneWidget);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('settings-benchmark-run')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('with Parakeet selected it says Parakeet is not measured', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: _settings().copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          engine: OnDeviceEngine.parakeet.value,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('settings-benchmark-parakeet')),
      findsOneWidget,
    );
    expect(find.textContaining('Parakeet wird nicht gemessen'), findsOneWidget);
  });

  testWidgets('while running it shows progress, disables the run button and '
      'offers cancel', (tester) async {
    await _pump(
      tester,
      settings: _settings(),
      run: const BenchmarkRunState(
        phase: BenchmarkRunPhase.running,
        done: 1,
        total: 3,
        tier: QualityTier.balanced,
      ),
    );

    expect(
      find.byKey(const ValueKey('settings-benchmark-progress')),
      findsOneWidget,
    );
    expect(find.text('Läuft… Stufe 2 von 3: Ausgewogen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-benchmark-cancel')),
      findsOneWidget,
    );
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('settings-benchmark-run')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a busy refusal is shown inline with a retry', (tester) async {
    await _pump(
      tester,
      settings: _settings(),
      run: const BenchmarkRunState(
        phase: BenchmarkRunPhase.failed,
        error: BenchmarkRunError.busy,
      ),
    );

    expect(
      find.text(
        'Während einer Aufnahme kann der Test nicht laufen. Starte ihn danach erneut.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-benchmark-retry')),
      findsOneWidget,
    );
  });

  testWidgets('a measured recommendation that differs names the tier and '
      'switches the model on tap', (tester) async {
    final container = await _pump(
      tester,
      settings: _settings(
        model: 'whisper-small',
        rtf: {QualityTier.compact: 0.9, QualityTier.balanced: 0.2},
        at: measuredAt,
        backend: 'cpu',
        locale: 'he',
      ),
      installed: {'whisper-small', 'whisper-medium'},
    );

    expect(
      find.byKey(const ValueKey('settings-benchmark-recommendation')),
      findsOneWidget,
    );
    expect(find.text('Nach der Messung empfohlen: Ausgewogen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-benchmark-switch')));
    await tester.pump();

    expect(
      container.read(settingsProvider).value!.effectiveModelId,
      'whisper-medium',
    );
  });

  testWidgets('with Whisper active, a Parakeet language still names the '
      'Whisper tier this machine warrants (UIA-RT-03, E2a)', (tester) async {
    // The row only shows while Whisper is the active engine, so the tier it
    // names is a recommendation within Whisper, not against Parakeet.
    await _pump(
      tester,
      settings: _settings(
        model: 'whisper-small',
        rtf: {QualityTier.compact: 0.9, QualityTier.balanced: 0.2},
        at: measuredAt,
        backend: 'cpu',
      ),
      installed: {'whisper-small', 'whisper-medium'},
    );

    expect(
      find.byKey(const ValueKey('settings-benchmark-recommendation')),
      findsOneWidget,
    );
  });

  // UIA-XP-7-03: Vulkan on llvmpipe is the processor, in every app language.
  group('benchmarkBackendLabel (UIA-XP-7-03)', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(Locale(locale.languageCode));

      test('llvmpipe is not a graphics card, ${locale.languageCode}', () {
        final label = benchmarkBackendLabel(
          l10n,
          'vulkan',
          gpuName: 'llvmpipe (LLVM 15.0.7, 256 bits)',
        );
        expect(label, l10n.benchmarkBackendSoftwareVulkan('llvmpipe'));
        expect(label, isNot(l10n.benchmarkBackendGpu('Vulkan')));
      });

      test('a real Vulkan GPU stays a graphics card, '
          '${locale.languageCode}', () {
        expect(
          benchmarkBackendLabel(l10n, 'vulkan', gpuName: 'AMD Radeon 780M'),
          l10n.benchmarkBackendGpu('Vulkan'),
        );
        expect(
          benchmarkBackendLabel(l10n, 'vulkan', gpuName: null),
          l10n.benchmarkBackendGpu('Vulkan'),
        );
      });

      // UIA-XP-7-12: one tier reads in the singular.
      test('one measured tier is singular, ${locale.languageCode}', () {
        expect(l10n.benchmarkDone(1), isNot(l10n.benchmarkDone(2)));
        expect(l10n.benchmarkDone(1), isNot(contains('{')));
        expect(l10n.benchmarkDone(3), contains('3'));
      });
    }

    test('German says "1 Stufe"', () {
      expect(
        lookupL10n(const Locale('de')).benchmarkDone(1),
        'Messung abgeschlossen: 1 Stufe gemessen.',
      );
    });
  });
}
