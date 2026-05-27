/// Shared DI providers for the modular STT subsystem.
///
/// Placed in a standalone file to avoid circular imports between
/// [stt_bundle.dart] and [stt_server_state_notifier.dart].
///
/// Import this file in [SttServerStateNotifier] directly;
/// external consumers use [stt_bundle.dart] which re-exports these.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../process_runner.dart';
import 'server_binary_recovery.dart';

/// Overrideable [ProcessRunner] for the whisper-server subprocess.
/// Tests replace this with a fake to avoid spawning real processes.
final processRunnerProvider = Provider<ProcessRunner>(
  (_) => const SystemProcessRunner(),
);

/// Overrideable [http.Client] for STT HTTP calls.
/// Tests replace this with a mock client.
final sttHttpClientProvider = Provider<http.Client>((_) => http.Client());

/// Heartbeat policy for the whisper-server startup health-poll.
///
/// Production default: 3 windows of 60 s each (= 3 min total tolerance
/// without stderr progress), and an absolute 180 s wall-clock deadline.
///
/// The two limits guard different failure shapes:
///   - `window` × `maxMissedWindows` catches the silent-stall shape
///     (server is alive but emits no stderr at all).
///   - `overallDeadline` catches the long-load shape where stderr keeps
///     ticking (e.g. layer-by-layer model load on a thrashing disk)
///     but `/health` never flips to 200.
///
/// Tests override this to run fast without real time passing. Test
/// fixtures that previously used a `(window, maxMissedWindows)` record
/// literal construct [SttStartupHeartbeatConfig] directly — the third
/// `overallDeadline` field defaults to the production value, so the
/// migration was a mechanical literal → constructor swap.
final sttStartupHeartbeatConfigProvider = Provider<SttStartupHeartbeatConfig>(
  (_) => const SttStartupHeartbeatConfig(),
);

/// Configuration value object for [sttStartupHeartbeatConfigProvider].
class SttStartupHeartbeatConfig {
  const SttStartupHeartbeatConfig({
    this.window = const Duration(seconds: 60),
    this.maxMissedWindows = 3,
    this.overallDeadline = const Duration(seconds: 180),
  });

  /// Per-window stderr-heartbeat tolerance.
  final Duration window;

  /// How many consecutive empty heartbeat windows trigger a stall fail.
  final int maxMissedWindows;

  /// Absolute wall-clock deadline for the whole `_waitReady` loop. Catches
  /// the slow-but-not-silent shape that the heartbeat window alone misses.
  final Duration overallDeadline;
}

/// Singleton [ServerBinaryRecovery] for the app session. The recovery
/// orchestrator carries an in-session generation counter (max 1 attempt
/// per variant per session — PRD-Modul-1 § Risiken), so the provider
/// MUST live as a session-scoped Provider, not be re-created per call.
///
/// Tests override this with a fake or with a recovery instance backed by
/// a fake [WhisperServerDownloader] / [BinaryStore] to avoid real disk.
final serverBinaryRecoveryProvider = Provider<ServerBinaryRecovery>(
  (_) => ServerBinaryRecovery(),
);
