import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/audio/capture/capture_dir.dart';
import 'package:whispaste/services/audio/user_audio_dirs.dart';

/// Counts process calls so the per-process cache is observable.
class _CountingProcess {
  int calls = 0;
  String? ownerUid;

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls++;
    if (exe == 'stat' && ownerUid != null) {
      return ProcessResult(1, 0, '$ownerUid\n', '');
    }
    return Process.run(exe, args);
  }
}

final _posixSkip = Platform.isWindows ? 'POSIX permissions only' : null;

int _mode(String path) => FileStat.statSync(path).mode & 0x1FF;

void main() {
  late Directory root;
  late _CountingProcess process;
  late UserAudioDirs dirs;
  late List<LogRecord> warnings;
  late List<String> listed;

  // A foreign owner can only be faked through the `stat` process. On macOS
  // the owner is read in process (libc, see capture_dir.dart), so the owner
  // cases use the POSIX process path, which runs on every POSIX host with
  // that host's own `stat` syntax. The native path is covered by
  // posix_native_test.
  UserAudioDirs makeDirs({required bool viaProcesses}) => UserAudioDirs(
    system: () => CaptureSystem(
      platform: Platform.isMacOS && !viaProcesses
          ? CapturePlatform.macos
          : CapturePlatform.linux,
      environment: const {},
      appDataDir: root.path,
      runProcess: process.call,
    ),
    directories: () => listed,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('wp_user_audio_');
    process = _CountingProcess();
    listed = [];
    dirs = makeDirs(viaProcesses: false);
    warnings = [];
    Logger.root.level = Level.ALL;
    Logger.root.onRecord
        .where((r) => r.level >= Level.WARNING)
        .listen(warnings.add);
  });

  tearDown(() {
    Logger.root.clearListeners();
    root.deleteSync(recursive: true);
  });

  group('ensure', () {
    test('creates a missing audio folder with mode 0700', () async {
      final dir = p.join(root.path, 'recordings');

      expect(await dirs.ensure(dir), isTrue);
      expect(_mode(dir), 0x1C0);
    }, skip: _posixSkip);

    test('tightens an existing 0755 audio folder to 0700', () async {
      final dir = Directory(p.join(root.path, 'pending-audio'))..createSync();
      await Process.run('chmod', ['755', dir.path]);

      expect(await dirs.ensure(dir.path), isTrue);
      expect(_mode(dir.path), 0x1C0);
    }, skip: _posixSkip);

    test('a symlinked folder is kept usable: warning, no throw, target '
        'untouched', () async {
      final target = Directory(p.join(root.path, 'elsewhere'))..createSync();
      await Process.run('chmod', ['755', target.path]);
      final link = p.join(root.path, 'recordings');
      Link(link).createSync(target.path);

      expect(await dirs.ensure(link), isFalse);
      expect(Directory(link).existsSync(), isTrue);
      expect(_mode(target.path), 0x1ED);
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains(link));
    }, skip: _posixSkip);

    test('a folder owned by someone else only warns', () async {
      process.ownerUid = '4242';
      dirs = makeDirs(viaProcesses: true);
      final dir = p.join(root.path, 'recordings');

      expect(await dirs.ensure(dir), isFalse);
      expect(Directory(dir).existsSync(), isTrue);
      expect(warnings, hasLength(1));
    }, skip: _posixSkip);

    test('a second call in the same process spawns no process', () async {
      final dir = p.join(root.path, 'recordings');
      await dirs.ensure(dir);
      final afterFirst = process.calls;

      expect(await dirs.ensure(dir), isTrue);
      expect(process.calls, afterFirst);
    }, skip: _posixSkip);

    test('a folder removed after hardening (factory reset) is created and '
        'hardened again', () async {
      final dir = p.join(root.path, 'recordings');
      await dirs.ensure(dir);
      Directory(dir).deleteSync();

      expect(await dirs.ensure(dir), isTrue);
      expect(_mode(dir), 0x1C0);
    }, skip: _posixSkip);

    test('a failed folder warns only once per process', () async {
      process.ownerUid = '4242';
      dirs = makeDirs(viaProcesses: true);
      final dir = p.join(root.path, 'recordings');
      expect(await dirs.ensure(dir), isFalse);
      expect(await dirs.ensure(dir), isFalse, reason: 'cached result');

      expect(warnings, hasLength(1));
    }, skip: _posixSkip);
  });

  group('hardenExisting', () {
    test('tightens every existing audio folder and creates none', () async {
      final retained = Directory(p.join(root.path, 'recordings'))..createSync();
      await Process.run('chmod', ['755', retained.path]);
      final missing = p.join(root.path, 'pending-audio');
      listed.addAll([retained.path, missing]);

      await dirs.hardenExisting();

      expect(_mode(retained.path), 0x1C0);
      expect(Directory(missing).existsSync(), isFalse);
    }, skip: _posixSkip);

    test('never throws, also when a folder cannot be made private', () async {
      process.ownerUid = '4242';
      dirs = makeDirs(viaProcesses: true);
      final retained = Directory(p.join(root.path, 'recordings'))..createSync();
      listed.add(retained.path);

      await expectLater(dirs.hardenExisting(), completes);
      expect(warnings, hasLength(1));
    }, skip: _posixSkip);
  });
}
