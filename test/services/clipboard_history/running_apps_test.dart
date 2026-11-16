/// Handover tests for the `listRunningApps` channel call (issue #616): the
/// macOS (bundle id) and Windows (exe name) payload shapes, and the split
/// between "platform has no method" (empty) and "native failure" (throws).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/running_apps.dart';

const _channel = MethodChannel('com.whispaste.clipboard_history');

void _handle(Future<Object?>? Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS payload: bundle ids with names, sorted by name', () async {
    _handle((call) async {
      expect(call.method, 'listRunningApps');
      return [
        {'id': 'com.apple.Safari', 'name': 'Safari'},
        {'id': 'com.bitwarden.desktop', 'name': 'Bitwarden'},
      ];
    });
    final apps = await listRunningApps();
    expect(apps.map((a) => a.id), [
      'com.bitwarden.desktop',
      'com.apple.Safari',
    ]);
    expect(apps.map((a) => a.name), ['Bitwarden', 'Safari']);
  });

  test('Windows payload: exe names; missing name falls back to the id, '
      'entries without an id are dropped', () async {
    _handle(
      (call) async => [
        {'id': '1password.exe', 'name': '1Password'},
        {'id': 'keepass.exe'},
        {'name': 'no id'},
        {'id': ''},
      ],
    );
    final apps = await listRunningApps();
    expect(apps.map((a) => a.id), ['1password.exe', 'keepass.exe']);
    expect(apps.last.name, 'keepass.exe');
  });

  test('no handler (Linux) reads as an empty list', () async {
    expect(await listRunningApps(), isEmpty);
  });

  test('a native failure propagates so the settings can show it', () async {
    _handle((call) async => throw PlatformException(code: 'boom'));
    await expectLater(listRunningApps(), throwsA(isA<PlatformException>()));
  });
}
