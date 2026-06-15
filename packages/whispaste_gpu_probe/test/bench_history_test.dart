/// Tests for [BenchHistory] / [BenchRun] — JSONL round-trip, parse tolerance,
/// and the GPU-backend classifier used by the report highlight.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

BenchRun _run({
  String engineId = 'sherpa-onnx-cpu',
  String backend = 'onnx-cpu',
  String outcome = 'ok',
  int? durationMs = 1200,
  DateTime? ts,
}) => BenchRun(
  timestamp: ts ?? DateTime.utc(2026, 6, 15, 12),
  engineId: engineId,
  engineLabel: 'Label $engineId',
  backend: backend,
  outcome: outcome,
  modelId: 'sherpa-whisper-base',
  modelLabel: 'sherpa base',
  durationMs: durationMs,
  audioMs: 3000,
  realtimeFactor: durationMs != null ? durationMs / 3000 : null,
  transcribedText: 'Guten Tag.',
  version: '1.0-test',
);

void main() {
  group('isGpuBackend', () {
    test('cpu and onnx-cpu are not GPU', () {
      expect(isGpuBackend('cpu'), isFalse);
      expect(isGpuBackend('onnx-cpu'), isFalse);
    });

    test('accelerator backends are GPU', () {
      for (final b in const [
        'directcompute',
        'cuda',
        'cuda12',
        'vulkan',
        'directml',
        'wav2vec2-directml',
      ]) {
        expect(isGpuBackend(b), isTrue, reason: b);
      }
    });

    test('null / empty is not GPU', () {
      expect(isGpuBackend(null), isFalse);
      expect(isGpuBackend(''), isFalse);
    });
  });

  group('BenchRun', () {
    test('toJson/fromJson round-trips and stamps isGpu', () {
      final run = _run(backend: 'cuda');
      final back = BenchRun.fromJson(run.toJson());
      expect(back, isNotNull);
      expect(back!.engineId, run.engineId);
      expect(back.backend, 'cuda');
      expect(back.durationMs, 1200);
      expect(back.realtimeFactor, closeTo(0.4, 0.001));
      expect(back.transcribedText, 'Guten Tag.');
      expect(run.toJson()['isGpu'], isTrue);
    });

    test('fromJson rejects a row missing required fields', () {
      expect(BenchRun.fromJson({'engineId': 'x'}), isNull);
      expect(
        BenchRun.fromJson({
          'timestamp': 'not-a-date',
          'engineId': 'x',
          'backend': 'cpu',
          'outcome': 'ok',
        }),
        isNull,
      );
    });
  });

  group('BenchHistory', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('bench-hist-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('missing file → empty history', () {
      final h = BenchHistory(File(p.join(tmp.path, 'nope.jsonl')));
      expect(h.load(), isEmpty);
    });

    test('append then load round-trips, oldest first', () {
      final f = File(p.join(tmp.path, 'sub', 'bench-history.jsonl'));
      final h = BenchHistory(f);
      h.append(_run(engineId: 'a', ts: DateTime.utc(2026, 1, 1)));
      h.append(_run(engineId: 'b', ts: DateTime.utc(2026, 1, 2)));
      final runs = h.load();
      expect(runs.map((r) => r.engineId), ['a', 'b']);
      expect(f.existsSync(), isTrue); // parent dir created lazily
    });

    test('a malformed tail line does not break earlier history', () {
      final f = File(p.join(tmp.path, 'bench-history.jsonl'));
      final h = BenchHistory(f);
      h.append(_run(engineId: 'good'));
      f.writeAsStringSync('{ this is not json\n', mode: FileMode.append);
      f.writeAsStringSync('\n', mode: FileMode.append); // blank line
      final runs = h.load();
      expect(runs, hasLength(1));
      expect(runs.single.engineId, 'good');
    });
  });
}
