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
/// Production default: 3 windows of 60 s each (= 3 min total tolerance).
/// Tests override this to run fast without real time passing.
final sttStartupHeartbeatConfigProvider =
    Provider<({Duration window, int maxMissedWindows})>(
      (_) => (window: const Duration(seconds: 60), maxMissedWindows: 3),
    );
