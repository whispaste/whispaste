/// The CUDA/Vulkan comparison (#1670): the decision rule, the order and abort
/// rules of the run, the setup key that decides when to measure again, the
/// stored result, and how that result gates the pack load and the offer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/hardware_info_service.dart'
    show GpuInfo, GpuVendor;
import 'package:whispaste/services/stt/whisper/cuda_ab.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

const _gtx1650 = GpuInfo(
  vendor: GpuVendor.nvidia,
  name: 'NVIDIA GeForce GTX 1650',
  vramMB: 4096,
  cudaAvailable: true,
  driverVersion: '32.0.16.1088',
);

String _key({
  GpuInfo gpu = _gtx1650,
  String appVersion = '1.4.9',
  String packId = 'ggml-v1.9.5-cu12.8-r1',
  String modelId = 'whisper-large-v3-turbo',
}) => cudaAbKey(
  gpu: gpu,
  appVersion: appVersion,
  packId: packId,
  modelId: modelId,
);

void main() {
  group('pickCudaAbWinner', () {
    test('GTX 1650 timings (turbo, #1670) pick Vulkan', () {
      expect(
        pickCudaAbWinner(cudaMs: [2484, 2494], vulkanMs: [1029, 1038]),
        CudaAbWinner.vulkan,
      );
    });

    test('RTX 3060 Ti timings (CUDA 30 to 48 % faster) keep CUDA', () {
      expect(
        pickCudaAbWinner(cudaMs: [520, 540], vulkanMs: [800, 820]),
        CudaAbWinner.cuda,
      );
    });

    test('Vulkan only a little faster (inside the margin) keeps CUDA', () {
      expect(
        pickCudaAbWinner(cudaMs: [1000, 1000], vulkanMs: [950, 960]),
        CudaAbWinner.cuda,
      );
      expect(
        pickCudaAbWinner(cudaMs: [1000, 1000], vulkanMs: [900, 900]),
        CudaAbWinner.vulkan,
      );
    });

    test('compares medians, so one slow outlier does not decide', () {
      expect(
        pickCudaAbWinner(cudaMs: [500, 510, 4000], vulkanMs: [800, 810, 820]),
        CudaAbWinner.cuda,
      );
    });

    test('median of an even count is the mean of the middle two', () {
      expect(medianMs([3, 1]), 2);
      expect(medianMs([5, 1, 3]), 3);
    });
  });

  group('measureCudaAb', () {
    test('warms both sides once, then measures interleaved pairs', () async {
      final calls = <String>[];
      var cuda = 0;
      var vulkan = 0;
      final result = await measureCudaAb(
        prepareVulkan: () async {
          calls.add('load');
          return true;
        },
        timeCuda: () async {
          calls.add('cuda');
          return 100 + cuda++;
        },
        timeVulkan: () async {
          calls.add('vulkan');
          return 50 + vulkan++;
        },
        shouldStop: () => false,
      );

      expect(calls, [
        'load',
        'cuda',
        'vulkan', // warm-up pair, not counted
        'cuda',
        'vulkan',
        'cuda',
        'vulkan',
      ]);
      expect(result.complete, isTrue);
      expect(result.cudaMs, [101, 102]);
      expect(result.vulkanMs, [51, 52]);
    });

    test('a dictation starting mid-run ends it after the step', () async {
      var steps = 0;
      final result = await measureCudaAb(
        prepareVulkan: () async => true,
        timeCuda: () async => ++steps,
        timeVulkan: () async => ++steps,
        shouldStop: () => steps >= 3,
      );

      expect(result.abort, CudaAbAbort.busy);
      expect(steps, 3);
    });

    test('a busy pipeline before the start loads nothing', () async {
      var loaded = false;
      final result = await measureCudaAb(
        prepareVulkan: () async => loaded = true,
        timeCuda: () async => 1,
        timeVulkan: () async => 1,
        shouldStop: () => true,
      );

      expect(result.abort, CudaAbAbort.busy);
      expect(loaded, isFalse);
    });

    test('no Vulkan device: no timing at all', () async {
      var timed = false;
      final result = await measureCudaAb(
        prepareVulkan: () async => false,
        timeCuda: () async {
          timed = true;
          return 1;
        },
        timeVulkan: () async => 1,
        shouldStop: () => false,
      );

      expect(result.abort, CudaAbAbort.noVulkan);
      expect(timed, isFalse);
    });
  });

  group('cudaAbKey (when to measure again)', () {
    test('is stable for the same setup', () {
      expect(_key(), _key());
    });

    test('changes with driver, card, app build, pack and model', () {
      const newDriver = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce GTX 1650',
        vramMB: 4096,
        cudaAvailable: true,
        driverVersion: '32.0.16.2000',
      );
      const otherCard = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce RTX 3060 Ti',
        vramMB: 8192,
        cudaAvailable: true,
        driverVersion: '32.0.16.1088',
      );
      final keys = {
        _key(),
        _key(gpu: newDriver),
        _key(gpu: otherCard),
        _key(appVersion: '1.4.10'),
        _key(packId: 'ggml-v1.9.6-cu12.8-r1'),
        _key(modelId: 'whisper-medium'),
      };
      expect(keys, hasLength(6));
    });
  });

  group('cudaAbRecordFor', () {
    final record = CudaAbRecord(
      winner: CudaAbWinner.vulkan,
      measuredAt: DateTime.utc(2026),
    );

    test('finds the record of the current setup only', () {
      final records = {_key(): record};
      CudaAbRecord? lookup({String modelId = 'whisper-large-v3-turbo'}) =>
          cudaAbRecordFor(
            records: records,
            gpu: _gtx1650,
            packId: 'ggml-v1.9.5-cu12.8-r1',
            modelId: modelId,
            appVersion: '1.4.9',
          );

      expect(lookup(), same(record));
      expect(lookup(modelId: 'whisper-small'), isNull);
    });

    test('without GPU info, pack or model there is no record', () {
      expect(
        cudaAbRecordFor(
          records: {_key(): record},
          gpu: null,
          packId: 'ggml-v1.9.5-cu12.8-r1',
          modelId: 'whisper-large-v3-turbo',
          appVersion: '1.4.9',
        ),
        isNull,
      );
    });
  });

  group('CudaAbStore', () {
    late Directory dir;
    late CudaAbStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('cuda_ab_');
      store = CudaAbStore(File(p.join(dir.path, 'cuda_ab.json')));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips a result', () {
      store.write(
        'k',
        CudaAbRecord(
          winner: CudaAbWinner.vulkan,
          measuredAt: DateTime.utc(2026, 11, 16),
          cudaMedianMs: 2489,
          vulkanMedianMs: 1033.5,
        ),
      );

      final read = CudaAbStore(store.file).readAll()['k']!;
      expect(read.vulkanFaster, isTrue);
      expect(read.cudaMedianMs, 2489);
      expect(read.vulkanMedianMs, 1033.5);
      expect(read.interrupted, isFalse);
    });

    test('a run that never ended reads as "keep CUDA", so a crash in the '
        'comparison cannot repeat on every start', () {
      store.markPending('k');

      final read = store.readAll()['k']!;
      expect(read.winner, CudaAbWinner.cuda);
      expect(read.interrupted, isTrue);
    });

    test('a run paused for a dictation leaves nothing behind', () {
      store.markPending('k');
      store.clearPending('k');

      expect(store.readAll(), isEmpty);
    });

    test('clearPending never removes a finished result', () {
      final done = CudaAbRecord(
        winner: CudaAbWinner.cuda,
        measuredAt: DateTime.utc(2026),
      );
      store.write('k', done);
      store.clearPending('k');

      expect(store.readAll()['k'], isNotNull);
    });

    test('keeps only the newest setups', () {
      for (var i = 0; i < 12; i++) {
        store.write(
          'k$i',
          CudaAbRecord(
            winner: CudaAbWinner.cuda,
            measuredAt: DateTime.utc(2026),
          ),
        );
      }

      final keys = store.readAll().keys;
      expect(keys, hasLength(8));
      expect(keys, contains('k11'));
      expect(keys, isNot(contains('k0')));
    });

    test('an unreadable file is an empty store', () {
      store.file.writeAsStringSync('{not json');
      expect(store.readAll(), isEmpty);

      store.file.writeAsStringSync(jsonEncode({'k': 'garbage'}));
      expect(store.readAll(), isEmpty);
    });
  });

  group('load gate and offer', () {
    const pack = CudaPackInfo(
      id: 'ggml-test-r1',
      url: 'https://example.invalid/pack.zip',
      archiveSizeBytes: 1024,
      archiveSha256: '',
      files: [],
    );

    test('an installed, consented pack is not loaded when Vulkan won', () {
      String? dir({required bool vulkanFaster}) => activeCudaPackDirFor(
        offered: true,
        downloadAllowed: true,
        enabled: true,
        state: const CudaPackState(pack: pack, installed: true),
        accepted: cudaEulaConsentValue(pack.id),
        rootDir: '/root',
        vulkanFaster: vulkanFaster,
      );

      expect(dir(vulkanFaster: false), p.join('/root', pack.id));
      expect(dir(vulkanFaster: true), isNull);
    });

    test('GTX 16 cards get the "usually slower" hint, RTX cards do not', () {
      expect(isGtx16Nvidia('NVIDIA GeForce GTX 1650'), isTrue);
      expect(isGtx16Nvidia('NVIDIA GeForce GTX 1660 SUPER'), isTrue);
      expect(isGtx16Nvidia('NVIDIA GeForce GTX 1630'), isTrue);
      expect(isGtx16Nvidia('NVIDIA GeForce RTX 3060 Ti'), isFalse);
      expect(isGtx16Nvidia('NVIDIA GeForce GTX 1080'), isFalse);
      expect(isGtx16Nvidia(''), isFalse);
    });

    test(
      'GTX 16 cards are still offered the pack (the comparison decides)',
      () {
        expect(
          isCudaPackOffered(packAvailable: true, turingOrNewerNvidia: true),
          isTrue,
        );
      },
    );
  });
}
