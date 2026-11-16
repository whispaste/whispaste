/// Which app holds the microphone when a recording cannot start (#139).
///
/// Only Windows tells: its privacy store lists, per app, when it last used
/// the microphone, and an entry without a stop time is using it right now.
/// macOS and Linux give no such answer, so the notice stays generic there.
library;

import 'dart:io';

/// The app named on the "microphone won't start" card, set by the audio
/// service before it reports the failed start and cleared on the next start.
String? micBusyApp;

const _micConsentKey =
    r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone';

/// Executables that are never named: WhisPaste itself is not "another app".
const _ownProcessNames = {'whispaste'};

/// The display name of an app holding the microphone in the output of
/// `reg query <ConsentStore\microphone> /s`, or null when none does.
///
/// Pure. A key block holds the microphone while its `LastUsedTimeStop` is 0.
/// Desktop apps appear as their path with `#` for `\` (`C:#Tools#zoom.exe`),
/// store apps as `Publisher.App_hash`.
String? parseMicBusyApp(String regOutput) {
  String? key;
  for (final raw in regOutput.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.startsWith('HKEY_')) {
      key = line.trim();
      continue;
    }
    final match = RegExp(
      r'^\s*LastUsedTimeStop\s+REG_QWORD\s+0x0$',
    ).firstMatch(line);
    if (match == null || key == null) continue;
    final name = _appNameFromKey(key);
    if (name != null && !_ownProcessNames.contains(name.toLowerCase())) {
      return name;
    }
  }
  return null;
}

String? _appNameFromKey(String key) {
  final last = key.split(r'\').last;
  if (last.isEmpty || last == 'NonPackaged' || last == 'microphone') {
    return null;
  }
  if (last.contains('#')) {
    final file = last.split('#').last;
    return file.toLowerCase().endsWith('.exe')
        ? file.substring(0, file.length - 4)
        : file;
  }
  // `Publisher.App_hash`: the part before the hash, last dotted word.
  final family = last.split('_').first;
  final word = family.split('.').last;
  return word.isEmpty ? null : word;
}

/// Asks the platform which app uses the microphone; null when unknown.
Future<String?> probeMicBusyApp() async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run('reg', [
      'query',
      _micConsentKey,
      '/s',
    ]).timeout(const Duration(seconds: 2));
    if (result.exitCode != 0) return null;
    return parseMicBusyApp(result.stdout.toString());
  } on Exception {
    return null;
  }
}
