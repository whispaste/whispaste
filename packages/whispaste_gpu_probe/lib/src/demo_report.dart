/// Demo report builder for `--demo` CLI mode.
///
/// Provides a representative synthetic [ProbeReport] that shows every possible
/// outcome across a realistic GPU/CPU candidate mix so the HTML report can be
/// previewed without running real engines.
library;

import 'probe_types.dart';

/// Builds a representative synthetic [ProbeReport] for demo / preview use.
///
/// Candidates:
/// - `whisper-cpp-cpu` (cpu, small) — ok, baseline ~48 s
/// - `const-me-directcompute` (directml, small) — ok, ~8 s → ~6× (WINNER)
/// - `wav2vec2-directml-de` (directml, small) — ok, ~12 s → ~4×
/// - `onnx-directml` (directml, small) — ok, ~15 s → ~3.2×
/// - `whisper-cpp-vulkan` (vulkan, small) — hung (timedOut)
/// - `whisper-cpp-cuda12` (cuda12, small) — crashed, CUDA error
/// - `whisper-cpp-cpu-medium` (cpu, medium) — skipped, VRAM budget exceeded
ProbeReport buildDemoReport() {
  final hw = HardwareContext(
    gpuModel: 'NVIDIA GeForce GTX 650',
    vramGb: 1,
    cpuModel: 'Intel Core i5-1145G7',
    ramGb: 16,
    os: 'Windows 11 Pro (Build 26200)',
    driverVersion: '342.01',
  );

  const results = <CandidateResult>[
    CandidateResult(
      candidateId: 'whisper-cpp-cpu',
      outcome: Outcome.ok,
      durationMs: 48000,
      wer: 0.07,
      realtimeFactor: 0.5,
      backend: 'cpu',
      modelId: 'small',
      transcribedText: 'Bitte transkribiere diesen Satz schnell und korrekt.',
    ),
    CandidateResult(
      candidateId: 'const-me-directcompute',
      outcome: Outcome.ok,
      durationMs: 8000,
      wer: 0.08,
      realtimeFactor: 0.083,
      backend: 'directml',
      modelId: 'small',
      transcribedText: 'Bitte transkribiere diesen Satz schnell und korrekt.',
    ),
    CandidateResult(
      candidateId: 'wav2vec2-directml-de',
      outcome: Outcome.ok,
      durationMs: 12000,
      wer: 0.18,
      realtimeFactor: 0.125,
      backend: 'directml',
      modelId: 'small',
      transcribedText: 'bitte transkribiere diesen satz schnel und korekt',
    ),
    CandidateResult(
      candidateId: 'onnx-directml',
      outcome: Outcome.ok,
      durationMs: 15000,
      wer: 0.11,
      realtimeFactor: 0.156,
      backend: 'directml',
      modelId: 'small',
      transcribedText: 'Bitte transkribiere diesen Satz schnell und korrekt.',
    ),
    CandidateResult(
      candidateId: 'whisper-cpp-vulkan',
      outcome: Outcome.hung,
      errorDetail: 'timedOut',
      backend: 'vulkan',
      modelId: 'small',
    ),
    CandidateResult(
      candidateId: 'whisper-cpp-cuda12',
      outcome: Outcome.crashed,
      exitCode: 1,
      stderrTail:
          'CUDA error: no kernel image is available for execution on the device (sm_30)',
      errorDetail: 'exit code 1',
      backend: 'cuda12',
      modelId: 'small',
    ),
    CandidateResult(
      candidateId: 'whisper-cpp-cpu-medium',
      outcome: Outcome.skipped,
      errorDetail:
          'Modell medium (~1,5 GB) überschreitet VRAM-Budget (1024 MB)',
      backend: 'cpu',
      modelId: 'medium',
    ),
  ];

  return ProbeReport(
    timestamp: DateTime.now().toUtc(),
    results: results,
    version: const String.fromEnvironment(
      'whispaste_version',
      defaultValue: 'demo',
    ),
    hardwareContext: hw,
  );
}
