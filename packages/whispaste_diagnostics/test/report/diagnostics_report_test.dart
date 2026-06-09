/// Unit tests for the core diagnostics report formatter.
///
/// Mirrors the app-side `test/features/about/diagnostics_report_test.dart`
/// tests, verifying the formatter works identically from the pure-Dart core.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/analysis/dll_analysis.dart';
import 'package:whispaste_diagnostics/src/analysis/verdict.dart';
import 'package:whispaste_diagnostics/src/probes/av_quarantine_probe.dart';
import 'package:whispaste_diagnostics/src/probes/hardware_probe.dart';
import 'package:whispaste_diagnostics/src/probes/path_service.dart';
import 'package:whispaste_diagnostics/src/probes/permissions_probe.dart';
import 'package:whispaste_diagnostics/src/probes/settings_probe.dart';
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

  group('formatDiagnosticsReport — extended sections (slices 2+3)', () {
    String baseReport({
      String? deviceId,
      HardwareProbeResult? hardware,
      PermissionsProbeResult? permissions,
      AvQuarantineResult? avQuarantine,
      SettingsSnapshotResult? settings,
      bool settingsUnavailable = false,
      VerdictResult? verdict,
      List<String> logTail = const <String>[],
      bool fullLogs = false,
      String executablePath = '/opt/whispaste',
    }) {
      return formatDiagnosticsReport(
        version: '1.2.36',
        variant: 'macos',
        osVersion: 'macos 26.5',
        dartVersion: 'Dart 3.12.1',
        locale: 'de-DE',
        executablePath: executablePath,
        serverPath: '/srv/whisper-server',
        serverExists: true,
        sttFiles: const ['whisper-server'],
        logTail: logTail,
        fullLogs: fullLogs,
        deviceId: deviceId,
        hardware: hardware,
        permissions: permissions,
        avQuarantine: avQuarantine,
        settings: settings,
        settingsUnavailable: settingsUnavailable,
        verdict: verdict,
      );
    }

    test('renders the Sentry device_id', () {
      final report = baseReport(deviceId: 'abc123def456');
      expect(report, contains('Geräte-ID (Sentry): abc123def456'));
    });

    test('renders full hardware with RAM-scarcity marker', () {
      final report = baseReport(
        hardware: const HardwareProbeResult(
          ramTotalMb: 4096,
          ramFreeMb: 1024,
          ramScarce: true,
          cpuModel: 'Apple M5',
          cpuCores: 10,
          gpuName: 'Apple M5',
          gpuVramMb: 16384,
          diskFreeMb: 250000,
        ),
      );
      expect(report, contains('RAM: 4096 MB gesamt'));
      expect(report, contains('1024 MB frei'));
      expect(report, contains('knapp')); // §6.6 scarcity marker
      expect(report, contains('CPU: Apple M5 (10 Kerne)'));
      expect(report, contains('Freier Speicher: 250000 MB'));
    });

    test('renders permissions incl. stale-TCC', () {
      final report = baseReport(
        permissions: const PermissionsProbeResult(
          macosAccessibilityGranted: false,
          macosAccessibilityStale: true,
          macosAppleEventsGranted: true,
          macosAppleEventsStale: false,
          macosMicGranted: true,
          windowsMicAllowed: null,
        ),
      );
      expect(report, contains('Berechtigungen:'));
      expect(report, contains('Accessibility'));
      expect(report, contains('stale')); // stale-TCC surfaced
    });

    test('permissions section notes when nothing could be determined', () {
      final report = baseReport(
        permissions: const PermissionsProbeResult(
          macosAccessibilityGranted: null,
          macosAccessibilityStale: null,
          macosAppleEventsGranted: null,
          macosAppleEventsStale: null,
          macosMicGranted: null,
          windowsMicAllowed: null,
        ),
      );
      expect(report, contains('Berechtigungen:'));
      expect(report, contains('nicht ermittelbar'));
    });

    test('renders AV-quarantine status', () {
      final report = baseReport(
        avQuarantine: const AvQuarantineResult(
          binaryPath: '/srv/whisper-server',
          binaryExists: true,
          quarantined: true,
          detail: 'com.apple.quarantine present',
        ),
      );
      expect(report, contains('AV/Quarantäne:'));
      expect(report, contains('Quarantäne'));
    });

    test('renders verdict with primary fingerprint when unhealthy', () {
      final verdict = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: <String>[],
          vcRuntimeMissing: false,
        ),
        ramScarce: true,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      final report = baseReport(verdict: verdict);
      expect(report, contains('Bewertung:'));
      expect(report, contains('stt-exit-other')); // RAM-scarce fingerprint
    });

    test('renders healthy verdict when no suspicions', () {
      final verdict = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: <String>[],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      final report = baseReport(verdict: verdict);
      expect(report, contains('Bewertung:'));
      expect(report, contains('keine Auffälligkeiten'));
    });

    test('notes settings unavailable in standalone mode', () {
      final report = baseReport(settingsUnavailable: true);
      expect(report, contains('Einstellungen:'));
      expect(report, contains('Standalone'));
    });

    test('uses a full-log header when fullLogs is set', () {
      final report = baseReport(
        logTail: const ['line A', 'line B'],
        fullLogs: true,
      );
      expect(report, isNot(contains('letzte 2 Logzeilen')));
      expect(report, contains('Logzeilen'));
    });

    test('sanitizes the whole report (§6.5) — no raw home path leaks', () {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      // Skip on the rare CI runner with no HOME/USERPROFILE set.
      if (home == null || home.isEmpty) return;
      final report = baseReport(executablePath: '$home/tools/whispaste');
      expect(report, isNot(contains(home)));
      expect(report, contains('<home>/tools/whispaste'));
    });
  });

  // -------------------------------------------------------------------------
  // gatherDiagnosticsReport — MSIX standalone-fallback wiring (Slice 1)
  //
  // Drives the Windows-only MSIX-fallback branch cross-platform via the
  // gatherer test seams (gatherIsWindowsOverride, gatherMsixDataRootResolver-
  // Override) plus sttDirOverride. Asserts observable behaviour through the
  // public gatherDiagnosticsReport interface:
  //   - the effective STT directory's files are listed in the report (AC1)
  //   - the variant label is 'Microsoft Store / MSIX' on fallback (AC4)
  //   - no fallback when the regular STT dir exists, or when the resolver
  //     returns null (AC2)
  // -------------------------------------------------------------------------
  group('gatherDiagnosticsReport — MSIX standalone-fallback wiring', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wd_msix_gather_');
    });

    tearDown(() {
      // Reset all seams so no state leaks between tests (S2).
      gatherIsWindowsOverride = null;
      gatherMsixDataRootResolverOverride = null;
      sttDirOverride = null;
      localAppDataOverride = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Builds a fake MSIX data root with `models/stt` containing a distinctive
    /// marker file, and returns the root path.
    String buildMsixRootWithStt() {
      final root = p.join(tmp.path, 'LocalCache', 'Roaming', 'WhisPaste');
      final stt = Directory(p.join(root, 'models', 'stt'))
        ..createSync(recursive: true);
      File(p.join(stt.path, 'ggml-msix-marker.bin')).writeAsStringSync('x');
      return root;
    }

    test('AC1+AC4: regular STT dir absent + resolver yields a root → effective '
        'STT dir is used AND variant is Microsoft Store / MSIX', () async {
      // regularSttDir points at a non-existent path → fallback path taken.
      sttDirOverride = p.join(tmp.path, 'does-not-exist', 'models', 'stt');
      gatherIsWindowsOverride = true;
      final msixRoot = buildMsixRootWithStt();
      gatherMsixDataRootResolverOverride = () => msixRoot;

      final report = await gatherDiagnosticsReport();

      // AC1: the marker file living under the MSIX models/stt is reported.
      expect(report, contains('ggml-msix-marker.bin'));
      // AC4: the detected variant is the Store / MSIX build.
      expect(report, contains('(Microsoft Store / MSIX)'));
    });

    test('AC2: regular STT dir present → fallback skipped, resolver not used, '
        'variant stays the host installVariantLabel()', () async {
      // A real, existing STT dir → regularExists == true → no fallback.
      final realStt = Directory(p.join(tmp.path, 'real', 'models', 'stt'))
        ..createSync(recursive: true);
      File(
        p.join(realStt.path, 'ggml-real-install.bin'),
      ).writeAsStringSync('y');
      sttDirOverride = realStt.path;
      gatherIsWindowsOverride = true;

      // Resolver would point at the MSIX marker root — but must NOT be called.
      var resolverCalled = false;
      gatherMsixDataRootResolverOverride = () {
        resolverCalled = true;
        return buildMsixRootWithStt();
      };

      final report = await gatherDiagnosticsReport();

      expect(resolverCalled, isFalse);
      // The real install's files are reported, not the MSIX marker.
      expect(report, contains('ggml-real-install.bin'));
      expect(report, isNot(contains('ggml-msix-marker.bin')));
      // No MSIX override → variant is the host label (e.g. 'macos' off-Windows).
      expect(report, isNot(contains('(Microsoft Store / MSIX)')));
      expect(report, contains('(${installVariantLabel()})'));
    });

    test(
      'AC2-edge: regular STT dir absent + resolver yields null → no fallback, '
      'nominal path retained, variant stays installVariantLabel()',
      () async {
        sttDirOverride = p.join(tmp.path, 'empty', 'models', 'stt');
        gatherIsWindowsOverride = true;
        var resolverCalled = false;
        gatherMsixDataRootResolverOverride = () {
          resolverCalled = true;
          return null; // no MSIX install discovered
        };

        final report = await gatherDiagnosticsReport();

        expect(resolverCalled, isTrue);
        expect(report, isNot(contains('ggml-msix-marker.bin')));
        expect(report, isNot(contains('(Microsoft Store / MSIX)')));
        expect(report, contains('(${installVariantLabel()})'));
      },
    );
  });
}
