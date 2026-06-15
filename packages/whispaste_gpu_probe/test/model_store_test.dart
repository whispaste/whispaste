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
}
