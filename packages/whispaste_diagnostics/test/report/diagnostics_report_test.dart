/// Unit tests for the core diagnostics report formatter.
///
/// Mirrors the app-side `test/features/about/diagnostics_report_test.dart`
/// tests, verifying the formatter works identically from the pure-Dart core.
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/report/diagnostics_report.dart';

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
        gpu: const GpuInfo(
          vendor: GpuVendor.nvidia,
          name: 'NVIDIA GeForce GTX 650',
          cudaAvailable: false,
          vulkanAvailable: true,
        ),
        logTail: const ['line A', 'line B'],
      );

      expect(report, contains('WhisPaste v1.2.35 (Microsoft Store / MSIX)'));
      expect(report, contains('Locale: de-DE'));
      expect(report, contains('NVIDIA GeForce GTX 650'));
      expect(report, contains('Backend'));
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
          serverBackend: null,
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
        expect(report, isNot(contains('Logzeilen')));
      },
    );
  });

  group('ModelLoadProbeResult.exitCodeHex', () {
    test('STATUS_DLL_NOT_FOUND maps to 0xC0000135', () {
      // 3221225781 is the signed int representation of 0xC0000135
      const probe = ModelLoadProbeResult(ran: true, exitCode: 3221225781);
      expect(probe.exitCodeHex, '0xC0000135');
    });

    test('null exitCode returns null hex', () {
      const probe = ModelLoadProbeResult(ran: true, loaded: true);
      expect(probe.exitCodeHex, isNull);
    });
  });

  group('installVariantLabel', () {
    test('returns a non-empty string', () {
      expect(installVariantLabel(), isNotEmpty);
    });
  });
}
