import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/audio/user_audio_migration.dart';

void main() {
  late Directory tmp;
  late String from;
  late String to;

  File write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_audio_move_');
    from = p.join(tmp.path, 'roaming', 'WhisPaste');
    to = p.join(tmp.path, 'local', 'WhisPaste');
    Directory(from).createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('moves every audio folder and leaves other app data alone', () async {
    write(p.join(from, 'recordings', 'a.wav'), 'a');
    write(p.join(from, 'pending-audio', 'b.wav'), 'b');
    write(p.join(from, 'imports', 'work', 'job', 'source.mp3'), 'c');
    write(p.join(from, 'history.db'), 'db');

    expect(await moveUserAudio(from: from, to: to), 0);

    expect(File(p.join(to, 'recordings', 'a.wav')).readAsStringSync(), 'a');
    expect(File(p.join(to, 'pending-audio', 'b.wav')).existsSync(), isTrue);
    expect(
      File(p.join(to, 'imports', 'work', 'job', 'source.mp3')).existsSync(),
      isTrue,
    );
    for (final name in userAudioFolderNames) {
      expect(Directory(p.join(from, name)).existsSync(), isFalse);
    }
    expect(File(p.join(from, 'history.db')).existsSync(), isTrue);
  });

  test('merges into an existing folder and keeps both on a clash', () async {
    write(p.join(from, 'recordings', 'old.wav'), 'old');
    write(p.join(from, 'recordings', 'same.wav'), 'roaming');
    write(p.join(to, 'recordings', 'same.wav'), 'local');

    expect(await moveUserAudio(from: from, to: to), 1);

    expect(File(p.join(to, 'recordings', 'old.wav')).existsSync(), isTrue);
    expect(
      File(p.join(to, 'recordings', 'same.wav')).readAsStringSync(),
      'local',
    );
    expect(
      File(p.join(from, 'recordings', 'same.wav')).readAsStringSync(),
      'roaming',
      reason: 'never deleted, retried next start',
    );
  });

  test('rewrites journal paths that point into the old folder', () async {
    final oldWav = p.join(from, 'recordings', 'x.wav');
    write(oldWav, 'x');
    write(
      p.join(from, 'recordings', 'journal', 'tx-1.json'),
      jsonEncode({'id': 'tx-1', 'wavPath': oldWav, 'entryId': '1'}),
    );
    final capture = p.join(tmp.path, 'capture', 'whispaste_1.wav');
    write(
      p.join(from, 'recordings', 'journal', 'rec-2.json'),
      jsonEncode({'id': 'rec-2', 'wavPath': capture}),
    );

    await moveUserAudio(from: from, to: to);

    Map<String, dynamic> read(String name) =>
        jsonDecode(
              File(
                p.join(to, 'recordings', 'journal', name),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(read('tx-1.json'), {
      'id': 'tx-1',
      'wavPath': p.join(to, 'recordings', 'x.wav'),
      'entryId': '1',
    });
    expect(read('rec-2.json')['wavPath'], capture);
  });

  test('does nothing when there is nothing to move', () async {
    expect(await moveUserAudio(from: from, to: to), 0);
    expect(Directory(to).existsSync(), isFalse);
    expect(await moveUserAudio(from: from, to: from), 0);
  });
}
