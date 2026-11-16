// The native lookup of the app that holds macOS secure input (F35-8).
// macOS maps the holder to a name and bundle id; Windows and Linux have no
// such handler, so the lookup reports no holder and the notice stays generic.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/windows_desktop_paste_controller.dart';

const _channel = MethodChannel('com.whispaste.desktop_paste');

void _mock(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('macOS maps the native holder to its name and bundle id', () async {
    _mock((call) async {
      if (call.method != 'secureInputHolder') return null;
      return {
        'pid': 4242,
        'name': 'Terminal',
        'bundleId': 'com.apple.Terminal',
      };
    });

    final holder = await MacOSDesktopPasteController().secureInputHolder();

    expect(holder, isNotNull);
    expect(holder!.name, 'Terminal');
    expect(holder.bundleId, 'com.apple.Terminal');
  });

  test('macOS without a holder (nil) reports no holder', () async {
    _mock((call) async => null);

    expect(await MacOSDesktopPasteController().secureInputHolder(), isNull);
  });

  test('macOS with a PID but no app name keeps the name empty', () async {
    _mock((call) async => {'pid': 99});

    final holder = await MacOSDesktopPasteController().secureInputHolder();

    expect(holder, isNotNull);
    expect(holder!.name, isNull);
    expect(holder.bundleId, isNull);
  });

  test(
    'Windows has no handler and reports no holder, without an error',
    () async {
      // No mock handler: the channel answers MissingPluginException.
      expect(await WindowsDesktopPasteController().secureInputHolder(), isNull);
    },
  );
}
