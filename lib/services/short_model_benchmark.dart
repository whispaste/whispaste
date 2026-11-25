/// The setup-only speech benchmark. A child owns native inference so cancel
/// and the deadline can stop it without touching the dictation engine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'stt/stt_benchmark.dart';
import '../core/config/settings_provider.dart';
import 'stt/whisper/gpu_probe.dart' show kGpuProbeChildEnv;

const shortModelBenchmarkLimit = Duration(seconds: 20);

/// Session-only: projections are never stored as measured tier results.
final shortModelBenchmarkRtfProvider =
    NotifierProvider<ShortBenchmarkRtf, double?>(ShortBenchmarkRtf.new);

class ShortBenchmarkRtf extends Notifier<double?> {
  @override
  double? build() {
    ref.watch(
      settingsProvider.select((s) => s.value?.behavior.gpuAcceleration),
    );
    return null;
  }

  void setResult(double? rtf) => state = rtf;
}

/// Discards the warm-up and averages exactly two successful measured runs.
/// Malformed/partial reports use the same static fallback as cancellation.
double? compactRtfFromReport(Object? report) {
  if (report is! Map || report['model'] != 'whisper-small') return null;
  final duration = report['audioDurationMs'];
  final runs = report['runs'];
  if (duration is! num ||
      !duration.isFinite ||
      duration <= 0 ||
      runs is! List ||
      runs.length != 3) {
    return null;
  }
  var total = 0.0;
  for (final run in runs.skip(1)) {
    if (run is! Map) return null;
    final ms = run['transcribeMs'];
    if (ms is! num || !ms.isFinite || ms <= 0) return null;
    total += ms;
  }
  return total / 2 / duration;
}

class ShortModelBenchmark {
  Process? _child;
  final _cancelled = Completer<void>();

  /// Whether the last [run] failed on its own: the child exited with an
  /// error, or its report was unusable or missing. A cancel or the time
  /// limit is no failure (the machine is just slow). Read by the usage
  /// statistics as `model/check_failed` `small|short_test` (#1791).
  bool get failed => _failed;
  bool _failed = false;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    _child?.kill(ProcessSignal.sigkill);
  }

  Future<double?> run({required String gpu}) =>
      Future.any([_run(gpu: gpu), _cancelled.future.then((_) => null)]);

  Future<double?> _run({required String gpu}) async {
    Directory? directory;
    final deadline = Timer(shortModelBenchmarkLimit, cancel);
    try {
      // No silence fallback: it would produce a misleading recommendation.
      final data = await rootBundle.load(kBenchmarkReferenceAsset);
      directory = await Directory.systemTemp.createTemp(
        'whispaste-short-test-',
      );
      final wav = File(p.join(directory.path, 'reference.wav'));
      final report = File(p.join(directory.path, 'result.json'));
      await wav.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (_cancelled.isCompleted) return null;
      final child = _child = await Process.start(
        Platform.resolvedExecutable,
        [
          '--transcribe-file',
          wav.path,
          '--model',
          'whisper-small',
          '--language',
          'de',
          '--repeat',
          '3',
          '--gpu',
          gpu,
          '--out',
          report.path,
        ],
        environment: {kGpuProbeChildEnv: '1'},
      );
      unawaited(child.stdout.drain<void>());
      unawaited(child.stderr.drain<void>());
      if (_cancelled.isCompleted) child.kill(ProcessSignal.sigkill);
      final code = await Future.any<int?>([
        child.exitCode,
        _cancelled.future.then((_) => null),
      ]);
      if (_cancelled.isCompleted) return null;
      if (code != 0) {
        _failed = true;
        return null;
      }
      final rtf = compactRtfFromReport(jsonDecode(await report.readAsString()));
      _failed = rtf == null;
      return rtf;
    } on Object {
      _failed = !_cancelled.isCompleted;
      return null;
    } finally {
      deadline.cancel();
      _child?.kill(ProcessSignal.sigkill);
      // Wait for native resources and file handles to be released before
      // cleanup (not part of the visible result/deadline).
      final child = _child;
      final cleanupDirectory = directory;
      if (child != null) {
        unawaited(
          child.exitCode
              .then((_) async {
                if (cleanupDirectory != null &&
                    await cleanupDirectory.exists()) {
                  await cleanupDirectory.delete(recursive: true);
                }
              })
              .catchError((Object _) {}),
        );
      } else if (cleanupDirectory != null) {
        await cleanupDirectory.delete(recursive: true);
      }
    }
  }
}
