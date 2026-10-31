/// ProbeCandidate for faster-whisper / CTranslate2 via Purfview's standalone
/// `whisper-faster.exe` (a.k.a. Faster-Whisper-XXL) Windows build.
///
/// faster-whisper runs Whisper on the CTranslate2 inference engine — among the
/// fastest and best-maintained CPU/CUDA Whisper implementations. Purfview ships
/// a prebuilt, self-contained Windows binary (no Python), which makes it a clean
/// alternative to bundle for beta testers: the CPU path runs everywhere, and the
/// XXL build additionally bundles the CUDA runtime (unlike sherpa-cuda, which
/// needs an external CUDA Toolkit), so the GPU path is self-contained on modern
/// NVIDIA.
///
/// ## Model layout
///
/// Like sherpa-onnx, a CTranslate2 Whisper model is a small BUNDLE of files in
/// one directory: `model.bin`, `config.json`, `tokenizer.json`, `vocabulary.txt`.
/// The [ModelStore] downloads the bundle into `models/<id>/` and hands that
/// directory to this candidate as [ProbeContext.modelPath]; `--model <dir>`
/// loads the converted model straight from there.
///
/// ## Command line
///
/// Purfview's `--model` takes a model NAME (not a path) and looks the bundle up
/// as `<model_dir>/faster-whisper-<name>`. The [ModelStore] therefore stores the
/// bundle in a directory named `faster-whisper-<size>`; this candidate derives
/// the name + parent from [ProbeContext.modelPath]:
///
/// ```
/// whisper-faster.exe <wav> \
///   --model <size> --model_dir <parent-of-bundle> \
///   --language de --device cpu --compute_type int8 \
///   --output_format txt --output_dir <workdir> --beep_off
/// ```
///
/// ## Output format
///
/// `whisper-faster.exe` writes the transcript to `<workdir>/<wav-stem>.txt` as
/// timestamped segment lines (same bracket form as whisper.cpp):
///
///   `[00:00.000 --> 00:02.020]  Das Wetter heute ist sonnig und warm.`
///
/// We read that file (authoritative — stdout also carries progress noise) and
/// strip the timestamp prefix per line; if the file is missing we fall back to
/// parsing captured stdout.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'outcome_classifier.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'wer.dart';

// ---------------------------------------------------------------------------
// Transcript parser
// ---------------------------------------------------------------------------

/// Parses faster-whisper transcript [lines] (from the output `.txt` or stdout)
/// and returns the joined text.
///
/// Each segment line looks like `[00:00.000 --> 00:02.020]  text`; the optional
/// leading timestamp block is stripped. Plain lines (no bracket) are taken
/// verbatim. Blank lines are ignored.
String parseFasterWhisperTranscript(List<String> lines) {
  // A leading [..timestamps..] block: digits, colons, dots, spaces, '-', '>'.
  final segment = RegExp(r'^\[[\d:.\s\->]+\]\s*(.*)$');
  final out = <String>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = segment.firstMatch(line);
    final text = (m != null ? m.group(1)! : line).trim();
    if (text.isNotEmpty) out.add(text);
  }
  return out.join(' ');
}

// ---------------------------------------------------------------------------
// FasterWhisperCandidate
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that runs Purfview's `whisper-faster.exe` on a CTranslate2
/// Whisper model bundle.
class FasterWhisperCandidate implements ProbeCandidate {
  const FasterWhisperCandidate({
    required this.id,
    required this.binaryName,
    this.backend = 'ct2-cpu',
    this.device = 'cpu',
    this.computeType = 'int8',
    this.runner = const ProbeRunner(),
    this.referenceTranscript,
  });

  @override
  final String id;

  /// Executable path / name (`whisper-faster.exe` / `faster-whisper-xxl.exe`).
  final String binaryName;

  /// Backend label stored in [CandidateResult.backend].
  final String backend;

  /// CTranslate2 device passed via `--device` (`cpu` or `cuda`). `cuda` needs a
  /// CUDA-enabled build + a supported NVIDIA GPU; it fails otherwise.
  final String device;

  /// CTranslate2 compute type passed via `--compute_type` (`int8` on CPU,
  /// `int8_float16` on CUDA are good defaults).
  final String computeType;

  /// Injectable runner (production default; override in tests).
  final ProbeRunner runner;

  /// Optional soll-transcript for WER computation.
  final String? referenceTranscript;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    // ctx.modelPath is the CT2 bundle directory.
    if (!Directory(ctx.modelPath).existsSync()) {
      return CandidateResult(
        candidateId: id,
        outcome: Outcome.skipped,
        errorDetail:
            'CTranslate2-Modellverzeichnis nicht gefunden: "${ctx.modelPath}".',
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

    // `--model` is a NAME; the tool resolves <model_dir>/faster-whisper-<name>.
    // Our bundle dir is named `faster-whisper-<size>`, so split it back apart.
    final modelDirName = p.basename(ctx.modelPath);
    final modelName = modelDirName.startsWith('faster-whisper-')
        ? modelDirName.substring('faster-whisper-'.length)
        : modelDirName;
    final modelParent = p.dirname(ctx.modelPath);

    final runResult = await capturingRunner.run(
      executable: binaryName,
      arguments: [
        ctx.referenceWavPath,
        '--model',
        modelName,
        '--model_dir',
        modelParent,
        '--language',
        ctx.language,
        '--device',
        device,
        '--compute_type',
        computeType,
        '--output_format',
        'txt',
        '--output_dir',
        ctx.workDir,
        '--beep_off',
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

    // The output file is authoritative; stdout carries progress noise too.
    final transcript = _readTranscript(ctx, stdoutLines);

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

  /// Reads the `<wav-stem>.txt` written into the work dir; falls back to the
  /// captured stdout when the file is absent. The output file is deleted after
  /// reading so the work dir does not accumulate transcripts across runs.
  String _readTranscript(ProbeContext ctx, List<String> stdoutLines) {
    final stem = p.basenameWithoutExtension(ctx.referenceWavPath);
    final outFile = File(p.join(ctx.workDir, '$stem.txt'));
    if (outFile.existsSync()) {
      try {
        final lines = outFile.readAsLinesSync();
        outFile.deleteSync();
        return parseFasterWhisperTranscript(lines);
      } on FileSystemException {
        // Fall through to stdout parsing.
      }
    }
    return parseFasterWhisperTranscript(stdoutLines);
  }

  /// Tees the single-subscription stdout into a broadcast stream so both the
  /// capture list and [ProbeRunner]'s heartbeat listener can subscribe.
  /// Mirrors the other subprocess candidates.
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
