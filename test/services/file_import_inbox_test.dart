import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/file_import_inbox.dart';
import 'package:whispaste/services/single_instance_service.dart';

void main() {
  late Directory temp;
  late FileImportInbox inbox;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('import-inbox-test-');
    inbox = FileImportInbox(directory: temp);
  });
  tearDown(() async {
    inbox.close();
    await temp.delete(recursive: true);
  });
  test(
    'cold start and concurrent launches retain every request once',
    () async {
      final expected = List.generate(30, (i) => ['${temp.path}/$i 日本語.mpeg']);
      await Future.wait(expected.map(inbox.enqueue));
      final received = <List<String>>[];
      await inbox.drain(received.add);
      expect(
        received.map(jsonEncode),
        unorderedEquals(expected.map(jsonEncode)),
      );
      await inbox.drain(received.add);
      expect(received, hasLength(30));
      await inbox.enqueue(['${temp.path}/later.mp3']);
      await inbox.drain(received.add);
      expect(received, hasLength(31));
    },
  );
  test('malformed requests do not block later valid imports', () async {
    final bad = await temp.createTemp('bad-');
    await File('${bad.path}/ready.json').writeAsString('[42]');
    await inbox.enqueue(['${temp.path}/valid.mp3']);
    final received = <List<String>>[];
    await inbox.drain(received.add);
    expect(received.single.single, endsWith('valid.mp3'));
  });
  test(
    'only explicit imports accept absolute paths; filenames are not commands',
    () {
      expect(FileImportInbox.arguments(['${temp.path}/a.wav']), isEmpty);
      expect(
        FileImportInbox.arguments([
          '--import-files',
          'relative.wav',
          '${temp.path}/a.wav',
        ]),
        ['${temp.path}/a.wav'],
      );
      expect(
        InstanceCommand.fromArgs(['--import-files', '--cancel']),
        InstanceCommand.focus,
      );
    },
  );
  test('closed inbox retains requests until next start', () async {
    await inbox.enqueue(['${temp.path}/a.wav']);
    inbox.close();
    await inbox.drain((_) => fail('closed receiver invoked'));
    final receiver = FileImportInbox(directory: temp);
    final received = <List<String>>[];
    await receiver.drain(received.add);
    expect(received, hasLength(1));
    receiver.close();
  });
}
