/// EngineRegistry — the engine axis of the engine × model test bench.
///
/// This is the PRD's candidate matrix (a Whisper-alternatives shootout against
/// the mandatory whisper.cpp CPU baseline): Const-me/DirectCompute, ONNX
/// Runtime + DirectML, a non-Whisper wav2vec2 model, plus the whisper.cpp
/// Vulkan / CUDA-12 variants. Each engine wraps the matching candidate from the
/// candidate library and declares the model FAMILY it consumes (ggml vs ONNX),
/// so the live test can offer only compatible models.
///
/// Engine binaries are bundled next to the exe; an engine whose binary is not
/// present surfaces as "nicht verfügbar" — which is exactly the empirical state
/// the tool exists to reveal on hardware like the GTX 650.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'const_me_candidate.dart';
import 'onnx_direct_ml_candidate.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'sherpa_onnx_candidate.dart';
import 'wav2vec2_direct_ml_candidate.dart';
import 'whisper_cpp_candidate.dart';

/// Model families — which catalogue models an engine can consume.
const String familyGgml = 'ggml'; // whisper.cpp + Const-me (GGML .bin)
const String familyOnnxWhisper = 'onnx-whisper'; // ONNX Runtime Whisper-ONNX
const String familyOnnxWav2vec2 = 'onnx-wav2vec2'; // non-Whisper wav2vec2 ONNX
const String familySherpaOnnx = 'sherpa-onnx'; // sherpa-onnx Whisper bundle

/// One selectable engine in the bench: a candidate + its model family +
/// availability (is the engine binary bundled?).
class ProbeEngine {
  ProbeEngine({
    required this.id,
    required this.label,
    required this.backend,
    required this.modelFamily,
    required this.binary,
    required ProbeCandidate Function() builder,
    this.note,
  }) : _builder = builder;

  /// Stable id used in the UI / API.
  final String id;

  /// Human label, e.g. `Const-me · DirectCompute`.
  final String label;

  /// Backend tag, e.g. `directcompute`, `directml`, `cpu`, `vulkan`.
  final String backend;

  /// Model family this engine consumes (one of the `family*` constants).
  final String modelFamily;

  /// Absolute path of the engine binary (bundled next to the exe).
  final String binary;

  /// Optional short note shown in the UI (e.g. why it is a key candidate).
  final String? note;

  final ProbeCandidate Function() _builder;

  /// True when the engine binary is actually present.
  bool get available => isExecutableAvailable(binary);

