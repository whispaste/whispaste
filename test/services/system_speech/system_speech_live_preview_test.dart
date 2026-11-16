import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/system_speech/system_speech_channel.dart';
import 'package:whispaste/services/system_speech/system_speech_live_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const name = 'whispaste/system_speech';
  late MethodChannel channel;
  late SystemSpeechLivePreview preview;
  late List<MethodCall> calls;
  late Completer<bool> startGate;

  setUp(() {
    channel = const MethodChannel(name);
    calls = [];
    startGate = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'liveStart') return startGate.future;
          return null;
        });
    preview = SystemSpeechLivePreview(SystemSpeechChannel())..attach();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    preview.dispose();
  });

  Future<void> host(String text) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .handlePlatformMessage(
        name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('livePartial', text),
        ),
        (_) {},
      );

  test(
    'chunks before the host is ready are delivered after liveStart',
    () async {
      final started = preview.start('de');
      preview.feed(Uint8List.fromList([1, 2]));
      startGate.complete(true);
      await started;
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), ['liveStart', 'liveFeed']);
    },
  );

  test('a failed start drops chunks and shows nothing', () async {
    final started = preview.start('de');
    preview.feed(Uint8List.fromList([1, 2]));
    startGate.complete(false);
    await started;
    preview.feed(Uint8List.fromList([3]));
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), ['liveStart']);
    final seen = <String>[];
    preview.preview.listen(seen.add);
    await host('hallo');
    expect(seen, isEmpty);
  });

  test(
    'interim text reaches the stream only while running; stop ends it',
    () async {
      startGate.complete(true);
      await preview.start('de');
      final seen = <String>[];
      preview.preview.listen(seen.add);
      await host('hallo wel');
      await host('hallo welt');
      expect(seen, ['hallo wel', 'hallo welt']);
      await preview.stop();
      await host('spät');
      expect(seen.length, 2);
      expect(calls.last.method, 'liveStop');
    },
  );

  test('stop without a start never touches the host', () async {
    await preview.stop();
    expect(calls, isEmpty);
  });
}
