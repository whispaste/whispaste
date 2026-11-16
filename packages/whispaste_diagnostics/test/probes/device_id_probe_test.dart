/// Unit tests for device_id_probe.dart.
///
/// The probe reports the app's stored install id, never a value derived
/// from the machine.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/device_id_probe.dart';
import 'package:whispaste_diagnostics/src/probes/path_service.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('device_id_probe'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('deviceId', () {
    test('returns the install id the app stored', () {
      File(
        p.join(dir.path, installIdFileName),
      ).writeAsStringSync('0a1b2c3d4e5f\n');
      expect(deviceId(directory: dir.path), '0a1b2c3d4e5f');
    });

    test('is unknown before the app ever ran, and creates nothing', () {
      expect(deviceId(directory: dir.path), 'unknown');
      expect(File(p.join(dir.path, installIdFileName)).existsSync(), isFalse);
    });

    test('is unknown for a damaged file', () {
      File(p.join(dir.path, installIdFileName)).writeAsStringSync('my-pc');
      expect(deviceId(directory: dir.path), 'unknown');
    });
  });

  group('deviceId in an MSIX install (PAR-031)', () {
    late Directory exeRoot;
    late Directory msixRoot;
    late Directory otherMsixRoot;

    setUp(() {
      exeRoot = Directory.systemTemp.createTempSync('device_id_exe');
      msixRoot = Directory.systemTemp.createTempSync('device_id_msix');
      otherMsixRoot = Directory.systemTemp.createTempSync('device_id_msix2');
      appDataDirOverride = exeRoot.path;
    });

    tearDown(() {
      appDataDirOverride = null;
      for (final d in [exeRoot, msixRoot, otherMsixRoot]) {
        d.deleteSync(recursive: true);
      }
    });

    test(
      'reads the id from the MSIX LocalCache root when the EXE root has none',
      () {
        File(
          p.join(msixRoot.path, installIdFileName),
        ).writeAsStringSync('0a1b2c3d4e5f');
        expect(deviceId(msixRoots: () => [msixRoot.path]), '0a1b2c3d4e5f');
      },
    );

    test('prefers the EXE root when it already holds an id', () {
      File(
        p.join(exeRoot.path, installIdFileName),
      ).writeAsStringSync('111111111111');
      File(
        p.join(msixRoot.path, installIdFileName),
      ).writeAsStringSync('222222222222');
      expect(deviceId(msixRoots: () => [msixRoot.path]), '111111111111');
    });

    test(
      'takes the first MSIX root that holds a valid id, in candidate order',
      () {
        File(
          p.join(otherMsixRoot.path, installIdFileName),
        ).writeAsStringSync('333333333333');
        expect(
          deviceId(msixRoots: () => [msixRoot.path, otherMsixRoot.path]),
          '333333333333',
        );
      },
    );

    test('a damaged MSIX id is unknown, and nothing is created', () {
      File(p.join(msixRoot.path, installIdFileName)).writeAsStringSync('my-pc');
      expect(deviceId(msixRoots: () => [msixRoot.path]), 'unknown');
      expect(
        File(p.join(exeRoot.path, installIdFileName)).existsSync(),
        isFalse,
      );
    });

    test('is unknown when no root holds an id', () {
      expect(deviceId(msixRoots: () => [msixRoot.path]), 'unknown');
    });

    test('candidates are the LocalCache roots of WhisPaste packages only', () {
      expect(
        msixLocalCacheCandidatesFor(
          localAppData: r'C:\Users\x\AppData\Local',
          packageDirNames: [
            '12342SilvioLindstedt.WhisPaste_abc',
            'Microsoft.Other_def',
          ],
        ),
        [
          r'C:\Users\x\AppData\Local\Packages\12342SilvioLindstedt.WhisPaste_abc'
              r'\LocalCache\Roaming\WhisPaste',
        ],
      );
    });

    test('the production lookup is empty off Windows', () {
      if (!Platform.isWindows) {
        expect(msixLocalCacheRoots(), isEmpty);
      }
    });
  });
}
