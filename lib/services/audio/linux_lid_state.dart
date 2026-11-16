/// Notebook lid state on Linux (#932).
///
/// The kernel's ACPI button driver publishes the lid switch as a text file,
/// `/proc/acpi/button/lid/<name>/state`, containing `state:      closed` or
/// `open`. It needs no permission and no extra tool. Machines without a lid
/// (desktops, many ARM boards) have no such file; then nothing is reported
/// and the silence detection stays the only signal.
library;

import 'dart:io';

/// Reads the lid state files of the machine, one string per lid switch.
typedef LidStateReader = Future<List<String>> Function();

const _lidRoot = '/proc/acpi/button/lid';

Future<List<String>> _readLidFiles() async {
  try {
    final root = Directory(_lidRoot);
    if (!await root.exists()) return const <String>[];
    final states = <String>[];
    await for (final entry in root.list()) {
      final file = File('${entry.path}/state');
      if (await file.exists()) states.add(await file.readAsString());
    }
    return states;
  } on Exception {
    return const <String>[];
  }
}

/// Whether a lid switch reports "closed". `false` when there is no lid file,
/// the content is unreadable or says anything else: an unknown state never
/// excludes a device.
Future<bool> linuxLidClosed({LidStateReader read = _readLidFiles}) async {
  final states = await read();
  return states.any(
    (s) => RegExp(r'^state:\s*closed\s*$', multiLine: true).hasMatch(s),
  );
}
