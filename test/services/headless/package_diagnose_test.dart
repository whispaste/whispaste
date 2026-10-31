import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ffi' as ffi;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/headless/package_diagnose.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLibraryPathFor;
import 'package:whispaste/services/stt/native_call_guard.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart'
    show whisperLibraryPathFor, whisperVadModelFileName, whisperVadModelPathFor;

String? _noCpuBackend(ffi.DynamicLibrary dylib, String libraryPath) => null;

/// Console stand-in: keeps what it is given, never takes it ([stall]) or
/// fails ([fail]).
class _Console implements StreamConsumer<List<int>> {
  _Console({this.stall = false, this.fail = false});

  final bool stall;
  final bool fail;
  final received = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (stall) return Completer<void>().future;
    if (fail) return Future.error(const StdoutException('no handle'));
    return stream.forEach(received.addAll);
  }

  @override
  Future<void> close() async {}
}

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
    test(
      'covers the whisper engine, its FFI guard and the Smart Mode shim',
      () {
        final exe = p.join('opt', 'whispaste', 'whispaste');
        final libs = bundledNativeLibraries(exe);
        expect(libs.map((l) => l.name), [
          'whisper',
          'ffi_guard',
          'smart_mode_shim',
        ]);
        expect(libs[0].path, whisperLibraryPathFor(exe));
        expect(libs[0].symbols, contains('whisper_full'));
        expect(libs[0].selfCheck, selfCheckWhisperVadModel);
        expect(
          libs[1].path,
          NativeCallGuard.pathNextTo(whisperLibraryPathFor(exe)),
        );
        expect(libs[1].selfCheck, isNotNull);
        expect(libs[2].path, smartModeLibraryPathFor(exe));
        expect(libs[2].symbols, contains('smart_mode_load'));
      },
    );
  });

  group('selfCheckWhisperVadModel', () {
    late Directory dir;
    late String library;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp_diag_vad_');
      library = p.join(dir.path, 'libwhisper.so');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('fails when the VAD model is not next to libwhisper', () {
      expect(
        () => selfCheckWhisperVadModel(library),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(whisperVadModelFileName),
          ),
        ),
      );
    });

    test('passes where the engine looks for the VAD model', () {
      final exe = p.join(dir.path, 'whispaste');
      File(whisperVadModelPathFor(exe))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0]);
      expect(
        () => selfCheckWhisperVadModel(whisperLibraryPathFor(exe)),
        returnsNormally,
      );
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
        probe: (lib) {
          probed.add(lib.path);
          return null;
        },
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
          return null;
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

  group('CPU backend check', () {
    const whisper = NativeLibrary(
      name: 'whisper',
      path: '/x/libwhisper.so',
      symbols: ['whisper_full'],
      cpuBackendProbe: _noCpuBackend,
    );

    test('reports the CPU backend variant ggml loaded', () {
      final report = runPackageDiagnose(
        libraries: const [whisper],
        version: '1.2.3',
        executable: '/x/whispaste',
        probe: (_) => 'SSE3 SSSE3 AVX AVX2 F16C FMA BMI2',
      );
      expect(report.ok, isTrue);
      final entries = report.toJson()['libraries']! as List<Object?>;
      expect(entries.single, {
        'name': 'whisper',
        'path': '/x/libwhisper.so',
        'ok': true,
        'cpuBackend': 'SSE3 SSSE3 AVX AVX2 F16C FMA BMI2',
      });
    });

    test('fails when no CPU backend was registered', () {
      // The Linux SIGABRT (Sentry 137899969): ggml found no backend module
      // next to libwhisper, so whisper.cpp aborted on a null CPU device.
      final report = runPackageDiagnose(
        libraries: const [whisper],
        version: '1.2.3',
        executable: '/x/whispaste',
        probe: (_) => null,
      );
      expect(report.ok, isFalse);
      final entries = report.toJson()['libraries']! as List<Object?>;
      expect((entries.single! as Map)['error'], contains('CPU backend'));
    });

    test('is checked for both engines where backends load dynamically', () {
      // Each engine loads its own ggml-cpu-<level> modules from its own
      // directory (Windows/Linux, -DGGML_BACKEND_DL=ON); the Smart Mode
      // shim's must resolve against its own ggml, not libwhisper's.
      final exe = p.join('opt', 'whispaste', 'whispaste');
      final libs = bundledNativeLibraries(exe);
      expect(libs[0].checksCpuBackend, !Platform.isMacOS);
      expect(libs[1].checksCpuBackend, isFalse);
      expect(libs[2].checksCpuBackend, !Platform.isMacOS);
    });
  });

  group('runtime section', () {
    test('is reported in the JSON but never changes the outcome', () {
      const runtime = {'whisperThreads': 6};
      final report = runPackageDiagnose(
        libraries: const [
          NativeLibrary(name: 'a', path: '/x/liba.so', symbols: ['a_init']),
        ],
        version: '1.2.3',
        executable: '/x/whispaste',
        probe: (_) => null,
        runtime: runtime,
      );
      expect(report.ok, isTrue);
      expect(report.toJson()['runtime'], runtime);
    });

    test('is omitted from the JSON when not probed', () {
      final report = runPackageDiagnose(
        libraries: const [],
        version: '1.2.3',
        executable: '/x/whispaste',
        probe: (_) => null,
      );
      expect(report.toJson().containsKey('runtime'), isFalse);
    });
  });

  group('selfCheckNativeCallGuard', () {
    test('fails for a missing guard', () {
      expect(
        () => selfCheckNativeCallGuard('/definitely/not/here/libwp.so'),
        throwsStateError,
      );
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

  group('emitPackageDiagnoseReport', () {
    test('with --out writes only the file, never the console', () async {
      final dir = Directory.systemTemp.createTempSync('wp-diagnose-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'r.json');
      final console = _Console();
      await emitPackageDiagnoseReport(
        '{"ok":true}',
        outPath: path,
        console: IOSink(console),
      );
      expect(File(path).readAsStringSync(), '{"ok":true}\n');
      expect(console.received, isEmpty);
    });

    test('without --out prints the report to the console', () async {
      final console = _Console();
      final delivered = await emitPackageDiagnoseReport(
        '{"ok":true}',
        console: IOSink(console),
      );
      expect(delivered, isTrue);
      expect(utf8.decode(console.received), '{"ok":true}\n');
    });

    test('returns after the timeout when the console never takes it', () {
      fakeAsync((async) {
        bool? delivered;
        emitPackageDiagnoseReport(
          '{}',
          console: IOSink(_Console(stall: true)),
          timeout: const Duration(seconds: 2),
        ).then((value) => delivered = value);
        async.elapse(const Duration(seconds: 1));
        expect(delivered, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(delivered, isFalse);
      });
    });

    test('returns when the console fails', () async {
      final delivered = await emitPackageDiagnoseReport(
        '{}',
        console: IOSink(_Console(fail: true)),
      );
      expect(delivered, isFalse);
    });
  });
}
