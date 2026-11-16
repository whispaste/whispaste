// Files opened while the first-run onboarding is on top (#1705): the app
// must keep them and hand them over once it closes, never drop them.
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/single_instance_service.dart';

void main() {
  final memo = p.join(p.current, 'memo.wav');
  final second = p.join(p.current, 'second.mp3');

  tearDown(() async {
    SingleInstanceService.onOpenFiles = null;
    // Clears whatever a test left queued.
    await SingleInstanceService.release();
  });

  test('files opened during the onboarding wait and run after it', () {
    final received = <List<String>>[];
    void handler(List<String> paths) => received.add(paths);

    // The onboarding is on top: not ready.
    SingleInstanceService.deliverOpenFilesWhen(ready: false, handler: handler);
    SingleInstanceService.openUrls([Uri.file(memo).toString()]);
    SingleInstanceService.openUrls([Uri.file(second).toString()]);
    expect(received, isEmpty, reason: 'nothing may run behind the overlay');

    // The onboarding closed.
    SingleInstanceService.deliverOpenFilesWhen(ready: true, handler: handler);
    expect(received, [
      [memo],
      [second],
    ]);

    // Handed over once: setting the handler again repeats nothing.
    SingleInstanceService.deliverOpenFilesWhen(ready: true, handler: handler);
    expect(received, hasLength(2));
  });

  test('negative control: without an onboarding the file runs at once', () {
    final received = <List<String>>[];
    SingleInstanceService.deliverOpenFilesWhen(
      ready: true,
      handler: received.add,
    );
    SingleInstanceService.openUrls([Uri.file(memo).toString()]);
    expect(received, [
      [memo],
    ]);
  });

  test('a file taken by a handler that was rebuilt meanwhile is kept', () {
    // The old shell took the file, then was rebuilt before it could import
    // it; its dispose cleared the handler.
    SingleInstanceService.onOpenFiles = null;
    SingleInstanceService.requeueOpenFiles([memo]);

    final received = <List<String>>[];
    SingleInstanceService.deliverOpenFilesWhen(
      ready: true,
      handler: received.add,
    );
    expect(received, [
      [memo],
    ]);
  });

  test('an onboarding reopened later holds new files again', () {
    final received = <List<String>>[];
    void handler(List<String> paths) => received.add(paths);

    SingleInstanceService.deliverOpenFilesWhen(ready: true, handler: handler);
    SingleInstanceService.deliverOpenFilesWhen(ready: false, handler: handler);
    SingleInstanceService.openUrls([Uri.file(memo).toString()]);
    expect(received, isEmpty);

    SingleInstanceService.deliverOpenFilesWhen(ready: true, handler: handler);
    expect(received, [
      [memo],
    ]);
  });
}
