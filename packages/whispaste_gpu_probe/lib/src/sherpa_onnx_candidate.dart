/// ProbeCandidate for sherpa-onnx (k2-fsa) running an offline Whisper-ONNX
/// model via the `sherpa-onnx-offline` CLI.
///
/// sherpa-onnx is one of the best-maintained open ONNX-Runtime STT toolkits;
/// the prebuilt Windows `sherpa-onnx-offline.exe` uses the CPU execution
/// provider out of the box, which makes it a clean, reliably-deployable
/// alternative for beta testers regardless of GPU vendor. (CUDA / DirectML
/// builds exist as separate downloads and can be added as further engines.)
///
/// ## Model layout
///
/// Unlike the single-file GGML models, a sherpa-onnx Whisper model is a small
/// BUNDLE of files in one directory: an encoder ONNX, a decoder ONNX, and a
/// tokens table. The [ModelStore] downloads the bundle into `models/<id>/` and
/// hands that directory to this candidate as [ProbeContext.modelPath]; we
/// resolve the three files inside it (preferring the int8 variants).
///
/// ## Command line
///
/// ```
/// sherpa-onnx-offline \
///   --whisper-encoder=<dir>/<x>-encoder.int8.onnx \
///   --whisper-decoder=<dir>/<x>-decoder.int8.onnx \
///   --tokens=<dir>/<x>-tokens.txt \
///   --whisper-language=de --whisper-task=transcribe \
///   --num-threads=<n> <wav>
/// ```
///
/// The Kaldi-style option parser only accepts the `--flag=value` form (no
/// space-separated values), so every flag is joined with `=`.
///
/// ## Output format
///
/// `sherpa-onnx-offline` prints the input filename followed by a single JSON
/// result line on stdout:
///
///   `{"text":" Guten Tag, das ist ein Test.","timestamps":[...],"tokens":[...]}`
///
/// [parseSherpaOnnxTranscript] scans the captured stdout from the end for the
/// JSON object carrying a `"text"` field and returns its trimmed value.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'outcome_classifier.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'wer.dart';

// ---------------------------------------------------------------------------
// Model-file resolution
// ---------------------------------------------------------------------------

/// The three files a sherpa-onnx Whisper run needs, resolved inside a bundle
/// directory.
class SherpaModelFiles {
  const SherpaModelFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  /// Absolute path of the encoder ONNX file.
  final String encoder;

  /// Absolute path of the decoder ONNX file.
  final String decoder;

  /// Absolute path of the tokens table.
  final String tokens;
}

/// Resolves the encoder/decoder/tokens files inside the bundle directory [dir].
///
/// Matches by filename substring (`encoder`/`decoder` + `.onnx`, `tokens` +
/// `.txt`) so it is robust to the model-size prefix (`base-encoder…`,
/// `medium-encoder…`). When both an int8 and a full-precision variant are
/// present, the int8 file is preferred (smaller, what the catalogue ships).
///
/// Returns null when the directory is missing or any of the three files cannot
/// be found.
SherpaModelFiles? resolveSherpaModelFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return null;

  String? encoder;
  String? decoder;
  String? tokens;
  for (final f in d.listSync().whereType<File>()) {
    final name = p.basename(f.path).toLowerCase();
    final isInt8 = name.contains('int8');
    if (name.endsWith('.onnx') && name.contains('encoder')) {
      if (encoder == null || isInt8) encoder = f.path;
    } else if (name.endsWith('.onnx') && name.contains('decoder')) {
      if (decoder == null || isInt8) decoder = f.path;
    } else if (name.endsWith('.txt') && name.contains('tokens')) {
      tokens ??= f.path;
    }
  }
  if (encoder == null || decoder == null || tokens == null) return null;
  return SherpaModelFiles(encoder: encoder, decoder: decoder, tokens: tokens);
}

// ---------------------------------------------------------------------------
// Transcript parser
// ---------------------------------------------------------------------------

/// Parses `sherpa-onnx-offline` stdout and returns the transcript text.
///
/// Scans [stdout] from the end for a JSON object line carrying a `"text"`
/// field (the recognition result) and returns its trimmed value. Returns an
/// empty string when no such line is present.
String parseSherpaOnnxTranscript(List<String> stdout) {
  for (final line in stdout.reversed) {
    final t = line.trim();
    if (!t.startsWith('{') || !t.contains('"text"')) continue;
    try {
      final obj = jsonDecode(t);
      if (obj is Map && obj['text'] is String) {
        final text = (obj['text'] as String).trim();
        if (text.isNotEmpty) return text;
      }
    } on FormatException {
      // Not the JSON result line — keep scanning.
    }
  }
  return '';
}

