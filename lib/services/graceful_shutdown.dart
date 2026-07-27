/// Timeout-bounded native-resource teardown, shared by the two paths that
/// can end the process: the Dart-level "close = quit" window-close handler
/// (`app.dart`'s `onWindowClose`) and the native `applicationShouldTerminate`
/// bridge for macOS Cmd+Q / Dock "Quit" (`AppDelegate.swift` +
/// `MacOSLifecycleChannel.registerTerminationHandler`).
///
/// Both must free the on-device STT engine's native GPU/Metal resources
/// before the process actually exits — otherwise ggml's Metal-residency-set
/// teardown assert aborts the whole app (same class of bug as
/// FLUTTER_WHISPASTE-BC, just reached via a quit path that bypasses the
/// window-close handler entirely).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import 'stt_engine_lifecycle_provider.dart';
import 'telemetry_service.dart';

final _log = AppLogger('GracefulShutdown');

Future<void> runGracefulEngineShutdown(ProviderContainer container) async {
  try {
    await container
        .read(onDeviceEngineLifecycleProvider)
        .stop()
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    _log.debug('STT engine stop failed during shutdown (non-fatal): $e');
  }

  try {
    await container
        .read(historyDatabaseProvider)
        .close()
        .timeout(const Duration(seconds: 2));
  } catch (e) {
    _log.debug('DB close failed during shutdown (non-fatal): $e');
  }

  try {
    final telemetry = container.read(telemetryProvider);
    await container
        .read(telemetrySessionAggregatorProvider)
        .drainAndFlush(telemetry)
        .timeout(const Duration(seconds: 2), onTimeout: () {});
  } catch (e) {
    _log.debug('telemetry flush failed (non-fatal): $e');
  }
}
