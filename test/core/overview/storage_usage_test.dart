import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/overview/storage_usage.dart';
import 'package:whispaste/core/text/byte_size.dart';

void main() {
  test('formatStorageBytes delegates to the shared byte formatter', () {
    expect(
      formatStorageBytes(1500000000, 'de'),
      formatByteSize(1500000000, locale: 'de'),
    );
  });

  test(
    'cache folders are the regenerable ones, never models or recordings',
    () {
      const root = '/data/whispaste';
      final dirs = storageCacheDirs(root);
      expect(dirs, [p.join(root, 'gpu-probe'), p.join(root, 'app_icons')]);
      expect(dirs.any((d) => d.contains('stt')), isFalse);
      expect(
        dirs.any((d) => d.contains('audio') || d.contains('imports')),
        isFalse,
      );
    },
  );
}
