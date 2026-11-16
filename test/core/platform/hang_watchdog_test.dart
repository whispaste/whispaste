import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/hang_watchdog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(HangWatchdogClient.hangWatchdogChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('heartbeat protocol', () {
    test('arms with marker dir and threshold, then beats every 2 s', () {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      fakeAsync((async) {
        final client = HangWatchdogClient();
        client.start(markerDirectory: '/support');
        async.flushMicrotasks();
        expect(calls.single.method, 'arm');
        expect(calls.single.arguments, {
          'markerDir': '/support',
          'thresholdMs': 20000,
        });
        async.elapse(const Duration(seconds: 10));
        expect(calls.where((c) => c.method == 'beat'), hasLength(5));

        client.stop();
        async.flushMicrotasks();
        expect(calls.last.method, 'disarm');
        async.elapse(const Duration(seconds: 10));
        expect(calls.where((c) => c.method == 'beat'), hasLength(5));
      });
    });

    test('a second start neither re-arms nor doubles the beat', () {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      fakeAsync((async) {
        final client = HangWatchdogClient();
        client.start(markerDirectory: '/a');
        async.flushMicrotasks();
        client.start(markerDirectory: '/a');
        async.elapse(const Duration(seconds: 4));
        expect(calls, ['arm', 'beat', 'beat']);
        client.stop();
        async.flushMicrotasks();
      });
    });

    test('a runner without the host leaves the client idle', () {
      fakeAsync((async) {
        final client = HangWatchdogClient();
        client.start(markerDirectory: '/a');
        async.flushMicrotasks();
        expect(client.isRunning, isFalse);
      });
    });
  });

  group('hang marker', () {
    test('parses what the runners write', () {
      final m = HangMarker.parse('stalled_ms=21000\nrestarted=1\nat_ms=5\n')!;
      expect(m.restarted, isTrue);
      expect(m.stalledMs, 21000);
      expect(
        HangMarker.parse('stalled_ms=25000\nrestarted=0\n')!.restarted,
        isFalse,
      );
      expect(HangMarker.parse('garbage'), isNull);
    });

    test('is consumed exactly once', () async {
      final dir = await Directory.systemTemp.createTemp('hang_marker');
      addTearDown(() => dir.delete(recursive: true));
      await File(
        '${dir.path}${Platform.pathSeparator}$markerFileName',
      ).writeAsString('stalled_ms=22000\nrestarted=1\n');

      final first = await consumeHangMarker(dir.path);
      expect(first?.stalledMs, 22000);
      expect(await consumeHangMarker(dir.path), isNull);
    });
  });
}
