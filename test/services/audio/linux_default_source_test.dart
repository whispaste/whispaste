/// Hand-over from the sound server's default source to the "silent
/// microphone" suggestion on Linux (#930): the device that records under
/// "System default" is named, and the suggestion never offers it back.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show InputDevice;
import 'package:whispaste/services/audio/linux_default_source.dart';
import 'package:whispaste/services/microphone_priority.dart';

const _usb = InputDevice(id: 'alsa_input.usb-Blue', label: 'Blue Yeti');
const _builtIn = InputDevice(
  id: 'alsa_input.pci-0000_00_1f.3.analog-stereo',
  label: 'Built-in Audio Analog Stereo',
);
const _devices = [_builtIn, _usb];

PactlRunner _pactl(Map<String, String?> answers) =>
    (args) async => answers[args.first];

void main() {
  group('linuxDefaultSourceName', () {
    test('reads get-default-source', () async {
      final name = await linuxDefaultSourceName(
        run: _pactl({'get-default-source': 'alsa_input.usb-Blue\n'}),
      );
      expect(name, 'alsa_input.usb-Blue');
    });

    test('falls back to the Default Source line of pactl info', () async {
      final name = await linuxDefaultSourceName(
        run: _pactl({
          'get-default-source': null,
          'info':
              'Server Name: PipeWire\nDefault Source: alsa_input.usb-Blue\n',
        }),
      );
      expect(name, 'alsa_input.usb-Blue');
    });

    test('is null without pactl', () async {
      expect(await linuxDefaultSourceName(run: _pactl({})), isNull);
    });
  });

  group('silence with the system default', () {
    Future<String?> suggestion(String? defaultSource) async {
      final label = await linuxDefaultInputLabel(
        _devices,
        run: _pactl({'get-default-source': defaultSource}),
      );
      return suggestAlternativeMicrophone(
        silent: label ?? 'Default',
        available: [for (final d in _devices) d.label],
        lidClosed: false,
      );
    }

    test('names the default source and suggests another device', () async {
      expect(await suggestion(_usb.id), _builtIn.label);
      expect(await suggestion(_builtIn.id), _usb.label);
    });

    test('an unknown default source suggests nothing', () async {
      expect(await suggestion('alsa_output.x.monitor'), isNull);
      expect(await suggestion(null), isNull);
    });
  });
}
