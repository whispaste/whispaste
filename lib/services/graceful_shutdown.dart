/// Timeout-bounded native-resource teardown, shared by the two paths that
/// can end the process: the Dart-level "close = quit" window-close handler
/// (`app.dart`'s `onWindowClose`) and the native `applicationShouldTerminate`
/// bridge for macOS Cmd+Q / Dock "Quit" (`AppDelegate.swift` +
/// `MacOSLifecycleChannel.registerTerminationHandler`).
///
/// Both must free the on-device STT engine's (and the local Smart Mode
/// engine's) native GPU/Metal resources
/// before the process actually exits — otherwise ggml's Metal-residency-set
/// teardown assert aborts the whole app (same class of bug as
/// FLUTTER_WHISPASTE-BC, just reached via a quit path that bypasses the
/// window-close handler entirely).
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import 'automation_api/automation_api_controller.dart';
import 'smart_mode/smart_mode_ffi_engine.dart';
import 'stt/on_device_engine_lifecycle.dart';
import 'stt/stt_bundle.dart';
import 'stt_engine_lifecycle_provider.dart';
import 'stt_parakeet/parakeet_engine_notifier.dart';
import 'stt_parakeet/parakeet_lifecycle_adapter.dart';
import 'telemetry_service.dart';

final _log = AppLogger('GracefulShutdown');

Future<void> runGracefulEngineShutdown(ProviderContainer container) async {
  try {
    final engine = container.read(onDeviceEngineLifecycleProvider);
    // Quit never waits for a native decode: a busy engine is retired or its
    // worker killed at once (SttServerStateNotifier / ParakeetEngineNotifier
    // .stopForQuit).
    final stopped = switch (engine) {
      WhisperEngineLifecycleAdapter() => engine.stopForQuit(),
      ParakeetEngineLifecycleAdapter() => engine.stopForQuit(),
      _ => engine.stop(),
    };
    await stopped.timeout(const Duration(seconds: 10));
  } catch (e) {
    _log.debug('STT engine stop failed during shutdown (non-fatal): $e');
  }

  try {
    // The local Smart Mode engine keeps its llama.cpp model resident between
    // calls — free it for the same Metal-teardown reason as the STT engine.
    // Only if it was ever built: reading the provider here would otherwise
    // construct an engine just to shut it down.
    if (container.exists(smartModeEngineProvider)) {
      final engine = container.read(smartModeEngineProvider);
      if (engine is SmartModeFfiEngine) {
        await engine.shutdown().timeout(const Duration(seconds: 10));
      }
    }
  } catch (e) {
    _log.debug('Smart Mode engine stop failed during shutdown (non-fatal): $e');
  }

  try {
    // Local automation API (ticket 03) — single-instance, in-process server;
    // close its socket(s) explicitly rather than relying on process exit,
    // same reasoning as the DB close below.
    await container
        .read(automationApiControllerProvider.notifier)
        .shutdown()
        .timeout(const Duration(seconds: 2), onTimeout: () {});
  } catch (e) {
    _log.debug('Automation API stop failed during shutdown (non-fatal): $e');
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

  // A native decode still running on a retired engine: a normal exit runs C++
  // static destructors while that thread is inside Metal, so end the process
  // without them (8bfb8d5e). Everything above has already been flushed.
  final whisperBusy =
      container.exists(localSttBundleProvider) &&
      container.read(localSttBundleProvider.notifier).hasNativeCallRunning;
  final parakeetBusy =
      container.exists(parakeetEngineProvider) &&
      container.read(parakeetEngineProvider.notifier).hasNativeCallRunning;
  if (whisperBusy || parakeetBusy) {
    _log.warning('Quitting while a native call runs: ending without exit()');
    _endProcessWithoutDestructors();
  }
}

/// Ends the process without running C++ static destructors (`_exit` on
/// macOS/Linux, `ExitProcess` on Windows).
void _endProcessWithoutDestructors() {
  if (Platform.isWindows) {
    DynamicLibrary.open(
      'kernel32.dll',
    ).lookupFunction<Void Function(Uint32), void Function(int)>('ExitProcess')(
      0,
    );
  } else {
    DynamicLibrary.process()
        .lookupFunction<Void Function(Int32), void Function(int)>('_exit')(0);
  }
}
