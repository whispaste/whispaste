import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

/// #1546: a bundle file counts only with its pinned size, so a hand-placed
/// or cut-off file is downloaded again instead of failing on load.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wp_parakeet_'));
  tearDown(() => dir.deleteSync(recursive: true));

  const files = [
    ParakeetModelFile(
      filename: 'a.onnx',
      sources: [''],
      sizeBytes: 4,
      sha256: '',
    ),
    ParakeetModelFile(
      filename: 'b.txt',
      sources: [''],
      sizeBytes: 2,
      sha256: '',
    ),
  ];
  void put(String name, int bytes) =>
      File('${dir.path}/$name').writeAsBytesSync(List.filled(bytes, 1));

  test('every file with its pinned size is a complete bundle', () {
    put('a.onnx', 4);
    put('b.txt', 2);
    expect(parakeetBundleCompleteIn(dir.path, files), isTrue);
  });

  test('a file of the right name but another size is not complete', () {
    put('a.onnx', 5);
    put('b.txt', 2);
    expect(parakeetBundleFileCompleteIn(dir.path, files.first), isFalse);
    expect(parakeetBundleCompleteIn(dir.path, files), isFalse);
  });

  test('a missing file or a folder of that name is not complete', () {
    put('a.onnx', 4);
    Directory('${dir.path}/b.txt').createSync();
    expect(parakeetBundleFileCompleteIn(dir.path, files.last), isFalse);
    expect(parakeetBundleCompleteIn(dir.path, files), isFalse);
    expect(
      parakeetBundleFileCompleteIn('${dir.path}/nowhere', files.first),
      isFalse,
    );
  });
}
