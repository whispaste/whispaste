import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/transcription/slice_manifest.dart';
import 'package:whispaste/services/transcription/slice_progress.dart';
import 'package:whispaste/services/transcription/transcriber_interface.dart';

/// Records what it was asked and reports each slice it "finishes".
class _FakeResumable implements ResumableTranscriber {
  _FakeResumable(this.finish);

  /// The texts of the slices that finish, in order.
  final List<String> finish;

  List<String>? seenCompleted;
  int? seenLength;

  @override
  Future<String> transcribeResumable(
    List<int> wavBytes, {
    String? language,
    List<String> completedParts = const [],
    bool Function()? isCancelled,
    SliceCheckpoint? onSliceDone,
  }) async {
    seenCompleted = completedParts;
    seenLength = wavBytes.length;
    final parts = [...completedParts];
    final total = completedParts.length + finish.length;
    await onSliceDone?.call(List.unmodifiable(parts), total);
    for (final text in finish) {
      parts.add(text);
      await onSliceDone?.call(List.unmodifiable(parts), total);
    }
    return parts.join(' ');
  }
}

void main() {
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_slice_manifest_test_');
    path = p.join(tmp.path, 'entry.slices');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('SliceManifest', () {
    test(
      'a written manifest reads back for audio of the same length',
      () async {
        final manifest = SliceManifest(path);
        await manifest.write(1000, const ['eins', '', 'drei']);

        expect(await manifest.read(1000), ['eins', '', 'drei']);
      },
    );

    test('a manifest for audio of another length is ignored', () async {
      final manifest = SliceManifest(path);
      await manifest.write(1000, const ['eins']);

      expect(await manifest.read(1001), isEmpty);
    });

    test('a missing or unreadable manifest reads as no slices', () async {
      final manifest = SliceManifest(path);
      expect(await manifest.read(1000), isEmpty);

      File(path).writeAsStringSync('{ not json');
      expect(await manifest.read(1000), isEmpty);
    });

    test('a write leaves no temporary file behind', () async {
      await SliceManifest(path).write(1000, const ['eins']);

      expect(File('$path.tmp').existsSync(), isFalse);
      expect(File(path).existsSync(), isTrue);
    });

    test('a failed write keeps the previous manifest', () async {
      final manifest = SliceManifest(path);
      await manifest.write(1000, const ['eins']);
      // A directory where the temporary file should go makes the write fail.
      Directory('$path.tmp').createSync();

      await manifest.write(1000, const ['eins', 'zwei']);

      expect(await manifest.read(1000), ['eins']);
    });

    test(
      'delete removes the manifest and is a no-op when it is missing',
      () async {
        final manifest = SliceManifest(path);
        await manifest.write(1000, const ['eins']);

        await manifest.delete();
        await manifest.delete();

        expect(File(path).existsSync(), isFalse);
      },
    );

    test(
      'moveTo moves the manifest, or does nothing when it is missing',
      () async {
        final dest = p.join(tmp.path, 'moved.slices');
        await SliceManifest(path).moveTo(dest);
        expect(File(dest).existsSync(), isFalse);

        await SliceManifest(path).write(1000, const ['eins']);
        await SliceManifest(path).moveTo(dest);

        expect(File(path).existsSync(), isFalse);
        expect(await SliceManifest(dest).read(1000), ['eins']);
      },
    );

    test('a written manifest is readable by the owner only (POSIX)', () async {
      if (Platform.isWindows) return;
      await SliceManifest(path).write(1000, const ['eins']);

      expect(FileStat.statSync(path).mode & 0x1FF, 0x180);
    });

    test('beside takes the extension of the audio file', () {
      expect(
        SliceManifest.beside(p.join('/x', 'abc.wav')).path,
        p.join('/x', 'abc.slices'),
      );
    });
  });

  group('SliceCheckpointWriter', () {
    test('writes only when a new slice has finished', () async {
      final manifest = SliceManifest(path);
      final writer = SliceCheckpointWriter(
        manifest: manifest,
        wavLength: 1000,
        persisted: 0,
      );

      // Before the first request: nothing finished, nothing written.
      await writer(const [], 3);
      expect(File(path).existsSync(), isFalse);

      await writer(const ['eins'], 3);
      expect(await manifest.read(1000), ['eins']);

      // A call without a new slice does not touch the file.
      File(path).writeAsStringSync('marker');
      await writer(const ['eins'], 3);
      expect(File(path).readAsStringSync(), 'marker');
    });

    test('a resumed run does not rewrite the slices it was given', () async {
      final manifest = SliceManifest(path);
      await manifest.write(1000, const ['eins']);
      final writer = SliceCheckpointWriter(
        manifest: manifest,
        wavLength: 1000,
        persisted: 1,
      );

      File(path).writeAsStringSync('marker');
      await writer(const ['eins'], 3);
      expect(File(path).readAsStringSync(), 'marker');

      await writer(const ['eins', 'zwei'], 3);
      expect(await manifest.read(1000), ['eins', 'zwei']);
    });
  });

  group('transcribeWithSliceManifest', () {
    test(
      'sends only the slices the manifest lacks and saves the new ones',
      () async {
        final manifest = SliceManifest(path);
        await manifest.write(1000, const ['eins']);
        final transcriber = _FakeResumable(const ['zwei', 'drei']);

        final text = await transcribeWithSliceManifest(
          transcriber,
          List.filled(1000, 0),
          manifestPath: path,
        );

        expect(text, 'eins zwei drei');
        expect(transcriber.seenCompleted, ['eins']);
        expect(transcriber.seenLength, 1000);
        expect(await manifest.read(1000), ['eins', 'zwei', 'drei']);
      },
    );

    test('a manifest of other audio is not reused', () async {
      await SliceManifest(path).write(999, const ['alt']);
      final transcriber = _FakeResumable(const ['neu']);

      await transcribeWithSliceManifest(
        transcriber,
        List.filled(1000, 0),
        manifestPath: path,
      );

      expect(transcriber.seenCompleted, isEmpty);
    });
  });

  group('SliceProgress', () {
    test('counts the slice in progress from 1 and never above the total', () {
      expect(const SliceProgress(done: 0, total: 3).current, 1);
      expect(const SliceProgress(done: 2, total: 3).current, 3);
      expect(const SliceProgress(done: 3, total: 3).current, 3);
      expect(const SliceProgress(done: 0, total: 1).isSliced, isFalse);
      expect(const SliceProgress(done: 0, total: 2).isSliced, isTrue);
    });

    test('the provider holds the latest report until it is cleared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        transcriptionSliceProgressProvider.notifier,
      );
      expect(container.read(transcriptionSliceProgressProvider), isNull);

      notifier.report(done: 1, total: 4);
      final progress = container.read(transcriptionSliceProgressProvider);
      expect(progress?.current, 2);
      expect(progress?.total, 4);

      notifier.clear();
      expect(container.read(transcriptionSliceProgressProvider), isNull);
    });
  });
}
