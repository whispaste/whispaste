import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio_routing_service.dart';
import 'package:whispaste/services/microphone_priority.dart';

class _ReadableRouting extends AudioRoutingService {
  @override
  bool get canReadDefaultInput => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.whispaste.audio_routing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final routing = _ReadableRouting();
  const usb = InputDevice(id: '{capture}.usb', label: 'USB Microphone');
  const builtin = InputDevice(
    id: '{capture}.internal',
    label: 'Built-in Microphone',
  );
  const devices = [usb, builtin];

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'endpoint crosses the channel and excludes the silent default',
    () async {
      for (final silent in devices) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getDefaultInputDevice');
          expect(call.arguments, isNull);
          return silent.id;
        });
        final label = await routing.defaultInputLabel(devices);
        expect(label, silent.label);
        expect(
          suggestAlternativeMicrophone(
            silent: label!,
            available: devices.map((d) => d.label).toList(),
          ),
          devices.firstWhere((d) => d.id != silent.id).label,
        );
      }
    },
  );

  test('missing, stale and failed endpoints do not suggest a device', () async {
    for (final id in [null, '', 'unlisted']) {
      messenger.setMockMethodCallHandler(channel, (_) async => id);
      expect(await routing.defaultInputLabel(devices), isNull);
    }
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect(await routing.defaultInputLabel(devices), isNull);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await routing.defaultInputLabel(devices), isNull);
  });
}
