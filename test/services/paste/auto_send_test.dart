/// Auto-send (#564): trigger logic (opt-in, extra key, confirmed paste only),
/// conflict detection and the native hand-over on all three platforms.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/desktop_paste/channel_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/windows_desktop_paste_controller.dart';
import 'package:whispaste/services/paste/auto_send.dart';
import 'package:whispaste/services/paste/paster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldSendEnterAfterPaste', () {
    test('sends only when enabled, key held and paste confirmed', () {
      for (final outcome in PasteOutcome.values) {
        for (final enabled in [true, false]) {
          for (final held in [true, false]) {
            final expected = enabled && held && outcome == PasteOutcome.success;
            expect(
              shouldSendEnterAfterPaste(
                enabled: enabled,
                extraKeyHeldAtRelease: held,
                outcome: outcome,
              ),
              expected,
              reason: '$outcome enabled=$enabled held=$held',
            );
          }
        }
      }
    });
  });

  group('autoSendConflictsWithHotkey', () {
    test('default shortcuts do not conflict', () {
      expect(autoSendConflictsWithHotkey(hotkeyModifiers: 'ctrl+shift'), false);
      expect(autoSendConflictsWithHotkey(hotkeyModifiers: 'cmd+shift'), false);
    });
    test('alt in the combination conflicts', () {
      expect(autoSendConflictsWithHotkey(hotkeyModifiers: 'ctrl+alt'), true);
    });
    test('alt as double-tap key conflicts', () {
      expect(
        autoSendConflictsWithHotkey(
          hotkeyModifiers: '',
          doubleTapKey: 'rightAlt',
        ),
        true,
      );
    });
  });

  test('setting is off by default and survives a round trip', () {
    expect(const BehaviorSettings().autoSendOnRelease, false);
    final on = const BehaviorSettings().copyWith(autoSendOnRelease: true);
    expect(BehaviorSettings.fromMap(on.toMap()).autoSendOnRelease, true);
  });

  group('native hand-over', () {
    const channel = MethodChannel('com.whispaste.desktop_paste');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controllers = <String, ChannelDesktopPasteController Function()>{
      'macOS': MacOSDesktopPasteController.new,
      'Windows': WindowsDesktopPasteController.new,
      'Linux': LinuxDesktopPasteController.new,
    };

    controllers.forEach((name, make) {
      test('$name: extraKeyHeld and sendEnter reach the channel', () async {
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return true;
        });
        final c = make();
        expect(await c.extraKeyHeld(), true);
        expect(await c.sendEnter(), true);
        expect(calls, ['extraKeyHeld', 'sendEnter']);
      });

      test('$name: a missing native side means no auto-send', () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          throw MissingPluginException();
        });
        final c = make();
        expect(await c.extraKeyHeld(), false);
        expect(await c.sendEnter(), false);
      });
    });
  });
}
