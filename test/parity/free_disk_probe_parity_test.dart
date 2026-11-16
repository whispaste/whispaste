// Contract for the disk-space probe (RE2-20 / OW-P19). Windows, macOS and
// Linux each need a native probe, and every model download service must run
// the central check before it starts a fetch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/free_disk_space.dart';

void main() {
  final probeSource = File(
    'lib/services/free_disk_space.dart',
  ).readAsStringSync();

  test('Windows probe uses GetDiskFreeSpaceExW', () {
    expect(probeSource, contains('Platform.isWindows'));
    expect(probeSource, contains("'GetDiskFreeSpaceExW'"));
  });

  test('macOS and Linux probe use statvfs', () {
    expect(probeSource, contains('Platform.isMacOS || Platform.isLinux'));
    expect(probeSource, contains('lookupFunction'));
    expect(probeSource, contains("'statvfs'"));
  });

  test('the probe answers on the platform that runs this test', () async {
    final bytes = await freeDiskBytes(Directory.systemTemp.path);

    expect(bytes, isNotNull);
    expect(bytes, greaterThan(0));
  });

  test('every model download service runs the central disk check', () {
    const services = [
      'lib/services/model_download_service.dart',
      'lib/services/smart_mode/smart_mode_model_download_service.dart',
      'lib/services/stt_parakeet/parakeet_download_service.dart',
    ];
    for (final path in services) {
      expect(
        File(path).readAsStringSync(),
        contains('checkDownloadDiskSpace('),
        reason: '$path must check free space before it fetches',
      );
    }
  });
}
