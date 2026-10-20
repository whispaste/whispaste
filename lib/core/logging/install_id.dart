/// Random per-install identifier for error reports and feedback (R-08).
///
/// It replaced an MD5 of the hostname, which anyone who knows a machine's
/// name could recompute and match to its reports. The value is drawn once
/// from a secure random source and kept in the app data directory, so it
/// stays stable across launches (crash grouping, the GPU-vendor sample)
/// but says nothing about the machine; deleting the file draws a new one.
/// `whispaste --diagnose` reads the same file (device_id_probe.dart).
library;

import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show appDataDir, installIdFileName;

final _valid = RegExp(r'^[0-9a-f]{12}$');
final _cache = <String, String>{};

/// The install's id: 12 lowercase hex characters, the length the feedback
/// table's RLS policy requires. When the file cannot be read or written the
/// id is still stable for this run, just not across launches.
String readInstallId({String? directory}) {
  final String dir;
  try {
    dir = directory ?? appDataDir();
  } on Object catch (e) {
    dev.log('No app data directory for the install id: $e', name: 'InstallId');
    return _cache.putIfAbsent('', _fresh);
  }
  return _cache.putIfAbsent(dir, () => _load(dir));
}

String _load(String dir) {
  final file = File(p.join(dir, installIdFileName));
  try {
    if (file.existsSync()) {
      final stored = file.readAsStringSync().trim();
      if (_valid.hasMatch(stored)) return stored;
    }
  } on FileSystemException catch (e) {
    dev.log('Install id not readable: $e', name: 'InstallId');
  }
  final id = _fresh();
  try {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(id, flush: true);
  } on FileSystemException catch (e) {
    dev.log('Install id not stored: $e', name: 'InstallId');
  }
  return id;
}

String _fresh() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 6; i++) random.nextInt(256).toRadixString(16),
  ].map((b) => b.padLeft(2, '0')).join();
}

@visibleForTesting
void resetInstallIdCacheForTesting() => _cache.clear();
