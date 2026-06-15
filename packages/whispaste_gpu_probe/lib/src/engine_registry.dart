/// EngineRegistry — the engine axis of the engine × model test bench.
///
/// An "engine" is a whisper.cpp backend (CPU / Vulkan / CUDA …) identified by
/// its binary. The CPU engine is bundled with the tool (an absolute path that
/// exists → available); GPU engines are detected on PATH and surface as
/// "nicht verfügbar" when their binary is absent — which is the honest probe
/// result on hardware without that backend.
///
/// Every engine consumes the same ggml model catalogue from [ModelStore], so
/// the live test is a clean engine × model matrix.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'probe_runner.dart';
import 'whisper_cpp_candidate.dart';

/// One selectable engine backed by a whisper.cpp binary.
class ProbeEngine {
  const ProbeEngine({
    required this.id,
    required this.label,
    required this.backend,
    required this.binary,
    this.runner = const ProbeRunner(),
  });

  /// Stable id used in the UI / API (e.g. `whisper-cpp-cpu`).
  final String id;

  /// Human label (e.g. `whisper.cpp · CPU`).
  final String label;

  /// Backend tag stored on results (`cpu`, `vulkan`, `cuda12`).
  final String backend;

  /// Binary: an absolute path (bundled) or a bare name resolved on PATH.
  final String binary;

  /// Injectable runner (production default; override in tests).
  final ProbeRunner runner;

  /// True when the binary is actually present (abs path exists, or bare name
  /// found on PATH).
  bool get available => isExecutableAvailable(binary);

  /// Builds the [WhisperCppCandidate] that runs this engine.
  WhisperCppCandidate candidate() => WhisperCppCandidate(
    id: id,
    binaryName: binary,
    backend: backend,
    runner: runner,
  );
}

/// True when [binary] can be launched: an absolute path that exists, or a bare
/// name found in a PATH directory (with platform executable extensions).
bool isExecutableAvailable(String binary) {
  if (binary.isEmpty) return false;
  if (p.isAbsolute(binary)) return File(binary).existsSync();
  final pathVar = Platform.environment['PATH'] ?? '';
  final sep = Platform.isWindows ? ';' : ':';
  final exts = Platform.isWindows
      ? const ['.exe', '.bat', '.cmd', '']
      : const [''];
  for (final dir in pathVar.split(sep)) {
    if (dir.isEmpty) continue;
    for (final ext in exts) {
      if (File(p.join(dir, '$binary$ext')).existsSync()) return true;
    }
  }
  return false;
}

/// The default whisper.cpp engine registry.
///
/// [cpuBinary] is the bundled CPU binary path (absolute, next to the exe);
/// the GPU engines are bare names looked up on PATH.
List<ProbeEngine> defaultEngineRegistry({
  required String cpuBinary,
  ProbeRunner runner = const ProbeRunner(),
}) => [
  ProbeEngine(
    id: 'whisper-cpp-cpu',
    label: 'whisper.cpp · CPU',
    backend: 'cpu',
    binary: cpuBinary,
    runner: runner,
  ),
  ProbeEngine(
    id: 'whisper-cpp-vulkan',
    label: 'whisper.cpp · Vulkan (GPU)',
    backend: 'vulkan',
    binary: 'whisper-vulkan',
    runner: runner,
  ),
  ProbeEngine(
    id: 'whisper-cpp-cuda12',
    label: 'whisper.cpp · CUDA 12 (GPU)',
    backend: 'cuda12',
    binary: 'whisper-cuda12',
    runner: runner,
  ),
];

/// JSON-serialisable engine list for `GET /api/engines` / the report UI.
List<Map<String, Object?>> enginesJson(List<ProbeEngine> engines) => [
  for (final e in engines)
    {
      'id': e.id,
      'label': e.label,
      'backend': e.backend,
      'available': e.available,
    },
];
