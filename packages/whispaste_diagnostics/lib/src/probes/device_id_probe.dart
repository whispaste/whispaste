/// Sentry device_id probe.
///
/// Derives a stable, anonymous device identifier using the same formula as
/// `crash_reporter._deriveDeviceId` in the Flutter app:
///
///   md5("${hostname}_whispaste").substring(0, 12)
///
/// This bit-identical implementation lives in the pure-Dart core so the
/// standalone WhisPaste-Diagnose CLI can emit the same device_id that
/// Sentry uses — enabling correlation of a CLI diagnostic report with a
/// Sentry crash event.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Pure formula (exported for unit tests)
// ---------------------------------------------------------------------------

/// Computes the device_id for [hostname].
///
/// Formula mirrors `crash_reporter._deriveDeviceId`:
///   `md5("${hostname}_whispaste").toString().substring(0, 12)`.
@visibleForTesting
String deriveDeviceId(String hostname) {
  final bytes = utf8.encode('${hostname}_whispaste');
  return md5.convert(bytes).toString().substring(0, 12);
}

// ---------------------------------------------------------------------------
// Live probe
// ---------------------------------------------------------------------------

/// Returns the device_id for the current machine.
///
/// Returns `'unknown'` on any error (matching the crash_reporter fallback).
String deviceId() {
  try {
    return deriveDeviceId(Platform.localHostname);
  } on Exception {
    return 'unknown';
  }
}
