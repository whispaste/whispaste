/// Dispatch of native sleep and wake events (ticket, matrix 9.5).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/low_power_state.dart';
import 'package:whispaste/services/power_event_service.dart';

const _channelName = 'com.whispaste.power.test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(_channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late PowerEventService service;

  setUp(() {
    calls = [];
    service = PowerEventService(
      channel: channel,
      onWillSleep: () async => calls.add('willSleep'),
      onDidWake: () async => calls.add('didWake'),
    )..start();
  });

  tearDown(() {
    service.stop();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> send(String method) {
    return messenger.handlePlatformMessage(
      _channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  test('willSleep and didWake reach their callbacks in order', () async {
    await send('willSleep');
    await send('didWake');

    expect(calls, ['willSleep', 'didWake']);
  });

  test('an unknown event calls neither callback', () async {
    await send('reboot');

    expect(calls, isEmpty);
  });

  test('stop removes the handler so later events are ignored', () async {
    service.stop();
    await send('willSleep');

    expect(calls, isEmpty);
  });

  group('shouldPrewarmAfterWake', () {
    test('re-warms a local engine when idle, even if it was unloaded', () {
      expect(
        shouldPrewarmAfterWake(
          isLocalProvider: true,
          isIdle: true,
          lowPower: LowPowerState.off,
        ),
        isTrue,
      );
    });

    test('keeps a cloud engine out of the re-warm', () {
      expect(
        shouldPrewarmAfterWake(
          isLocalProvider: false,
          isIdle: true,
          lowPower: LowPowerState.off,
        ),
        isFalse,
      );
    });

    test('never re-warms during a dictation', () {
      expect(
        shouldPrewarmAfterWake(
          isLocalProvider: true,
          isIdle: false,
          lowPower: LowPowerState.off,
        ),
        isFalse,
      );
    });

    test('skips the re-warm while low-power mode is on', () {
      expect(
        shouldPrewarmAfterWake(
          isLocalProvider: true,
          isIdle: true,
          lowPower: LowPowerState.on,
        ),
        isFalse,
      );
    });

    test('an unknown low-power state does not block the re-warm', () {
      expect(
        shouldPrewarmAfterWake(
          isLocalProvider: true,
          isIdle: true,
          lowPower: LowPowerState.unknown,
        ),
        isTrue,
      );
    });
  });
}
