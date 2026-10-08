/// `whispaste --diagnose`: a start probe for installed release packages.
///
/// The release workflow's package smoke tests (`scripts/smoke/`) install or
/// unpack each artifact and start it with `--diagnose`. Reaching Dart's
/// `main()` already proves that the runner, the Flutter engine and the AOT
/// snapshot load; this then opens every bundled native engine library (and
/// looks up one entry point each), so a package with a missing or
/// unresolvable `.so`/`.dll`/`.dylib` fails before it is published.
///
/// Like `--transcribe-file` it runs before crash reporting, the
/// single-instance guard and any window/UI setup, and touches no settings,
/// permissions (macOS TCC) or user data.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import '../../core/app_info.dart' show appVersion;
import '../../core/utils/windows_dll_search_path.dart';
import '../smart_mode/smart_mode_ffi_engine.dart' show smartModeLibraryPathFor;
import '../stt/whisper/whisper_ffi_engine.dart'
    show WhisperFfiEngine, whisperLibraryPathFor;

/// Usage text printed for an invalid `--diagnose` command line.
const String packageDiagnoseUsage = '''
Usage: whispaste --diagnose [--out <file>]

Checks that the installed app starts and its bundled native libraries load,
prints a JSON report and exits 0 (ok) or 1 (a library failed to load).
  --out <file>  also write the JSON report to <file>
''';

/// Parsed `--diagnose` command line.
class PackageDiagnoseOptions {
  const PackageDiagnoseOptions({this.outPath});

  final String? outPath;

  static bool isRequested(List<String> args) => args.contains('--diagnose');

  /// Parses [args]; throws [FormatException] with a user-facing message.
  static PackageDiagnoseOptions parse(List<String> args) {
    String? outPath;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--diagnose':
          break;
        case '--out':
          if (i + 1 >= args.length) {
            throw const FormatException('--out needs a file path');
          }
          outPath = args[++i];
        default:
          throw FormatException('unknown option ${args[i]}');
      }
    }
    return PackageDiagnoseOptions(outPath: outPath);
  }
}

/// A native library the app bundles, plus entry points it must export.
class NativeLibrary {
  const NativeLibrary({
    required this.name,
    required this.path,
    required this.symbols,
    this.checksCpuBackend = false,
  });

  final String name;
  final String path;
  final List<String> symbols;

  /// Whether ggml must register a CPU backend from this library's directory.
  /// Windows and Linux builds load the `ggml-cpu-<level>` modules at runtime
  /// (`-DGGML_BACKEND_DL=ON`), so a package missing them still opens
  /// libwhisper fine and only aborts on the first transcription.
  final bool checksCpuBackend;
}

/// The engine libraries bundled next to [executablePath], resolved exactly
/// like the engines resolve them at runtime.
List<NativeLibrary> bundledNativeLibraries(String executablePath) => [
  NativeLibrary(
    name: 'whisper',
    path: whisperLibraryPathFor(executablePath),
    symbols: const ['whisper_full'],
    checksCpuBackend: !Platform.isMacOS,
  ),
  NativeLibrary(
    name: 'smart_mode_shim',
    path: smartModeLibraryPathFor(executablePath),
    symbols: const ['smart_mode_load'],
  ),
];

/// Opens [library] and looks up its [NativeLibrary.symbols]; throws when the
/// library or one of its dependencies cannot be loaded. For a library that
/// [NativeLibrary.checksCpuBackend], returns the loaded CPU backend's
/// features (`null` = none registered).
String? probeNativeLibrary(NativeLibrary library) {
  ensureWindowsDllSearchPath(library.path);
  final dylib = ffi.DynamicLibrary.open(library.path);
  for (final symbol in library.symbols) {
    if (!dylib.providesSymbol(symbol)) {
      throw StateError('${library.path} does not export $symbol');
    }
  }
  if (!library.checksCpuBackend) return null;
  return WhisperFfiEngine.probeCpuBackend(dylib, library.path);
}

/// Outcome of probing one [NativeLibrary]; [error] is null on success.
class NativeLibraryResult {
  const NativeLibraryResult(this.library, this.error, {this.cpuBackend});

  final NativeLibrary library;
  final String? error;

  /// Features of the ggml CPU backend variant loaded for [library].
  final String? cpuBackend;

  bool get ok => error == null;

  Map<String, Object?> toJson() => {
    'name': library.name,
    'path': library.path,
    'ok': ok,
    if (cpuBackend != null) 'cpuBackend': cpuBackend,
    if (error != null) 'error': error,
  };
}

/// Result of [runPackageDiagnose].
class PackageDiagnoseReport {
  const PackageDiagnoseReport({
    required this.version,
    required this.executable,
    required this.libraries,
  });

  final String version;
  final String executable;
  final List<NativeLibraryResult> libraries;

  bool get ok => libraries.every((l) => l.ok);

  Map<String, Object?> toJson() => {
    'ok': ok,
    'version': version,
    'os': Platform.operatingSystem,
    'executable': executable,
    'libraries': [for (final l in libraries) l.toJson()],
  };
}

/// Probes every library in [libraries] with [probe], collecting each failure
/// instead of stopping at the first one.
PackageDiagnoseReport runPackageDiagnose({
  required List<NativeLibrary> libraries,
  required String version,
  required String executable,
  String? Function(NativeLibrary library) probe = probeNativeLibrary,
}) {
  final results = <NativeLibraryResult>[];
  for (final library in libraries) {
    String? error;
    String? cpuBackend;
    try {
      cpuBackend = probe(library);
      if (library.checksCpuBackend && cpuBackend == null) {
        error = 'no ggml CPU backend registered from ${library.path}';
      }
    } on Object catch (e) {
      error = '$e';
    }
    results.add(NativeLibraryResult(library, error, cpuBackend: cpuBackend));
  }
  return PackageDiagnoseReport(
    version: version,
    executable: executable,
    libraries: results,
  );
}

/// Exit code for an invalid command line (BSD `EX_USAGE`).
const int _exitUsage = 64;

/// Runs `--diagnose` for [args] and returns the process exit code.
Future<int> runPackageDiagnoseCli(List<String> args) async {
  final PackageDiagnoseOptions options;
  try {
    options = PackageDiagnoseOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('whispaste: ${e.message}\n\n$packageDiagnoseUsage');
    return _exitUsage;
  }
  final executable = Platform.resolvedExecutable;
  final report = runPackageDiagnose(
    libraries: bundledNativeLibraries(executable),
    version: appVersion,
    executable: executable,
  );
  final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
  if (options.outPath case final path?) {
    await File(path).writeAsString('$json\n');
  }
  stdout.writeln(json);
  await stdout.flush();
  return report.ok ? 0 : 1;
}
