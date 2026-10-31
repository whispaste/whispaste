/// Tests for [MacOSLifecycleChannel.wasLaunchedAsLoginItem] — the macOS
/// Login-Item signal `shouldMinimize` needs, because an `SMAppService` login
/// item cannot carry the `--autostart` argument Windows/Linux rely on.
///
/// The method is macOS-only by design (`null` elsewhere), so the channel
/// round-trip cases only run on a macOS host.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/macos_lifecycle_channel.dart';

const _channel = MethodChannel('com.whispaste.app_lifecycle');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockReply(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => reply(call));
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  final skipOffMac = Platform.isMacOS ? false : 'macOS-only channel';

  test('returns the native answer (true)', () async {
    mockReply((call) => call.method == 'wasLaunchedAsLoginItem' ? true : null);
    expect(await MacOSLifecycleChannel.wasLaunchedAsLoginItem(), isTrue);
  }, skip: skipOffMac);

  test('returns the native answer (false)', () async {
    mockReply((call) => false);
    expect(await MacOSLifecycleChannel.wasLaunchedAsLoginItem(), isFalse);
  }, skip: skipOffMac);

  test('degrades to null when the native side fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(code: 'boom');
        });
    expect(await MacOSLifecycleChannel.wasLaunchedAsLoginItem(), isNull);
  }, skip: skipOffMac);

  test('degrades to null when the method is not implemented', () async {
    // No handler registered → MissingPluginException.
    expect(await MacOSLifecycleChannel.wasLaunchedAsLoginItem(), isNull);
  }, skip: skipOffMac);
}