// ---------------------------------------------------------------------------
// SherpaOnnxCandidate
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that runs `sherpa-onnx-offline` on a Whisper-ONNX bundle.
class SherpaOnnxCandidate implements ProbeCandidate {
  const SherpaOnnxCandidate({
    required this.id,
    required this.binaryName,
    this.backend = 'onnx-cpu',
    this.provider = 'cpu',
    this.runner = const ProbeRunner(),
    this.referenceTranscript,
    this.numThreads = 4,
  });

  @override
  final String id;

  /// Executable path / name (`sherpa-onnx-offline[.exe]`).
  final String binaryName;

  /// Backend label stored in [CandidateResult.backend].
  final String backend;

  /// ONNX Runtime execution provider passed via `--provider`
  /// (`cpu`, `cuda`, `directml`, …). `cuda` requires a CUDA-enabled sherpa
  /// build + a supported NVIDIA GPU; it falls back / fails otherwise.
  final String provider;

  /// Injectable runner (production default; override in tests).
  final ProbeRunner runner;

  /// Optional soll-transcript for WER computation.
  final String? referenceTranscript;

  /// Threads passed to `--num-threads`.
  final int numThreads;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    // ctx.modelPath is the bundle directory; resolve the three model files.
    final files = resolveSherpaModelFiles(ctx.modelPath);
    if (files == null) {
      return CandidateResult(
        candidateId: id,
        outcome: Outcome.skipped,
        errorDetail:
            'sherpa-onnx-Modelldateien (encoder/decoder/tokens) nicht '
            'gefunden in "${ctx.modelPath}".',
        backend: backend,
      );
    }

    final stdoutLines = <String>[];
    final capturingRunner = ProbeRunner(
      launcher: _makeCaptureWrapper(runner.launcher, stdoutLines),
      startupDeadline: runner.startupDeadline,
      heartbeatTimeout: runner.heartbeatTimeout,
      stderrTailLines: runner.stderrTailLines,
    );

    final runResult = await capturingRunner.run(
      executable: binaryName,
      arguments: [
        '--whisper-encoder=${files.encoder}',
        '--whisper-decoder=${files.decoder}',
        '--tokens=${files.tokens}',
        '--provider=$provider',
        '--whisper-language=${ctx.language}',
        '--whisper-task=transcribe',
        '--num-threads=$numThreads',
        ctx.referenceWavPath,
      ],
      workingDirectory: ctx.workDir,
    );

    // Binary not found → launcher threw → exitCode is null, not timed out.
    if (runResult.exitCode == null && !runResult.timedOut) {
      return CandidateResult(
        candidateId: id,
        outcome: Outcome.skipped,
        durationMs: runResult.durationMs,
        errorDetail: 'Binary "$binaryName" nicht gefunden oder nicht startbar.',
        backend: backend,
      );
    }

    final transcript = parseSherpaOnnxTranscript(stdoutLines);

    double? wer;
    if (referenceTranscript != null && referenceTranscript!.isNotEmpty) {
      wer = computeWer(transcript, referenceTranscript!);
    }

    final outcome = classifyOutcome(
      exitCode: runResult.exitCode,
      timedOut: runResult.timedOut,
      transcript: transcript,
      detectedLanguage: null,
      expectedLanguage: ctx.language,
      wer: wer,
    );

    String? errorDetail;
    if (outcome != Outcome.ok) {
      if (runResult.timedOut) {
        errorDetail = 'Prozess überschritt Deadline und wurde beendet.';
      } else if (runResult.exitCode != null && runResult.exitCode != 0) {
        errorDetail =
            'Prozess beendete sich mit Exit-Code ${runResult.exitCode}.';
      }
    }

    return CandidateResult(
      candidateId: id,
      outcome: outcome,
      durationMs: runResult.durationMs,
      transcribedText: transcript.isEmpty ? null : transcript,
      errorDetail: errorDetail,
      exitCode: runResult.exitCode,
      stderrTail: runResult.stderrTail.isEmpty ? null : runResult.stderrTail,
      wer: wer,
      backend: backend,
    );
  }

  /// Tees the single-subscription stdout into a broadcast stream so both the
  /// capture list and [ProbeRunner]'s heartbeat listener can subscribe.
  /// Mirrors [WhisperCppCandidate] / [OnnxDirectMlCandidate].
  ProcessLauncher _makeCaptureWrapper(
    ProcessLauncher base,
    List<String> capture,
  ) {
    return (executable, arguments, workingDirectory) async {
      final result = await base(executable, arguments, workingDirectory);
      final teeCtrl = StreamController<String>.broadcast();
      result.stdout.listen(
        teeCtrl.add,
        onError: teeCtrl.addError,
        onDone: teeCtrl.close,
      );
      teeCtrl.stream.listen(capture.add);
      return ProcessStartResult(
        process: result.process,
        stdout: teeCtrl.stream,
        stderr: result.stderr,
      );
    };
  }
}
