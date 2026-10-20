import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/import/audio_drop_intake.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

void main() async {
  late Directory dir;
  const extensions = {'wav', 'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus'};

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wp-drop-intake-');
  });

  tearDown(() async {
    dir.deleteSync(recursive: true);
  });

  String file(String name) {
    final f = File(p.join(dir.path, name))..writeAsBytesSync(const [0]);
    return f.path;
  }

  test('queues every supported file in drop order', () async {
    final a = file('memo.m4a');
    final b = file('call.OGG');
    final split = await splitAudioDrop([a, b], extensions: extensions);
    expect(split.accepted, [a, b]);
    expect(split.rejected, isEmpty);
  });

  test(
    'refuses folders, unsupported files and missing paths separately',
    () async {
      final ok = file('talk.mp3');
      final folder = Directory(p.join(dir.path, 'recordings.mp3'))
        ..createSync();
      final text = file('notes.txt');
      final missing = p.join(dir.path, 'gone.wav');

      final split = await splitAudioDrop([
        folder.path,
        text,
        ok,
        missing,
      ], extensions: extensions);

      expect(split.accepted, [ok]);
      expect(
        {for (final r in split.rejected) r.reason},
        {
          AudioDropRejection.folder,
          AudioDropRejection.unsupportedFormat,
          AudioDropRejection.notFound,
        },
      );
      // A folder named like an audio file is a folder, not a format error.
      expect(
        split.rejected.singleWhere((r) => r.path == folder.path).reason,
        AudioDropRejection.folder,
      );
    },
  );

  test('accepts nothing when no path is supported', () async {
    final split = await splitAudioDrop([file('a.txt')], extensions: extensions);
    expect(split.accepted, isEmpty);
    expect(split.rejected.single.reason, AudioDropRejection.unsupportedFormat);
  });

  // FIFOs and device nodes need a POSIX system; Windows has no such paths.
  final posix = !Platform.isWindows;

  test(
    'refuses a FIFO and a character device',
    () async {
      final fifo = p.join(dir.path, 'pipe.wav');
      final made = Process.runSync('mkfifo', [fifo]);
      expect(made.exitCode, 0);
      final split = await splitAudioDrop([
        fifo,
        '/dev/null',
      ], extensions: extensions);
      expect(split.accepted, isEmpty);
      expect(
        split.rejected.map((r) => r.reason),
        everyElement(AudioDropRejection.notRegularFile),
      );
    },
    skip: posix ? null : 'POSIX file types only',
  );

  test(
    'refuses a symlink to a non-regular file, and follows a link to a regular one',
    () async {
      final link = Link(p.join(dir.path, 'null.wav'));
      link.createSync('/dev/null');
      final real = file('real.mp3');
      final alias = Link(p.join(dir.path, 'alias.mp3'))..createSync(real);

      final split = await splitAudioDrop([
        link.path,
        alias.path,
      ], extensions: extensions);
      expect(split.accepted, [alias.path]);
      expect(split.rejected.single.reason, AudioDropRejection.notRegularFile);

      final resolved = await inspectImportSource(alias.path);
      expect(resolved.kind, ImportSourceKind.regularFile);
      expect(resolved.resolvedPath, File(real).resolveSymbolicLinksSync());
    },
    skip: posix ? null : 'symlinks need developer mode on Windows',
  );

  test(
    'refuses a file above the size limit before anything is copied',
    () async {
      final big = File(p.join(dir.path, 'long.wav'))
        ..writeAsBytesSync(List<int>.filled(11, 0));
      final split = await splitAudioDrop(
        [big.path],
        extensions: extensions,
        maxBytes: 10,
      );
      expect(split.accepted, isEmpty);
      expect(split.rejected.single.reason, AudioDropRejection.tooLarge);
    },
  );

  test('the default limit is the 1 GB import cap', () async {
    expect(kMaxImportFileBytes, 1000000000);
  });

  test(
    'refuses Windows reserved device names in any case and with any extension',
    () async {
      for (final name in [
        'CON.mp3',
        'nul',
        'Aux.WAV',
        'com1.ogg',
        'LPT9.flac',
        'prn.m4a',
        'CONIN\$.mp3',
        'conout\$.wav',
        'COM\u00b9.ogg',
        'lpt\u00b2.flac',
        'COM\u00b3.m4a',
        'COM0.wav',
        'lpt0.mp3',
        'NUL:',
        'CON:',
        'COM1:',
        'NUL:stream',
        'nul:stream.wav',
      ]) {
        expect(
          isReservedDeviceName(p.join(dir.path, name)),
          isTrue,
          reason: name,
        );
      }
      for (final name in [
        'console.mp3',
        'nullable.wav',
        'COM10.mp3',
        'COM\u2074.mp3',
        'memo.m4a',
      ]) {
        expect(
          isReservedDeviceName(p.join(dir.path, name)),
          isFalse,
          reason: name,
        );
      }
      // Device namespaces are matched on the whole path, not the basename.
      for (final path in [
        r'\\.\C:\memo.mp3',
        r'\\?\C:\memo.mp3',
        '//./pipe/x.mp3',
        '//?/C:/memo.mp3',
        r'\??\C:\memo.mp3',
        '//??/C:/memo.mp3',
      ]) {
        expect(isReservedDeviceName(path), isTrue, reason: path);
      }
      // Refused by name, before anything is opened: the file need not exist.
      final split = await splitAudioDrop([
        p.join(dir.path, 'CON.mp3'),
        p.join(dir.path, 'lpt1.wav'),
      ], extensions: extensions);
      expect(split.accepted, isEmpty);
      expect(
        split.rejected.map((r) => r.reason),
        everyElement(AudioDropRejection.reservedName),
      );
    },
  );
}
