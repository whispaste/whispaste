// Hand-off points of "Transcribe with WhisPaste" (#1684): the launch
// argument or the opened URL becomes a file path, a cold start queues it for
// the file transcription, and a second launch hands it to the running
// instance instead of starting a second app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/opened_files.dart';
import 'package:whispaste/services/single_instance_service.dart';

void main() {
  group('openedFilesFromArgs', () {
    final posix = p.Context(style: p.Style.posix, current: '/home/ada');
    final windows = p.Context(style: p.Style.windows, current: r'C:\Users\a');

    test('Windows verb: the quoted path arrives as one argument', () {
      expect(
        openedFilesFromArgs(const [
          r'C:\Users\a\Music\memo 1.mp3',
        ], context: windows),
        [r'C:\Users\a\Music\memo 1.mp3'],
      );
    });

    test('Linux %U: file URIs are decoded, several files in one launch', () {
      expect(
        openedFilesFromArgs(const [
          'file:///home/ada/Musik/Notiz%20eins.m4a',
          'file:///home/ada/b.ogg',
        ], context: posix),
        ['/home/ada/Musik/Notiz eins.m4a', '/home/ada/b.ogg'],
      );
    });

    test('a relative path from a terminal resolves against the folder', () {
      expect(openedFilesFromArgs(const ['memo.wav'], context: posix), [
        '/home/ada/memo.wav',
      ]);
    });

    test('flags, app links and other schemes are no files', () {
      expect(
        openedFilesFromArgs(const [
          '--autostart',
          '--toggle',
          'whispaste://newsletter/confirmed',
          'https://example.org/a.mp3',
          '',
        ], context: posix),
        isEmpty,
      );
    });
  });

  group('SingleInstanceService file hand-off', () {
    late Directory tmp;
    final originalClock = SingleInstanceService.clock;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('whispaste_open_files_');
      SingleInstanceService.lockDirOverride = tmp.path;
      SingleInstanceService.clock = () => DateTime(2026, 11, 16, 12);
    });

    tearDown(() async {
      await SingleInstanceService.release();
      SingleInstanceService.clock = originalClock;
      SingleInstanceService.onOpenFiles = null;
      SingleInstanceService.onSecondInstanceLaunched = null;
      SingleInstanceService.lockDirOverride = null;
      SingleInstanceService.debugResetClaim();
      tmp.deleteSync(recursive: true);
    });

    test(
      'a cold start with files queues them until the import is wired up',
      () async {
        final primary = await SingleInstanceService.ensureSingleInstance(
          openFiles: const ['/m/a.mp3', '/m/b.wav'],
        );
        expect(primary, isTrue);

        final received = <List<String>>[];
        SingleInstanceService.onOpenFiles = received.add;
        expect(received, [
          ['/m/a.mp3', '/m/b.wav'],
        ]);
      },
    );

    test('files of second launches reach the running instance, none lost '
        'when several arrive at once', () async {
      expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
      final received = <List<String>>[];
      SingleInstanceService.onOpenFiles = received.add;
      var focused = 0;
      SingleInstanceService.onSecondInstanceLaunched = () => focused++;

      // Explorer starts one process per selected file; their requests can
      // land before the running instance reads the first signal.
      await SingleInstanceService.debugSignalOpenFiles(tmp.path, const [
        r'C:\m\a.mp3',
      ]);
      await SingleInstanceService.debugSignalOpenFiles(tmp.path, const [
        r'C:\m\b.flac',
      ]);
      await SingleInstanceService.debugReadSignal(tmp.path);

      expect(received.expand((files) => files).toSet(), {
        r'C:\m\a.mp3',
        r'C:\m\b.flac',
      });
      expect(received.expand((files) => files), hasLength(2));
      expect(focused, 0, reason: 'files are not a plain focus request');
      expect(
        Directory(p.join(tmp.path, 'open_files')).listSync(),
        isEmpty,
        reason: 'every request is read once and removed',
      );
    });

    test(
      'a request left over from an earlier run is dropped at start',
      () async {
        final folder = Directory(p.join(tmp.path, 'open_files'))
          ..createSync(recursive: true);
        File(p.join(folder.path, '1-1-1.req'))
          ..writeAsStringSync(jsonEncode(['/m/old.mp3']))
          ..setLastModifiedSync(DateTime(2020));

        expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
        final received = <List<String>>[];
        SingleInstanceService.onOpenFiles = received.add;

        expect(received, isEmpty);
        expect(folder.listSync(), isEmpty);
      },
    );

    test('macOS: opened file URLs go to the file transcription, links keep '
        'their meaning', () {
      final received = <List<String>>[];
      SingleInstanceService.onOpenFiles = received.add;
      var focused = 0;
      SingleInstanceService.onSecondInstanceLaunched = () => focused++;

      SingleInstanceService.openUrls(const [
        'file:///Users/ada/Desktop/Memo%201.m4a',
        'file:///Users/ada/Desktop/b.opus',
        'whispaste://somewhere',
      ]);

      String path(String url) => p.normalize(Uri.parse(url).toFilePath());
      expect(received, [
        [
          path('file:///Users/ada/Desktop/Memo%201.m4a'),
          path('file:///Users/ada/Desktop/b.opus'),
        ],
      ]);
      expect(focused, 1);
    });
  });
}
