/// The menu bar icon gets its accessible name from the native host (#1926):
/// on macOS the call goes out with the app name, elsewhere nothing is sent.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/tray_panel/status_item_name.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.status_item_name');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {'named': 1};
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('macOS asks the host to name the status item "WhisPaste"', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await nameMacStatusItem(channel: channel);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'nameStatusItem');
    expect(calls.single.arguments, {'label': 'WhisPaste'});
  });

  test('the shared tray channel is the one TrayPanelHost listens on', () {
    expect(kTrayPanelChannel.name, 'com.whispaste.tray_panel');
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('${platform.name} names its tray icon itself, no call', () async {
      debugDefaultTargetPlatformOverride = platform;
      await nameMacStatusItem(channel: channel);
      expect(calls, isEmpty);
    });
  }

  test('a host without the method never throws', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'unavailable');
        });
    await expectLater(nameMacStatusItem(channel: channel), completes);
  });
}
