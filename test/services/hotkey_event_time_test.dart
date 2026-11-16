import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/services/hotkey_event_time.dart';

/// Issue #809: the Carbon event time of the system reaches the handlers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whispaste/hotkey_event_time_test');
  final hotKey = HotKey(key: PhysicalKeyboardKey.keyD, identifier: 'main');

  Future<void> stamp(String type, String id, int ms) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall('stamp', {'type': type, 'identifier': id, 'atMs': ms}),
            ),
            (_) {},
          );

  test('a handler sees the stamp of its event, none afterwards', () async {
    final times = HotKeyEventTimes(channel: channel, enabled: true);
    final seen = <Duration?>[];
    final down = times.wrap('onKeyDown', (_) => seen.add(times.lastEventAt))!;
    final up = times.wrap('onKeyUp', (_) => seen.add(times.lastEventAt))!;

    await stamp('onKeyDown', 'main', 5000);
    down(hotKey);
    await stamp('onKeyUp', 'main', 5300);
    up(hotKey);

    expect(seen, [
      const Duration(milliseconds: 5000),
      const Duration(milliseconds: 5300),
    ]);
    expect(times.lastEventAt, isNull);
  });

  test('a stamp of another event or key is not used, and not reused', () async {
    final times = HotKeyEventTimes(channel: channel, enabled: true);
    final seen = <Duration?>[];
    final down = times.wrap('onKeyDown', (_) => seen.add(times.lastEventAt))!;

    await stamp('onKeyUp', 'main', 1);
    down(hotKey);
    await stamp('onKeyDown', 'other', 2);
    down(hotKey);
    await stamp('onKeyDown', 'main', 3);
    down(hotKey);
    down(hotKey);

    expect(seen, [null, null, const Duration(milliseconds: 3), null]);
  });

  test('inert when disabled; malformed stamps are ignored', () {
    final times = HotKeyEventTimes(channel: channel, enabled: false);
    void h(HotKey _) {}
    expect(times.wrap('onKeyDown', h), same(h));
    expect(HotKeyEventTimes.parseStamp({'atMs': -1}), isNull);
    expect(HotKeyEventTimes.parseStamp('x'), isNull);
  });
}
