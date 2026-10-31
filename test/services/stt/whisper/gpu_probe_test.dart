/// Unit tests for the out-of-process GPU probe (`gpu_probe.dart`): the rules
/// that map a child run to a verdict, the persisted result per key, and the
/// service that runs the child at most once per key. The child itself is a
/// fake here; a real crash cannot be produced inside a test runner.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/hardware_info_service.dart'
    show GpuInfo, GpuVendor;
import 'package:whispaste/services/stt/whisper/gpu_probe.dart';

const _gpu = GpuInfo(
  vendor: GpuVendor.amd,
  name: 'Radeon RX 6600',
  vramMB: 8192,
);
const _model = 'whisper-medium';

void main() {
  group('classifyProbeRun', () {
    test('exit 0 with a GPU backend in the report is ok', () {
      final o = classifyProbeRun(
        exitCode: 0,
        timedOut: false,
        engineBackend: 'vulkan',
        reachedApp: true,
      );
      expect(o.status, GpuProbeStatus.ok);
      expect(o.reason, 'vulkan');
    });

    test('exit 0 but the engine ran on CPU is a failure', () {
      final o = classifyProbeRun(
        exitCode: 0,
        timedOut: false,
        engineBackend: 'cpu',
        reachedApp: true,
      );
      expect(o.status, GpuProbeStatus.failed);
      expect(o.reason, 'engine ran on CPU');
    });

    test('a non-zero exit is a failure with the code in hex when large', () {
      // 0xC0000409 (FAST_FAIL_FATAL_APP_EXIT), the Sentry abort signature.
      final o = classifyProbeRun(
        exitCode: 0xC0000409,
        timedOut: false,
        engineBackend: null,
        reachedApp: true,
      );
      expect(o.status, GpuProbeStatus.failed);
      expect(o.reason, 'exit code 0xC0000409');
    });

    test('a hang that was killed is a failure', () {
      final o = classifyProbeRun(
        exitCode: null,
        timedOut: true,
        engineBackend: null,
        reachedApp: true,
      );
      expect(o.status, GpuProbeStatus.failed);
      expect(o.reason, 'timed out');
    });

    test('exit 0 without a report is a failure', () {
      final o = classifyProbeRun(
        exitCode: 0,
        timedOut: false,
        engineBackend: null,
        reachedApp: true,
      );
      expect(o.status, GpuProbeStatus.failed);
    });
  });

  test('formatProbeExitCode keeps small codes decimal', () {
    expect(formatProbeExitCode(1), '1');
    expect(formatProbeExitCode(-1073740791), '0xC0000409');
  });

  group('GpuProbeKey', () {
    GpuProbeKey key({
      String backend = 'vulkan',
      String app = '1.4.3',
      String os = 'Windows 10',
      String gpu = 'Radeon RX 6600',
      String driver = '24.12.1',
    }) => GpuProbeKey(
      backend: backend,
      gpuName: gpu,
      vramMB: 8192,
      driverVersion: driver,
      appVersion: app,
      osVersion: os,
    );

    test('differs per backend, app version, OS, GPU and driver', () {
      final base = key().id;
      expect(key(backend: 'cuda').id, isNot(base));
      expect(key(app: '1.4.4').id, isNot(base));
      expect(key(os: 'Windows 11').id, isNot(base));
      expect(key(gpu: 'Arc A770').id, isNot(base));
      expect(key(driver: '24.12.2').id, isNot(base));
    });

    test('is stable for the same setup', () {
      expect(key().id, key().id);
    });

    test('an unknown driver version is its own stable key', () {
      expect(key(driver: 'unknown').id, isNot(key().id));
      expect(key(driver: 'unknown').id, key(driver: 'unknown').id);
    });
  });

  group('start marker', () {
    test(
      'a child that never reached the app is unavailable, not a GPU verdict',
      () {
        for (final exit in [1, 0xC0000409, null]) {
          final o = classifyProbeRun(
            exitCode: exit,
            timedOut: exit == null,
            engineBackend: null,
            reachedApp: false,
          );
          expect(o.status, GpuProbeStatus.unavailable, reason: 'exit $exit');
        }
      },
    );

    test('a child that crashed after it reached the app is a failure', () {
      final o = classifyProbeRun(
        exitCode: 0xC0000409,
        timedOut: false,
        engineBackend: null,
        reachedApp: true,
      );
      expect(o.status, GpuProbeStatus.failed);
    });
  });

  group('GpuProbeStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('gpu_probe_store_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips a record and removes it', () {
      final store = GpuProbeStore(File(p.join(dir.path, 'gpu_probe.json')));
      store.write(
        'k',
        GpuProbeRecord(
          usable: false,
          reason: 'timed out',
          checkedAt: DateTime.utc(2026, 10, 21),
        ),
      );
      final read = store.read('k');
      expect(read?.usable, isFalse);
      expect(read?.reason, 'timed out');
      store.remove('k');
      expect(store.read('k'), isNull);
    });

    test('a corrupt file is an empty store, not an error', () {
      final file = File(p.join(dir.path, 'gpu_probe.json'))
        ..writeAsStringSync('{not json');
      expect(GpuProbeStore(file).read('k'), isNull);
    });

    test('one malformed entry does not hide the valid records next to it', () {
      final file = File(p.join(dir.path, 'gpu_probe.json'))
        ..writeAsStringSync(
          jsonEncode({
            'good': {
              'usable': true,
              'reason': '',
              'checkedAt': '2026-10-21T00:00:00.000Z',
            },
            'broken': {'usable': 'yes', 'checkedAt': 'not a date'},
          }),
        );
      final store = GpuProbeStore(file);
      expect(store.read('good')?.usable, isTrue);
      expect(store.read('broken'), isNull);

      // A later write must keep the valid record, not persist its loss.
      store.write(
        'other',
        GpuProbeRecord(
          usable: false,
          reason: 'timed out',
          checkedAt: DateTime.utc(2026, 10, 22),
        ),
      );
      expect(store.read('good')?.usable, isTrue);
    });
  });

  group('verdictFromRecord', () {
    test('no record means nothing was decided yet', () {
      expect(verdictFromRecord(null), isNull);
    });

    test('a stored failure stays unusable', () {
      expect(
        verdictFromRecord(
          GpuProbeRecord(
            usable: false,
            reason: 'x',
            checkedAt: DateTime.utc(2026),
          ),
        ),
        GpuProbeVerdict.unusable,
      );
    });
  });

  group('gpuProbeWav', () {
    test('is a 16 kHz mono 16-bit WAV of the requested length', () {
      final wav = gpuProbeWav();
      final data = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(data.getUint32(24, Endian.little), 16000);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint16(34, Endian.little), 16);
      expect(wav.length, 44 + 16000 * 2);
    });
  });

  group('GpuProbeService', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('gpu_probe_service_');
      file = File(p.join(dir.path, 'gpu_probe.json'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    GpuProbeService service(
      Future<GpuProbeOutcome> Function() run, {
      bool enabled = true,
      List<int>? runs,
    }) => GpuProbeService(
      store: GpuProbeStore(file),
      run: ({required modelId, required timeout}) {
        runs?.add(1);
        expect(modelId, _model);
        expect(timeout, kGpuProbeTimeout);
        return run();
      },
      appVersion: '1.4.3',
      osVersion: 'Windows 10',
      operatingSystem: 'windows',
      enabled: enabled,
    );

    test('a successful child is remembered: usable, no second run', () async {
      final runs = <int>[];
      final s = service(
        () async => const GpuProbeOutcome.ok('vulkan'),
        runs: runs,
      );
      expect(
        await s.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.usable,
      );
      // A fresh service (next launch) reads the file and does not run again.
      final next = service(() async => fail('must not run again'), runs: runs);
      expect(
        await next.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.usable,
      );
      expect(runs, hasLength(1));
    });

    test('a crashed child is persisted as unusable for this key', () async {
      final s = service(
        () async => const GpuProbeOutcome.failed('exit code 0xC0000409'),
      );
      expect(
        await s.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.unusable,
      );
      final key = s.keyFor(gpu: _gpu, backend: 'vulkan');
      expect(GpuProbeStore(file).read(key.id)?.reason, 'exit code 0xC0000409');
    });

    test('concurrent callers share one child run', () async {
      final runs = <int>[];
      final s = service(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return const GpuProbeOutcome.ok('vulkan');
      }, runs: runs);
      final results = await Future.wait([
        s.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        s.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
      ]);
      expect(results, everyElement(GpuProbeVerdict.usable));
      expect(runs, hasLength(1));
    });

    test('a child that could not start is unknown and not persisted', () async {
      final s = service(
        () async => const GpuProbeOutcome.unavailable('cannot start'),
      );
      expect(
        await s.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.unknown,
      );
      expect(file.existsSync(), isFalse);
    });

    group('macOS (platform override)', () {
      GpuProbeService onMac(List<int> runs, GpuProbeOutcome outcome) =>
          GpuProbeService(
            store: GpuProbeStore(file),
            run: ({required modelId, required timeout}) async {
              runs.add(1);
              return outcome;
            },
            appVersion: '1.4.3',
            osVersion: 'macOS 26',
            operatingSystem: 'macos',
          );

      test('the probe does not run and nothing is persisted', () async {
        final runs = <int>[];
        final s = onMac(runs, const GpuProbeOutcome.ok('metal'));
        expect(s.appliesHere, isFalse);
        expect(
          await s.verdict(gpu: _gpu, backend: 'metal', modelId: _model),
          GpuProbeVerdict.usable,
        );
        expect(runs, isEmpty);
        expect(file.existsSync(), isFalse);
      });

      test(
        'a failed, impossible or aborted probe never yields unusable',
        () async {
          for (final outcome in [
            const GpuProbeOutcome.failed('exit code 0xC0000409'),
            const GpuProbeOutcome.unavailable(
              'probe child did not start the app',
            ),
          ]) {
            final runs = <int>[];
            final s = onMac(runs, outcome);
            expect(
              await s.verdict(gpu: _gpu, backend: 'metal', modelId: _model),
              isNot(GpuProbeVerdict.unusable),
            );
            expect(runs, isEmpty);
          }
        },
      );

      test('Windows and Linux still probe', () {
        expect(
          GpuProbeService(
            store: GpuProbeStore(file),
            run: ({required modelId, required timeout}) async =>
                const GpuProbeOutcome.ok('vulkan'),
            appVersion: '1.4.3',
            osVersion: 'Windows 10',
            operatingSystem: 'windows',
          ).appliesHere,
          isTrue,
        );
      });
    });

    test('an unknown model is not probed at all', () async {
      final runs = <int>[];
      final s = GpuProbeService(
        store: GpuProbeStore(file),
        run: ({required modelId, required timeout}) async {
          runs.add(1);
          return const GpuProbeOutcome.ok('vulkan');
        },
        appVersion: '1.4.3',
        osVersion: 'Windows 10',
        operatingSystem: 'windows',
      );
      expect(
        await s.verdict(gpu: _gpu, backend: 'vulkan', modelId: 'not-a-model'),
        GpuProbeVerdict.unknown,
      );
      expect(runs, isEmpty);
    });

    test('disabled (probe child, tests) is usable without any run', () async {
      final s = service(() async => fail('must not run'), enabled: false);
      expect(
        await s.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.usable,
      );
      expect(file.existsSync(), isFalse);
    });

    test(
      'a driver update runs a new probe, an unknown driver does not loop',
      () async {
        final runs = <int>[];
        final s1 = service(
          () async => const GpuProbeOutcome.ok('vulkan'),
          runs: runs,
        );
        GpuInfo withDriver(String? v) => GpuInfo(
          vendor: GpuVendor.amd,
          name: 'Radeon RX 6600',
          vramMB: 8192,
          driverVersion: v,
        );
        await s1.verdict(
          gpu: withDriver('24.12.1'),
          backend: 'vulkan',
          modelId: _model,
        );
        // Same driver on the next launch: stored, no run.
        await service(
          () async => fail('must not run again'),
          runs: runs,
        ).verdict(
          gpu: withDriver('24.12.1'),
          backend: 'vulkan',
          modelId: _model,
        );
        expect(runs, hasLength(1));
        // Driver updated: a new key, a new probe.
        await service(
          () async => const GpuProbeOutcome.ok('vulkan'),
          runs: runs,
        ).verdict(
          gpu: withDriver('24.12.2'),
          backend: 'vulkan',
          modelId: _model,
        );
        expect(runs, hasLength(2));
        // Unreadable driver: one stable key, probed once and then stored.
        await service(
          () async => const GpuProbeOutcome.ok('vulkan'),
          runs: runs,
        ).verdict(gpu: withDriver(null), backend: 'vulkan', modelId: _model);
        await service(
          () async => fail('unknown driver must not loop'),
          runs: runs,
        ).verdict(gpu: withDriver(null), backend: 'vulkan', modelId: _model);
        expect(runs, hasLength(3));
      },
    );

    test('retry forgets the stored failure and probes again', () async {
      final failing = service(
        () async => const GpuProbeOutcome.failed('timed out'),
      );
      await failing.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model);
      final key = failing.keyFor(gpu: _gpu, backend: 'vulkan');

      final runs = <int>[];
      final retrying = service(
        () async => const GpuProbeOutcome.ok('vulkan'),
        runs: runs,
      );
      expect(
        await retrying.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.unusable,
      );
      retrying.retry(key);
      expect(
        await retrying.verdict(gpu: _gpu, backend: 'vulkan', modelId: _model),
        GpuProbeVerdict.usable,
      );
      expect(runs, hasLength(1));
    });
  });

  test('the probe result file is JSON readable by a human', () async {
    final dir = Directory.systemTemp.createTempSync('gpu_probe_json_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'gpu_probe.json'));
    GpuProbeStore(file).write(
      'k',
      GpuProbeRecord(
        usable: true,
        reason: 'metal',
        checkedAt: DateTime.utc(2026, 10, 21),
      ),
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(json['k'], containsPair('usable', true));
  });
}
