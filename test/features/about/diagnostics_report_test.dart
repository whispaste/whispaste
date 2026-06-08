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
        serverBackend: 'cpu',
        sttFiles: const ['whisper-server.exe', 'ggml.dll'],
        vcRuntimePresent: true,
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
      expect(report, contains('VC++-Runtime vorhanden: ja'));
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
          serverBackend: null,
          sttFiles: const <String>[],
          vcRuntimePresent: null,
          gpu: null,
          logTail: const <String>[],
        );

        expect(report, contains('GPU: (nicht ermittelt)'));
        expect(report, contains('vorhanden: nein'));
        expect(report, isNot(contains('backend:')));
        expect(report, isNot(contains('VC++-Runtime')));
        expect(report, contains('Sprachdienst-Dateien: (keine)'));
        // No log section when the tail is empty.
        expect(report, isNot(contains('Logzeilen')));
      },
    );
  });
}
