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
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart'
    show pickGpuDeviceIndex;

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
  });

  group('isCudaPackOffered', () {
    test('only for a published pack, outside the Store, on Turing+', () {
      expect(
        isCudaPackOffered(
          packAvailable: true,
          isStoreBuild: false,
          turingOrNewerNvidia: true,
        ),
        isTrue,
      );
      expect(
        isCudaPackOffered(
          packAvailable: true,
          isStoreBuild: true,
          turingOrNewerNvidia: true,
        ),
        isFalse,
      );
      expect(
        isCudaPackOffered(
          packAvailable: true,
          isStoreBuild: false,
          turingOrNewerNvidia: false,
        ),
        isFalse,
      );
      expect(
        isCudaPackOffered(
          packAvailable: false,
          isStoreBuild: false,
          turingOrNewerNvidia: true,
        ),
        isFalse,
      );
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
