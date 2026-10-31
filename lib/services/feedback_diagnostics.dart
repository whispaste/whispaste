/// The short diagnostics block a feedback message can carry (FB-04).
///
/// Four facts only: app version, operating system, the speech engine and the
/// compute backend. The full diagnostics report (Hilfe > Diagnose) also holds
/// log lines and paths, which do not fit the server's 1000-character text
/// field and must never leave the device by default, so it is not reused.
/// The block names no model: the speech model and the Smart Mode text model
/// stay out of it.
library;

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../core/config/settings_enums.dart' show OnDeviceEngine;
import '../core/config/settings_provider.dart';
import 'stt/whisper/whisper_isolate_engine.dart' show whisperEngineProvider;

/// Builds the block from plain values. Pure, so the exact text is testable.
String buildFeedbackDiagnosticBlock({
  required String appVersion,
  required String os,
  required String engine,
  required String backend,
}) =>
    '--- diagnostics ---\n'
    'App $appVersion · OS $os · Engine $engine · Backend $backend';

/// The block for this machine and the current settings. Reads the live
/// engine state, so a switch of engine or backend shows up on the next build.
final feedbackDiagnosticBlockProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final engine = settings.onDeviceEngine;
  final backend = engine == OnDeviceEngine.parakeet
      ? 'cpu'
      : ref.watch(whisperEngineProvider).status.backend.name;
  return buildFeedbackDiagnosticBlock(
    appVersion: appVersion,
    os: feedbackShortOs(),
    engine: engine.value,
    backend: backend,
  );
});

/// The operating system name and its version, cut to one short line. Linux
/// kernel strings run long, and the block has to stay short. The onboarding
/// contact panel sends the same line with its technical details.
String feedbackShortOs() {
  final version = Platform.operatingSystemVersion.split('\n').first.trim();
  final cut = version.length > 40 ? version.substring(0, 40) : version;
  return '${Platform.operatingSystem} $cut'.trim();
}
