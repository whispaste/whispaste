/// Tests for the engine registry — availability detection + the default set.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

void main() {
  group('isExecutableAvailable', () {
    test('empty string is never available', () {
      expect(isExecutableAvailable(''), isFalse);
    });

    test('absolute path: true when the file exists, false when missing', () {
      final tmp = Directory.systemTemp.createTempSync('eng-');
      final bin = File(p.join(tmp.path, 'whisper'))..writeAsStringSync('x');
      expect(isExecutableAvailable(bin.path), isTrue);
      expect(isExecutableAvailable(p.join(tmp.path, 'nope')), isFalse);
      tmp.deleteSync(recursive: true);
    });
  });

  group('defaultEngineRegistry', () {
    test('lists the full PRD candidate matrix (alternatives + baseline)', () {
      final ids = defaultEngineRegistry(exeDir: '/x').map((e) => e.id);
      expect(
        ids,
        containsAll(<String>[
          'whisper-cpp-cpu',
          'const-me-directcompute',
          'onnx-directml',
          'wav2vec2-directml-de',
          'whisper-cpp-vulkan',
          'whisper-cpp-cuda12',
          'sherpa-onnx-cpu',
          'sherpa-onnx-cuda',
        ]),
      );
    });

    test('sherpa-onnx engines declare the sherpa-onnx model family', () {
      final engines = defaultEngineRegistry(exeDir: '/x');
      final cpu = engines.firstWhere((e) => e.id == 'sherpa-onnx-cpu');
      expect(cpu.modelFamily, 'sherpa-onnx');
      expect(cpu.backend, 'onnx-cpu');
      expect(cpu.candidate().id, 'sherpa-onnx-cpu');

      final cuda = engines.firstWhere((e) => e.id == 'sherpa-onnx-cuda');
      expect(cuda.modelFamily, 'sherpa-onnx');
      expect(cuda.backend, 'cuda');
      expect(cuda.candidate().id, 'sherpa-onnx-cuda');
    });

    test('engines declare model families (ggml / onnx-whisper / wav2vec2)', () {
      final engines = defaultEngineRegistry(exeDir: '/x');
      final fam = {for (final e in engines) e.id: e.modelFamily};
      expect(fam['whisper-cpp-cpu'], 'ggml');
      expect(fam['const-me-directcompute'], 'ggml');
      expect(fam['onnx-directml'], 'onnx-whisper');
      expect(fam['wav2vec2-directml-de'], 'onnx-wav2vec2');
    });

    test('CPU engine is available when the bundled binary exists', () {
      final tmp = Directory.systemTemp.createTempSync('eng-');
      File(p.join(tmp.path, 'whisper')).writeAsStringSync('x');
      final engines = defaultEngineRegistry(exeDir: tmp.path);
      final cpu = engines.firstWhere((e) => e.id == 'whisper-cpp-cpu');
      expect(cpu.available, isTrue);

      final cpuJson = enginesJson(
        engines,
      ).firstWhere((e) => e['id'] == 'whisper-cpp-cpu');
      expect(cpuJson['available'], isTrue);
      expect(cpuJson['backend'], 'cpu');
      expect(cpuJson['family'], 'ggml');
      tmp.deleteSync(recursive: true);
    });

    test('engines are unavailable when their binary is absent', () {
      final engines = defaultEngineRegistry(exeDir: '/definitely/missing/dir');
      expect(engines.every((e) => !e.available), isTrue);
    });

    test('candidate() wires the engine id', () {
      final engines = defaultEngineRegistry(exeDir: '/x');
      expect(engines.first.candidate().id, 'whisper-cpp-cpu');
    });
  });
}
