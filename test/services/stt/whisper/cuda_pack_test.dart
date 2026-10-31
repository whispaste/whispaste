/// Unit tests for the optional CUDA pack: offer rules, GPU device choice,
/// and the install/remove/sweep file handling of [CudaPackStore].
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart'
    show WhisperBackend;
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart'
    show
        backendForDevice,
        ggmlDeviceTypeGpu,
        ggmlDeviceTypeIgpu,
        pickGpuDeviceIndex;

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  group('pickGpuDeviceIndex', () {
    test('prefers the CUDA device registered after Vulkan', () {
      expect(pickGpuDeviceIndex(['Vulkan0', 'CUDA0'], preferCuda: true), 1);
    });

    test('keeps the first device without a CUDA device (old driver)', () {
      expect(pickGpuDeviceIndex(['Vulkan0', 'Vulkan1'], preferCuda: true), 0);
    });

    test('ignores CUDA when the pack is not active', () {
      expect(pickGpuDeviceIndex(['Vulkan0', 'CUDA0'], preferCuda: false), 0);
    });

    test('tolerates unnamed devices', () {
      expect(pickGpuDeviceIndex([null, 'CUDA0'], preferCuda: true), 1);
    });

    test('prefers a discrete GPU over an integrated one registered first', () {
      // Hybrid laptop: ggml-vulkan enumerates the iGPU first.
      expect(
        pickGpuDeviceIndex(
          ['Vulkan0', 'Vulkan1'],
          preferCuda: false,
          gpuTypes: [ggmlDeviceTypeIgpu, ggmlDeviceTypeGpu],
        ),
        1,
      );
    });

    test('falls back to the integrated GPU when no discrete one exists', () {
      expect(
        pickGpuDeviceIndex(
          ['Vulkan0'],
          preferCuda: false,
          gpuTypes: [ggmlDeviceTypeIgpu],
        ),
        0,
      );
    });

    test('CUDA still wins over a discrete Vulkan device', () {
      expect(
        pickGpuDeviceIndex(
          ['Vulkan0', 'CUDA0'],
          preferCuda: true,
          gpuTypes: [ggmlDeviceTypeGpu, ggmlDeviceTypeGpu],
        ),
        1,
      );
    });

    test('returns the index among GPU devices only (registry order kept)', () {
      // The index is what whisper_context_params.gpu_device expects: the
      // N-th GPU/IGPU device, so the discrete card is the second of two.
      expect(
        pickGpuDeviceIndex(
          ['iGPU-A', 'dGPU-B', 'dGPU-C'],
          preferCuda: false,
          gpuTypes: [ggmlDeviceTypeIgpu, ggmlDeviceTypeGpu, ggmlDeviceTypeGpu],
        ),
        1,
      );
    });
  });

  group('backendForDevice', () {
    test('reports the backend of the device that actually runs', () {
      // CUDA requested, but only a Vulkan device is registered: say vulkan.
      expect(
        backendForDevice('Vulkan0', WhisperBackend.cuda),
        WhisperBackend.vulkan,
      );
      expect(
        backendForDevice('CUDA0', WhisperBackend.cuda),
        WhisperBackend.cuda,
      );
      expect(
        backendForDevice('MTL0', WhisperBackend.metal),
        WhisperBackend.metal,
      );
    });

    test('keeps the requested backend when the device name is unknown', () {
      expect(
        backendForDevice(null, WhisperBackend.vulkan),
        WhisperBackend.vulkan,
      );
      expect(
        backendForDevice('Something0', WhisperBackend.metal),
        WhisperBackend.metal,
      );
    });
  });

  group('isCudaPackOffered', () {
    test('only for a published pack on Turing+, in every channel', () {
      expect(
        isCudaPackOffered(packAvailable: true, turingOrNewerNvidia: true),
        isTrue,
      );
      expect(
        isCudaPackOffered(packAvailable: true, turingOrNewerNvidia: false),
        isFalse,
      );
      expect(
        isCudaPackOffered(packAvailable: false, turingOrNewerNvidia: true),
        isFalse,
      );
    });
  });

  group('isCudaPackDownloadAllowed', () {
    test('never in the Microsoft Store build, always elsewhere', () {
      expect(isCudaPackDownloadAllowed(channel: DeployChannel.store), isFalse);
      for (final channel in DeployChannel.values) {
        if (channel == DeployChannel.store) continue;
        expect(isCudaPackDownloadAllowed(channel: channel), isTrue);
      }
    });
  });

  group('BehaviorSettings.cudaAcceleration', () {
    test('defaults to on and round-trips through storage', () {
      expect(BehaviorSettings.defaults.cudaAcceleration, isTrue);
      final off = BehaviorSettings.defaults.copyWith(cudaAcceleration: false);
      expect(BehaviorSettings.fromMap(off.toMap()).cudaAcceleration, isFalse);
      expect(
        BehaviorSettings.fromMap(const {}).cudaAcceleration,
        isTrue,
        reason: 'settings saved before the key existed keep the default',
      );
    });
  });

  group('CudaPackStore', () {
    late Directory root;
    final moduleBytes = utf8.encode('fake ggml-cuda module');
    final runtimeBytes = utf8.encode('fake cuda runtime');

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cuda_pack_');
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    CudaPackInfo packFor(String archiveName, List<int> archiveBytes) =>
        CudaPackInfo(
          id: 'ggml-test-r1',
          url: 'https://example.invalid/packs/$archiveName',
          archiveSizeBytes: archiveBytes.length,
          archiveSha256: _sha(archiveBytes),
          files: [
            CudaPackFile('module.bin', moduleBytes.length, _sha(moduleBytes)),
            CudaPackFile(
              'runtime.bin',
              runtimeBytes.length,
              _sha(runtimeBytes),
            ),
          ],
        );

    List<int> zipBytes({List<int>? runtime}) {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('module.bin', moduleBytes))
        ..addFile(ArchiveFile.bytes('runtime.bin', runtime ?? runtimeBytes));
      return ZipEncoder().encodeBytes(archive);
    }

    List<int> tarGzBytes() {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('module.bin', moduleBytes))
        ..addFile(ArchiveFile.bytes('runtime.bin', runtimeBytes));
      return const GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
    }

    Future<void> stageDownload(
      CudaPackStore store,
      CudaPackInfo pack,
      List<int> bytes,
    ) async {
      final file = File(store.downloadPath(pack));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    for (final (name, build) in [
      ('pack.zip', () => zipBytes()),
      ('pack.tar.gz', () => tarGzBytes()),
    ]) {
      test('installs a verified $name and cleans up the download', () async {
        final bytes = build();
        final pack = packFor(name, bytes);
        final store = CudaPackStore(rootDir: root.path);
        await stageDownload(store, pack, bytes);

        await store.installFromArchive(pack);

        expect(isCudaPackInstalled(pack, rootDir: root.path), isTrue);
        expect(
          File(p.join(store.packDir(pack), 'module.bin')).readAsBytesSync(),
          moduleBytes,
        );
        expect(
          Directory('${store.packDir(pack)}.partial').existsSync(),
          isFalse,
        );
        expect(File(store.downloadPath(pack)).existsSync(), isFalse);
      });
    }

    test('rejects an archive whose checksum does not match', () async {
      final bytes = zipBytes();
      final pack = packFor('pack.zip', bytes);
      final store = CudaPackStore(rootDir: root.path);
      await stageDownload(store, pack, [...bytes, 0]);

      await expectLater(
        store.installFromArchive(pack),
        throwsA(isA<CudaPackVerificationException>()),
      );
      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);
      expect(File(store.downloadPath(pack)).existsSync(), isFalse);
    });

    test('rejects a pack whose files do not match their pins', () async {
      final bytes = zipBytes(runtime: utf8.encode('tampered'));
      final good = packFor('pack.zip', zipBytes());
      // Archive checksum matches the tampered archive, file pins do not.
      final pack = CudaPackInfo(
        id: good.id,
        url: good.url,
        archiveSizeBytes: bytes.length,
        archiveSha256: _sha(bytes),
        files: good.files,
      );
      final store = CudaPackStore(rootDir: root.path);
      await stageDownload(store, pack, bytes);

      await expectLater(
        store.installFromArchive(pack),
        throwsA(isA<CudaPackVerificationException>()),
      );
      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);
      expect(Directory(store.packDir(pack)).existsSync(), isFalse);
      expect(Directory('${store.packDir(pack)}.partial').existsSync(), isFalse);
    });

    test('a truncated or missing file makes the pack not installed', () async {
      final bytes = zipBytes();
      final pack = packFor('pack.zip', bytes);
      final store = CudaPackStore(rootDir: root.path);
      await stageDownload(store, pack, bytes);
      await store.installFromArchive(pack);
      final module = File(p.join(store.packDir(pack), 'module.bin'));

      module.writeAsBytesSync(moduleBytes.sublist(0, 4));
      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);

      module.deleteSync();
      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);
    });

    test('remove deletes the pack folder', () async {
      final bytes = zipBytes();
      final pack = packFor('pack.zip', bytes);
      final store = CudaPackStore(rootDir: root.path);
      await stageDownload(store, pack, bytes);
      await store.installFromArchive(pack);

      await store.remove(pack);

      expect(Directory(store.packDir(pack)).existsSync(), isFalse);
      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);
    });

    test('a pending removal hides the pack, is undone by a reinstall, '
        'and is carried out by the next sweep', () async {
      final bytes = zipBytes();
      final pack = packFor('pack.zip', bytes);
      final store = CudaPackStore(rootDir: root.path);
      await stageDownload(store, pack, bytes);
      await store.installFromArchive(pack);
      // What remove() leaves behind when Windows keeps the DLLs locked.
      final pending = File(p.join(root.path, '.remove-${pack.id}'))
        ..writeAsStringSync('');

      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);
      expect(store.cancelPendingRemoval(pack), isTrue);
      expect(isCudaPackInstalled(pack, rootDir: root.path), isTrue);

      pending.writeAsStringSync('');
      store.sweep(pack);
      expect(pending.existsSync(), isFalse);
      expect(Directory(store.packDir(pack)).existsSync(), isFalse);
    });

    test('a failed extraction (e.g. disk full) removes the staging folder at '
        'once instead of leaving up to ~1 GB until the next launch', () async {
      final bytes = zipBytes();
      final pack = packFor('pack.zip', bytes);
      final store = CudaPackStore(
        rootDir: root.path,
        extract: (archive, outDir) async {
          File(p.join(outDir, 'module.bin')).writeAsBytesSync(moduleBytes);
          throw const FileSystemException('No space left on device');
        },
      );
      await stageDownload(store, pack, bytes);

      await expectLater(
        store.installFromArchive(pack),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory('${store.packDir(pack)}.partial').existsSync(), isFalse);
      expect(isCudaPackInstalled(pack, rootDir: root.path), isFalse);
    });

    test('sweep removes other pack ids and staging folders, keeps the '
        'current pack and its resumable download', () async {
      final bytes = zipBytes();
      final pack = packFor('pack.zip', bytes);
      final store = CudaPackStore(rootDir: root.path);
      Directory(p.join(root.path, 'ggml-old-r1')).createSync();
      Directory(p.join(root.path, '${pack.id}.partial')).createSync();
      Directory(store.packDir(pack)).createSync();
      await stageDownload(store, pack, bytes);

      store.sweep(pack);

      expect(Directory(p.join(root.path, 'ggml-old-r1')).existsSync(), isFalse);
      expect(
        Directory(p.join(root.path, '${pack.id}.partial')).existsSync(),
        isFalse,
      );
      expect(Directory(store.packDir(pack)).existsSync(), isTrue);
      expect(File(store.downloadPath(pack)).existsSync(), isTrue);
    });
  });
}
