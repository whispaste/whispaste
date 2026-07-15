/// Unit tests for the About-page diagnostics block formatter.
///
/// Only [formatDiagnosticsReport] (the pure formatter) is exercised here —
/// the async `gatherDiagnosticsReport` does real filesystem/GPU probing and
/// belongs to an integration surface, not a unit test.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/about/diagnostics_report.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

void main() {
  group('formatDiagnosticsReport', () {
    test('includes core environment + Sprachdienst state', () {
      final report = formatDiagnosticsReport(
        version: '1.2.35',
        variant: 'Microsoft Store / MSIX',
        osVersion: 'windows 10.0 (Build 26200)',
        dartVersion: 'Dart 3.11.0',
        locale: 'de-DE',
        executablePath: r'C:\Program Files\WindowsApps\...\whispaste.exe',
        serverPath: r'C:\...\models\stt\whisper-server.exe',
        serverExists: true,
        backend: 'cpu',
        sttServerState: 'error',
        sttErrorMessage: 'Sprachdienst kann das Sprachmodell nicht öffnen.',
        sttFiles: const ['whisper-server.exe', 'ggml.dll'],
        vcRuntimePresent: true,
        modelLoadProbe: const ModelLoadProbeResult(
          ran: true,
          loaded: false,
          exitCode: 3221225781,
          stderrTail: ["whisper_init_from_file: failed to open 'model'"],
        ),
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce GTX 650',
          cudaAvailable: false,
          vulkanAvailable: true,
        ),
        logTail: const ['line A', 'line B'],
      );

      expect(report, contains('WhisPaste v1.2.35 (Microsoft Store / MSIX)'));
      expect(report, contains('Locale: de-DE'));
      expect(report, contains('NVIDIA GeForce GTX 650'));
      expect(report, contains('Backend')); // optimalBackend label present
      expect(report, contains('vorhanden: ja'));
      expect(report, contains('backend: cpu'));
      expect(report, contains('Status: error'));
      expect(
        report,
        contains('letzter Fehler: Sprachdienst kann das Sprachmodell'),
      );
      expect(report, contains('VC++-Runtime vorhanden: ja'));
      expect(report, contains('Modell-Ladetest: FEHLER'));
      expect(report, contains('0xC0000135'));
      expect(report, contains('failed to open'));
      expect(report, contains('whisper-server.exe, ggml.dll'));
      expect(report, contains('--- letzte 2 Logzeilen ---'));
      expect(report, contains('line A'));
      expect(report, contains('line B'));
    });

    test(
      'degrades gracefully when GPU is null and VC runtime not applicable',
      () {
        final report = formatDiagnosticsReport(
          version: '1.2.35',
          variant: 'macos',
          osVersion: 'macos 14',
          dartVersion: 'Dart 3.11.0',
          locale: 'en-US',
          executablePath: '/Applications/WhisPaste.app/...',
          serverPath: '/Users/x/Library/.../whisper-server',
          serverExists: false,
          backend: null,
          sttFiles: const <String>[],
          vcRuntimePresent: null,
          gpu: null,
          logTail: const <String>[],
        );

        expect(report, contains('GPU: (nicht ermittelt)'));
        expect(report, contains('vorhanden: nein'));
        expect(report, isNot(contains('backend:')));
        expect(report, isNot(contains('letzter Fehler:')));
        expect(report, isNot(contains('Modell-Ladetest')));
        expect(report, isNot(contains('VC++-Runtime')));
        expect(report, contains('Sprachdienst-Dateien: (keine)'));
        // No log section when the tail is empty.
        expect(report, isNot(contains('Logzeilen')));
      },
    );
  });

  group('formatDiagnosticsReport — engine state (Issue 09)', () {
    test('renders backend/loadedModel/cpuFallbackActive from live engine '
        'state', () {
      final report = formatDiagnosticsReport(
        version: '1.3.0',
        variant: 'macos',
        osVersion: 'macos 26.5',
        dartVersion: 'Dart 3.12.1',
        locale: 'de-DE',
        executablePath: '/Applications/WhisPaste.app/...',
        serverPath: '/Users/x/Library/.../whisper-server',
        serverExists: false,
        backend: 'metal',
        sttServerState: 'ready',
        loadedModel: 'ggml-medium.bin',
        cpuFallbackActive: true,
        sttFiles: const <String>[],
        gpu: null,
        logTail: const <String>[],
      );

      expect(report, contains('backend: metal'));
      expect(report, contains('Modell: ggml-medium.bin'));
      expect(report, contains('CPU-Fallback aktiv: ja'));
    });

    test('tolerates sttServerState == null (standalone CLI case) — backend '
        'still renders, no Status/Modell/CPU-Fallback lines', () {
      final report = formatDiagnosticsReport(
        version: '1.3.0',
        variant: 'macos',
        osVersion: 'macos 26.5',
        dartVersion: 'Dart 3.12.1',
        locale: 'de-DE',
        executablePath: '/Applications/WhisPaste.app/...',
        serverPath: '/Users/x/Library/.../whisper-server',
        serverExists: false,
        backend: 'cpu',
        sttFiles: const <String>[],
        settingsUnavailable: true,
        gpu: null,
        logTail: const <String>[],
      );

      expect(report, contains('backend: cpu'));
      expect(report, isNot(contains('Status:')));
      expect(report, isNot(contains('Modell:')));
      expect(report, isNot(contains('CPU-Fallback aktiv:')));
      expect(report, contains('Standalone'));
    });
  });
}
