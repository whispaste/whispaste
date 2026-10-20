// Guard for the Flatpak power safety net (PAR-030). The Linux runner listens
// for suspend/resume on the system bus (linux/runner/power_event_host.cc,
// org.freedesktop.login1). Inside the sandbox that bus is only reachable
// through a named --system-talk-name grant, so the manifest must carry exactly
// that grant and nothing broader. The sandbox behaviour itself is proven by
// the probe recorded in packaging/flatpak/README.md (runtime check).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifest = 'packaging/flatpak/de.whispaste.app.yml';
const _readme = 'packaging/flatpak/README.md';
const _grant = '--system-talk-name=org.freedesktop.login1';

String _finishArgs() {
  final text = File(_manifest).readAsStringSync();
  final start = text.indexOf('finish-args:');
  final end = text.indexOf('\nmodules:');
  if (start < 0 || end < start) {
    fail('finish-args or modules block missing in $_manifest');
  }
  return text.substring(start, end);
}

void main() {
  test('the manifest grants the login1 system service by name', () {
    expect(
      RegExp(
        r'^\s*- ' + RegExp.escape(_grant) + r'\s*$',
        multiLine: true,
      ).hasMatch(_finishArgs()),
      isTrue,
      reason: 'Flatpak needs $_grant for the suspend/resume safety net',
    );
  });

  test(
    'the only system-bus grant is login1 (no --system-talk-name widening)',
    () {
      final finishArgs = _finishArgs();
      final systemGrants = RegExp(
        r'--system-talk-name=(\S+)',
      ).allMatches(finishArgs).map((m) => m.group(1)).toList();
      expect(systemGrants, ['org.freedesktop.login1']);
      expect(finishArgs, isNot(contains('--system-own-name')));
      expect(finishArgs, isNot(contains('--socket=system-bus')));
    },
  );

  test('the grant names the service the runner really subscribes to', () {
    final source = File('linux/runner/power_event_host.cc').readAsStringSync();
    expect(source, contains('"org.freedesktop.login1"'));
  });

  test('the Flatpak README documents the grant and its runtime check', () {
    final readme = File(_readme).readAsStringSync();
    expect(readme, contains(_grant));
    expect(readme, contains('Stromereignis'));
  });
}
