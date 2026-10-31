/// The "Letztes Diktat" block: how the most recent dictation was processed
/// (CPU, GPU or cloud), whether a GPU run fell back to the CPU, and how long
/// the transcription took. Pure rules and the stored form only; the pipeline
/// records it and the page reads it.
library;

/// Where the transcription of a dictation ran.
enum DictationProcessing { cpu, gpu, cloud }

/// The last dictation as the overview shows it.
class LastDictation {
  const LastDictation({
    required this.processing,
    required this.fellBack,
    required this.processingMs,
  });

  final DictationProcessing processing;

  /// The GPU was wanted, but the dictation ran on the CPU.
  final bool fellBack;

  /// Transcription time in milliseconds, without the speaking time.
  final int processingMs;

  /// Stored form, `v1|<processing>|<0/1>|<ms>`. Unknown or damaged values
  /// decode to `null`, so the block simply shows nothing.
  String encode() =>
      ['v1', processing.name, fellBack ? '1' : '0', processingMs].join('|');

  static LastDictation? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 4 || parts[0] != 'v1') return null;
    DictationProcessing? processing;
    for (final value in DictationProcessing.values) {
      if (value.name == parts[1]) processing = value;
    }
    final ms = int.tryParse(parts[3]);
    if (processing == null || ms == null || ms < 0) return null;
    return LastDictation(
      processing: processing,
      fellBack: parts[2] == '1',
      processingMs: ms,
    );
  }
}

/// Whether a Whisper run wants the GPU: the hardware offers a GPU backend and
/// the GPU setting allows it. [optimalBackend] is the detected backend name.
bool whisperGpuWanted({
  required String? optimalBackend,
  required String? gpuAcceleration,
}) {
  final hasGpu = switch (optimalBackend) {
    'cuda' || 'metal' || 'vulkan' => true,
    _ => false,
  };
  return hasGpu && (gpuAcceleration ?? 'auto') != 'disabled';
}

/// Processing of a local dictation. A fallback is a GPU that was wanted but
/// is not the one serving the request.
({DictationProcessing processing, bool fellBack}) resolveLocalProcessing({
  required bool gpuWanted,
  required bool gpuActive,
}) => (
  processing: gpuActive ? DictationProcessing.gpu : DictationProcessing.cpu,
  fellBack: gpuWanted && !gpuActive,
);
