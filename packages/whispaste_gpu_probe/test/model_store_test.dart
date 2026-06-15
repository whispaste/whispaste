/// Tests for [ModelStore] — catalogue state, presence detection, download with
/// progress, and the error path.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

void main() {
  group('defaultModelCatalog', () {
    test('lists ggml models smallest → largest', () {
      final c = defaultModelCatalog();
      expect(c.first.id, 'ggml-tiny');
      expect(
        c.map((m) => m.id),
        containsAll(<String>['ggml-tiny', 'ggml-small', 'ggml-large-v3']),
      );
    });
  });

  group('ModelStore', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ms-test-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('all models absent in an empty directory', () {
      final s = ModelStore(directory: tmp.path);
      expect(s.statusJson().every((m) => m['state'] == 'absent'), isTrue);
      expect(s.localPathIfPresent('ggml-tiny'), isNull);
    });

    test('detects a present model file on construction', () {
      File(p.join(tmp.path, 'ggml-tiny.bin')).writeAsBytesSync([1, 2, 3]);
      final s = ModelStore(directory: tmp.path);
      final tiny = s.statusJson().firstWhere((m) => m['id'] == 'ggml-tiny');
      expect(tiny['state'], 'present');
      expect(s.localPathIfPresent('ggml-tiny'), isNotNull);
    });

    test('download streams progress then marks present', () async {
      Future<void> fake(
        Uri url,
        File target,
        void Function(int, int) onP,
      ) async {
        onP(50, 100);
        onP(100, 100);
        await target.writeAsBytes(List.filled(100, 0));
      }

      final s = ModelStore(directory: tmp.path, downloader: fake);
      var changes = 0;
      await s.download('ggml-tiny', onChange: () => changes++);

      expect(s.localPathIfPresent('ggml-tiny'), isNotNull);
      final tiny = s.statusJson().firstWhere((m) => m['id'] == 'ggml-tiny');
      expect(tiny['state'], 'present');
      expect(changes, greaterThan(1));
    });

    test('a download error lands in the model state', () async {
      Future<void> boom(Uri u, File t, void Function(int, int) onP) async =>
          throw const SocketException('netz weg');

      final s = ModelStore(directory: tmp.path, downloader: boom);
      await s.download('ggml-tiny');
      final tiny = s.statusJson().firstWhere((m) => m['id'] == 'ggml-tiny');
      expect(tiny['state'], 'error');
      expect('${tiny['error']}', contains('netz weg'));
    });

    test('download is idempotent once present', () async {
      var calls = 0;
      Future<void> fake(Uri u, File t, void Function(int, int) onP) async {
        calls++;
        await t.writeAsBytes([1]);
      }

      final s = ModelStore(directory: tmp.path, downloader: fake);
      await s.download('ggml-tiny');
      await s.download('ggml-tiny'); // already present → no second fetch
      expect(calls, 1);
    });
  });

  group('ModelStore — sherpa-onnx bundle models', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ms-bundle-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('catalogue lists sherpa bundles with family sherpa-onnx', () {
      final c = defaultModelCatalog();
      final sherpa = c.where((m) => m.family == 'sherpa-onnx').toList();
      expect(sherpa.map((m) => m.id), contains('sherpa-whisper-base'));
      expect(sherpa.every((m) => m.isBundle), isTrue);
    });

    test(
      'downloads every bundle file into models/<id>/ then marks present',
      () async {
        final fetched = <String>[];
        Future<void> fake(Uri u, File t, void Function(int, int) onP) async {
          fetched.add(p.basename(t.path));
          onP(10, 10);
          await t.writeAsBytes(List.filled(10, 0));
        }

        final s = ModelStore(directory: tmp.path, downloader: fake);
        await s.download('sherpa-whisper-base');

        // All three files fetched.
        expect(fetched, hasLength(3));
        expect(fetched.any((f) => f.contains('encoder')), isTrue);
        expect(fetched.any((f) => f.contains('decoder')), isTrue);
        expect(fetched.any((f) => f.contains('tokens')), isTrue);

        // localPath is the bundle DIRECTORY, not a single file.
        final path = s.localPathIfPresent('sherpa-whisper-base');
        expect(path, isNotNull);
        expect(Directory(path!).existsSync(), isTrue);
        expect(p.basename(path), 'sherpa-whisper-base');

        final status = s.statusJson().firstWhere(
          (m) => m['id'] == 'sherpa-whisper-base',
        );
        expect(status['state'], 'present');
      },
    );

    test('detects a present bundle on construction', () {
      final dir = Directory(p.join(tmp.path, 'sherpa-whisper-base'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'base-encoder.int8.onnx')).writeAsBytesSync([1]);
      File(p.join(dir.path, 'base-decoder.int8.onnx')).writeAsBytesSync([1]);
      File(p.join(dir.path, 'base-tokens.txt')).writeAsBytesSync([1]);

      final s = ModelStore(directory: tmp.path);
      final status = s.statusJson().firstWhere(
        (m) => m['id'] == 'sherpa-whisper-base',
      );
      expect(status['state'], 'present');
    });

    test('a partial bundle is not present', () {
      final dir = Directory(p.join(tmp.path, 'sherpa-whisper-base'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'base-encoder.int8.onnx')).writeAsBytesSync([1]);
      // decoder + tokens missing.

      final s = ModelStore(directory: tmp.path);
      final status = s.statusJson().firstWhere(
        (m) => m['id'] == 'sherpa-whisper-base',
      );
      expect(status['state'], 'absent');
      expect(s.localPathIfPresent('sherpa-whisper-base'), isNull);
    });
  });
}
