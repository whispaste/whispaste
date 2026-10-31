import 'dart:convert';
import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/retention/pending_wipe.dart';
import 'package:whispaste/services/path_service.dart' as paths;

/// In-memory file system that still reports [vanishing] as a file after it was
/// removed, as if the file went away between the type check and the stat.
class _StaleTypeFileSystem extends ForwardingFileSystem {
  _StaleTypeFileSystem(this.vanishing) : super(MemoryFileSystem());

  final String vanishing;
  var armed = false;

  @override
  Future<io.FileSystemEntityType> type(
    String path, {
    bool followLinks = true,
  }) async {
    if (armed && path == vanishing) return io.FileSystemEntityType.file;
    return delegate.type(path, followLinks: followLinks);
  }
}

io.Directory _setUpRoot(String prefix) {
  final root = io.Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => root.deleteSync(recursive: true));
  paths.appDataDirOverride = root.path;
  addTearDown(() => paths.appDataDirOverride = null);
  paths.retainedAudioDirOverride = p.join(root.path, 'recordings');
  addTearDown(() => paths.retainedAudioDirOverride = null);
  io.Directory(paths.retainedAudioDir()).createSync(recursive: true);
  return root;
}

io.File _audio(String name, String content) =>
    io.File(p.join(paths.retainedAudioDir(), name))..writeAsStringSync(content);

Future<Set<String>> _none() async => <String>{};

void main() {
  test(
    'a queued file is removed while its size and mtime still match',
    () async {
      _setUpRoot('wp71-sig-match-');
      final wav = _audio('whispaste_1.wav', 'pcm');
      expect(await recordPendingWipe([wav.path]), isTrue);

      final remaining = await applyPendingWipe(referencedPaths: _none);

      expect(remaining, 0);
      expect(wav.existsSync(), isFalse);
      expect(io.File(paths.pendingWipeFile()).existsSync(), isFalse);
    },
  );

  test(
    'the same path with other content is kept and its entry dropped',
    () async {
      _setUpRoot('wp71-sig-size-');
      final wav = _audio('whispaste_1.wav', 'pcm');
      expect(await recordPendingWipe([wav.path]), isTrue);
      wav.writeAsStringSync('a much longer new recording');

      final remaining = await applyPendingWipe(referencedPaths: _none);

      expect(remaining, 0);
      expect(
        wav.existsSync(),
        isTrue,
        reason: 'a new file is not ours to delete',
      );
      expect(io.File(paths.pendingWipeFile()).existsSync(), isFalse);
    },
  );

  test('the same path with the same size but another mtime is kept', () async {
    _setUpRoot('wp71-sig-mtime-');
    final wav = _audio('whispaste_1.wav', 'pcm');
    expect(await recordPendingWipe([wav.path]), isTrue);
    wav.writeAsStringSync('new');
    wav.setLastModifiedSync(DateTime(2001));

    final remaining = await applyPendingWipe(referencedPaths: _none);

    expect(remaining, 0);
    expect(wav.existsSync(), isTrue);
  });

  test(
    'entries without a signature are dropped and their files kept',
    () async {
      _setUpRoot('wp71-sig-legacy-');
      final wav = _audio('whispaste_1.wav', 'pcm');
      io.File(paths.pendingWipeFile())
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({wav.path: 1700000000000}));

      final remaining = await applyPendingWipe(referencedPaths: _none);

      expect(remaining, 0);
      expect(
        wav.existsSync(),
        isTrue,
        reason: 'unsigned entries are not acted on',
      );
      expect(io.File(paths.pendingWipeFile()).existsSync(), isFalse);
    },
  );

  test(
    'a file that vanishes before its stat is done counts as done and the loop goes on',
    () async {
      _setUpRoot('wp71-sig-vanish-');
      final gonePath = p.join(paths.retainedAudioDir(), 'gone.wav');
      final otherPath = p.join(paths.retainedAudioDir(), 'other.wav');
      final fs = _StaleTypeFileSystem(gonePath);
      fs.file(gonePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('pcm');
      fs.file(otherPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('pcm');
      expect(
        await recordPendingWipe([gonePath, otherPath], fileSystem: fs),
        isTrue,
      );
      fs.file(gonePath).deleteSync();
      fs.armed = true;

      final remaining = await applyPendingWipe(
        referencedPaths: _none,
        fileSystem: fs,
      );

      expect(remaining, 0, reason: 'the vanished entry counts as done');
      expect(
        fs.file(otherPath).existsSync(),
        isFalse,
        reason: 'the next entry is still removed',
      );
    },
  );

  test('overlapping calls share one pass', () async {
    _setUpRoot('wp71-sig-once-');
    final wav = _audio('whispaste_1.wav', 'pcm');
    expect(await recordPendingWipe([wav.path]), isTrue);
    var passes = 0;
    Future<Set<String>> counted() async {
      passes++;
      return <String>{};
    }

    final results = await Future.wait([
      applyPendingWipe(referencedPaths: counted),
      applyPendingWipe(referencedPaths: counted),
    ]);

    expect(passes, 1);
    expect(results, [0, 0]);
    expect(wav.existsSync(), isFalse);
  });
}
