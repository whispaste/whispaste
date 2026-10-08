import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/headless/package_diagnose.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLibraryPathFor;
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart'
    show whisperLibraryPathFor;

void main() {
  group('PackageDiagnoseOptions', () {
    test('is requested only by --diagnose', () {
      expect(PackageDiagnoseOptions.isRequested(['--diagnose']), isTrue);
      expect(PackageDiagnoseOptions.isRequested(['--toggle']), isFalse);
      expect(PackageDiagnoseOptions.isRequested(const []), isFalse);
    });

    test('parses --out', () {
      final options = PackageDiagnoseOptions.parse([
        '--diagnose',
        '--out',
        'r.json',
      ]);
      expect(options.outPath, 'r.json');
      expect(PackageDiagnoseOptions.parse(['--diagnose']).outPath, isNull);
    });

    test('rejects --out without a path and unknown options', () {
      expect(
        () => PackageDiagnoseOptions.parse(['--diagnose', '--out']),
        throwsFormatException,
      );
      expect(
        () => PackageDiagnoseOptions.parse(['--diagnose', '--bogus']),
        throwsFormatException,
      );
    });
  });

  group('bundledNativeLibraries', () {
    test('covers the whisper engine and the Smart Mode shim of the bundle', () {
      final exe = p.join('opt', 'whispaste', 'whispaste');
      final libs = bundledNativeLibraries(exe);
      expect(libs.map((l) => l.name), ['whisper', 'smart_mode_shim']);
      expect(libs[0].path, whisperLibraryPathFor(exe));
      expect(libs[0].symbols, contains('whisper_full'));
      expect(libs[1].path, smartModeLibraryPathFor(exe));
      expect(libs[1].symbols, contains('smart_mode_load'));
    });
  });

  group('runPackageDiagnose', () {
    const libs = [
      NativeLibrary(name: 'a', path: '/x/liba.so', symbols: ['a_init']),
      NativeLibrary(name: 'b', path: '/x/libb.so', symbols: ['b_init']),
    ];

    test('is ok when every bundled library loads', () {
      final probed = <String>[];
      final report = runPackageDiagnose(
        libraries: libs,
        version: '1.2.3',
        executable: '/x/whispaste',
        probe: (lib) => probed.add(lib.path),
      );
      expect(probed, ['/x/liba.so', '/x/libb.so']);
      expect(report.ok, isTrue);
      expect(report.toJson(), {
        'ok': true,
        'version': '1.2.3',
        'os': Platform.operatingSystem,
        'executable': '/x/whispaste',
        'libraries': [
          {'name': 'a', 'path': '/x/liba.so', 'ok': true},
          {'name': 'b', 'path': '/x/libb.so', 'ok': true},
        ],
      });
    });

    test('reports each failure and keeps probing the rest', () {
      final report = runPackageDiagnose(
        libraries: libs,
        version: '1.2.3',
        executable: '/x/whispaste',
        probe: (lib) {
          if (lib.name == 'a') throw ArgumentError('libfoo.so: not found');
        },
      );
      expect(report.ok, isFalse);
      final json = report.toJson();
      final entries = json['libraries']! as List<Object?>;
      expect(entries[0], {
        'name': 'a',
        'path': '/x/liba.so',
        'ok': false,
        'error': 'Invalid argument(s): libfoo.so: not found',
      });
      expect((entries[1]! as Map)['ok'], isTrue);
      // The report must stay valid JSON for the CI smoke scripts.
      expect(jsonDecode(jsonEncode(json)), json);
    });
  });

  group('probeNativeLibrary', () {
    test('fails for a missing library file', () {
      expect(
        () => probeNativeLibrary(
          const NativeLibrary(
            name: 'missing',
            path: '/definitely/not/here/libnope.so',
            symbols: ['nope'],
          ),
        ),
        throwsA(anything),
      );
    });
  });
}
