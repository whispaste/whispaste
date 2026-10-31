import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/overview/storage_usage.dart';

void main() {
  group('formatStorageBytes', () {
    test('uses KB, MB and GB with one decimal from MB on', () {
      expect(formatStorageBytes(0, 'en'), '0 B');
      expect(formatStorageBytes(1023, 'en'), '1,023 B');
      expect(formatStorageBytes(2048, 'en'), '2 KB');
      expect(formatStorageBytes(1024 * 1024, 'en'), '1.0 MB');
      expect(formatStorageBytes(1536 * 1024 * 1024, 'en'), '1.5 GB');
    });

    test('uses the language number format', () {
      expect(formatStorageBytes(1536 * 1024 * 1024, 'de'), '1,5 GB');
    });
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
