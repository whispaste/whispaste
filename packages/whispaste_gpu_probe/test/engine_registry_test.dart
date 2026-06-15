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
    test('CPU engine is available when the bundled binary exists', () {
      final tmp = Directory.systemTemp.createTempSync('eng-');
      final bin = File(p.join(tmp.path, 'whisper'))..writeAsStringSync('x');
      final engines = defaultEngineRegistry(cpuBinary: bin.path);
      final cpu = engines.firstWhere((e) => e.id == 'whisper-cpp-cpu');
      expect(cpu.available, isTrue);

      final json = enginesJson(engines);
      final cpuJson = json.firstWhere((e) => e['id'] == 'whisper-cpp-cpu');
      expect(cpuJson['available'], isTrue);
      expect(cpuJson['backend'], 'cpu');
      tmp.deleteSync(recursive: true);
    });

    test('GPU engines are unavailable when their binary is absent', () {
      final engines = defaultEngineRegistry(
        cpuBinary: '/definitely/missing/whisper',
      );
      final vulkan = engines.firstWhere((e) => e.id == 'whisper-cpp-vulkan');
      expect(vulkan.available, isFalse);
    });

    test('candidate() wires the engine id + backend', () {
      final engines = defaultEngineRegistry(cpuBinary: '/x/whisper');
      final cand = engines.first.candidate();
      expect(cand.id, 'whisper-cpp-cpu');
      expect(cand.backend, 'cpu');
    });
  });
}
