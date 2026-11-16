/// The Dock bounce is a best-effort hint (#459): a host without the native
/// handler, or one that fails, must not break the flow that asked for it.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/macos_lifecycle_channel.dart';

const _channel = MethodChannel('com.whispaste.app_lifecycle');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  final skipOffMac = Platform.isMacOS ? false : 'macOS-only channel';

  test('request and cancel without a platform handler do not throw', () async {
    // No handler registered: invokeMethod raises MissingPluginException.
    final token = await MacOSLifecycleChannel.requestUserAttention();
    expect(token, isNull);
    await MacOSLifecycleChannel.cancelUserAttention(1);
  }, skip: skipOffMac);

  test('a failing native side yields no token and a quiet cancel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(code: 'boom');
        });
    expect(await MacOSLifecycleChannel.requestUserAttention(), isNull);
    await MacOSLifecycleChannel.cancelUserAttention(1);
  }, skip: skipOffMac);

  test('the native token is handed back and cancel passes it on', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return call.method == 'requestUserAttention' ? 7 : null;
        });
    final token = await MacOSLifecycleChannel.requestUserAttention(
      critical: false,
    );
    expect(token, 7);
    await MacOSLifecycleChannel.cancelUserAttention(token!);
    expect(calls.map((c) => c.method), [
      'requestUserAttention',
      'cancelUserAttentionRequest',
    ]);
    expect(calls.last.arguments, {'token': 7});
  }, skip: skipOffMac);
}