  /// Builds the candidate that runs this engine on a chosen model.
  ProbeCandidate candidate() => _builder();
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

/// The default PRD engine registry, resolved against bundled binaries in
/// [exeDir]. The whisper.cpp CPU baseline ships bundled; the GPU/alternative
/// engines are detected when their binary is present.
List<ProbeEngine> defaultEngineRegistry({
  required String exeDir,
  ProbeRunner runner = const ProbeRunner(),
}) {
  String bin(String name) =>
      p.join(exeDir, Platform.isWindows ? '$name.exe' : name);
  String sub(String dir, String name) =>
      p.join(exeDir, dir, Platform.isWindows ? '$name.exe' : name);

  return [
    ProbeEngine(
      id: 'whisper-cpp-cpu',
      label: 'whisper.cpp · CPU',
      backend: 'cpu',
      modelFamily: familyGgml,
      binary: bin('whisper'),
      note: 'Pflicht-Baseline (1,0×)',
      builder: () => WhisperCppCandidate(
        id: 'whisper-cpp-cpu',
        binaryName: bin('whisper'),
        backend: 'cpu',
        runner: runner,
      ),
    ),
    ProbeEngine(
      id: 'const-me-directcompute',
      label: 'Const-me · DirectCompute (D3D11)',
      backend: 'directcompute',
      modelFamily: familyGgml,
      binary: sub('const-me', 'main'),
      note: 'Top-Verdächtiger — GGML, umgeht CUDA/Vulkan',
      builder: () => ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: sub('const-me', 'main'),
        modelSizeKey: 'whisper-small',
        // Const-me needs AVX1 + F16C (hybrid also FMA3 + BMI1). The live bench
        // is an explicit user choice, so assume the common modern x64 baseline
        // rather than pre-skipping; if the CPU truly lacks them, Const-me fails
        // and the outcome classifier records it. (Sandy/Ivy/Haswell-Bridge+.)
        cpuFeatures: const {
          cpuFeatureAvx,
          cpuFeatureF16c,
          cpuFeatureFma3,
          cpuFeatureBmi1,
        },
        runner: runner,
      ),
    ),
    ProbeEngine(
      id: 'sherpa-onnx-cpu',
      label: 'sherpa-onnx · Whisper (ONNX, CPU)',
      backend: 'onnx-cpu',
      modelFamily: familySherpaOnnx,
      binary: sub('sherpa-onnx', 'sherpa-onnx-offline'),
      note: 'Top-gepflegte Alternative (k2-fsa) — ONNX Runtime, vendor-neutral',
      builder: () => SherpaOnnxCandidate(
        id: 'sherpa-onnx-cpu',
        binaryName: sub('sherpa-onnx', 'sherpa-onnx-offline'),
        backend: 'onnx-cpu',
        runner: runner,
      ),
    ),
    ProbeEngine(
      id: 'whisper-cpp-vulkan',
      label: 'whisper.cpp · Vulkan',
      backend: 'vulkan',
      modelFamily: familyGgml,
      binary: sub('whisper-vulkan', 'whisper-cli'),
      note: 'Re-Test des Kepler-Hangs (Timeout → hung)',
      builder: () => WhisperCppCandidate(
        id: 'whisper-cpp-vulkan',
        binaryName: sub('whisper-vulkan', 'whisper-cli'),
        backend: 'vulkan',
        runner: runner,
      ),
    ),
    ProbeEngine(
      id: 'whisper-cpp-cuda12',
      label: 'whisper.cpp · CUDA 12',
      backend: 'cuda12',
      modelFamily: familyGgml,
      binary: sub('whisper-cuda12', 'whisper-cli'),
      note: 'Erwarteter Negativfall (Kepler sm_30)',
      builder: () => WhisperCppCandidate(
        id: 'whisper-cpp-cuda12',
        binaryName: sub('whisper-cuda12', 'whisper-cli'),
        backend: 'cuda12',
        runner: runner,
      ),
    ),
    ProbeEngine(
      id: 'onnx-directml',
      label: 'ONNX Runtime · DirectML (Whisper)',
      backend: 'directml',
      modelFamily: familyOnnxWhisper,
      binary: sub('onnx-directml', 'whisper-onnx-directml'),
      note: 'Kepler offiziell unterstützt; medium-Crash-Risiko 887A0006',
      builder: () => OnnxDirectMlCandidate(
        id: 'onnx-directml',
        binaryName: sub('onnx-directml', 'whisper-onnx-directml'),
        runner: runner,
      ),
    ),
    ProbeEngine(
      id: 'wav2vec2-directml-de',
      label: 'wav2vec2 · DirectML (non-Whisper, DE)',
      backend: 'wav2vec2-directml',
      modelFamily: familyOnnxWav2vec2,
      binary: sub('wav2vec2', 'wav2vec2-onnx-directml'),
      note: 'Alternative jenseits von Whisper',
      builder: () => OnnxDirectMlCandidate(
        id: 'wav2vec2-directml-de',
        binaryName: sub('wav2vec2', 'wav2vec2-onnx-directml'),
        backend: 'wav2vec2-directml',
        runner: runner,
        outputParser: parseWav2Vec2Transcript,
      ),
    ),
  ];
}

/// JSON-serialisable engine list for `GET /api/engines` / the report UI.
List<Map<String, Object?>> enginesJson(List<ProbeEngine> engines) => [
  for (final e in engines)
    {
      'id': e.id,
      'label': e.label,
      'backend': e.backend,
      'family': e.modelFamily,
      'available': e.available,
      if (e.note != null) 'note': e.note,
    },
];
