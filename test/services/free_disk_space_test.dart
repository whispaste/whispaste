import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/free_disk_space.dart';

void main() {
  test('reports a plausible value for an existing directory (UIA-ONB-09)', () {
    return freeDiskBytes(Directory.systemTemp.path).then((bytes) {
      expect(bytes, isNotNull);
      expect(bytes, greaterThan(0));
    });
  });

  test('resolves a missing directory to its nearest existing parent', () async {
    final missing = '${Directory.systemTemp.path}/wp-no-such-dir/a/b';
    final viaMissing = await freeDiskBytes(missing);
    final direct = await freeDiskBytes(Directory.systemTemp.path);
    // Same volume; other processes may write in between.
    expect(viaMissing, closeTo(direct!, 256 * 1024 * 1024));
  });
}
