/// Hand-over from the Linux ACPI lid switch to the microphone suggestion
/// (#932): a closed lid excludes the built-in microphone, an unknown state
/// never does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/linux_lid_state.dart';
import 'package:whispaste/services/microphone_priority.dart';

void main() {
  test('reads a closed lid from the ACPI state file', () async {
    expect(
      await linuxLidClosed(read: () async => ['state:      closed\n']),
      isTrue,
    );
  });

  test('open lid, no lid file and odd content report not closed', () async {
    expect(
      await linuxLidClosed(read: () async => ['state:      open\n']),
      isFalse,
    );
    expect(await linuxLidClosed(read: () async => const []), isFalse);
    expect(await linuxLidClosed(read: () async => ['unknown']), isFalse);
  });

  test(
    'a closed lid keeps the built-in microphone out of the suggestion',
    () async {
      final closed = await linuxLidClosed(read: () async => ['state: closed']);
      expect(
        suggestAlternativeMicrophone(
          silent: 'USB Mic',
          available: const ['Built-in Audio Analog Stereo', 'USB Mic'],
          lidClosed: closed,
        ),
        isNull,
      );
    },
  );
}
