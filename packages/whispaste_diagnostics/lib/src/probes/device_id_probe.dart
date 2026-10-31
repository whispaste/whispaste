/// Sentry device_id probe.
///
/// Reads the random per-install id the app stores in its data directory
/// (`install_id`, written by `lib/core/logging/install_id.dart`) and attaches
/// to every Sentry event, so a report from the standalone WhisPaste-Diagnose
/// CLI can be matched to the install's crash events. It never creates the
/// file: an install that has not started the app yet has no id.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_service.dart';

/// File in the app data directory that holds the install id.
const installIdFileName = 'install_id';

final _installIdPattern = RegExp(r'^[0-9a-f]{12}$');

/// The stored install id, or `'unknown'` when there is none.
///
/// Without [directory] the lookup tries the EXE data root first, then every
/// MSIX LocalCache root in [msixRoots] (default: [msixLocalCacheRoots]). A
/// Store install writes its id into the package's redirected `%APPDATA%`, which
/// the standalone CLI does not see from outside the container (PAR-031). With
/// [directory] only that root is read.
String deviceId({String? directory, List<String> Function()? msixRoots}) {
  try {
    if (directory != null) return _storedInstallId(directory) ?? 'unknown';
    final roots = [appDataDir(), ...(msixRoots ?? msixLocalCacheRoots)()];
    for (final root in roots) {
      final id = _storedInstallId(root);
      if (id != null) return id;
    }
    return 'unknown';
  } on Exception {
    return 'unknown';
  }
}

/// The valid id stored under [root], or null when the file is missing,
/// unreadable or damaged.
String? _storedInstallId(String root) {
  try {
    final file = File(p.join(root, installIdFileName));
    if (!file.existsSync()) return null;
    final stored = file.readAsStringSync().trim();
    return _installIdPattern.hasMatch(stored) ? stored : null;
  } on Exception {
    return null;
  }
}
