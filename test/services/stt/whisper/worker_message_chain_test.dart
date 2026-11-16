import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_isolate_engine.dart';

void main() {
  group('chainWorkerMessages', () {
    test('a handler that throws does not stop later messages', () async {
      final handled = Completer<String>();
      final dispatch = chainWorkerMessages((message) async {
        if (message == 'boom') throw StateError('unexpected');
        handled.complete(message as String);
      });

      dispatch('boom');
      dispatch('unload');

      expect(
        await handled.future.timeout(const Duration(seconds: 2)),
        'unload',
      );
    });

    test('messages are handled one at a time, in order', () async {
      final order = <String>[];
      final done = Completer<void>();
      final dispatch = chainWorkerMessages((message) async {
        await Future<void>.delayed(Duration.zero);
        order.add(message as String);
        if (order.length == 3) done.complete();
      });

      dispatch('a');
      dispatch('b');
      dispatch('c');

      await done.future.timeout(const Duration(seconds: 2));
      expect(order, ['a', 'b', 'c']);
    });
  });
}
