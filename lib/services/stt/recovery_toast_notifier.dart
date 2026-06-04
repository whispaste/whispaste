/// Bridges the `ServerBinaryRecovery` outcome surface to the UI toast
/// layer.
///
/// Why this exists: `SttServerStateNotifier` lives in `services/` and must
/// not depend on Flutter widgets — it cannot push a [WpToast] directly.
/// Following the same pattern as `PasteFailureNotifier`, this notifier
/// holds the most recent recovery event and the UI (currently
/// `RecordingBehavior` in `widgets/recording_behavior.dart`) listens for
/// changes and renders the actionable toast.
///
/// Events come in two flavours, matching the PRD's Toast-Tabelle:
///   1. [RecoveryToastKind.exhausted] — every recovery variant has been
///      tried and the user must be sent to settings to recover manually.
///      The toast renders the „Sprachdienst kann nicht starten…"
///      message plus an „Einstellungen öffnen" action.
///   2. [RecoveryToastKind.abiInfo] — an ABI-mismatch was detected and
///      the orchestrator is already re-downloading the model. The user
///      sees the „Lade Sprachmodell neu — bitte warten." info-toast
///      with no action button.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Discriminates which PRD-spec toast the UI should render.
enum RecoveryToastKind {
  /// Recovery orchestrator gave up. Surface the actionable
  /// „Einstellungen öffnen" toast.
  exhausted,

  /// The CPU floor build aborted with STATUS_DLL_NOT_FOUND — the machine
  /// lacks the Microsoft Visual C++ runtime. Surface the actionable
  /// „Visual C++ installieren" toast that opens the redist download.
  vcRuntimeMissing,

  /// ABI mismatch caught — silent re-download in flight. Surface the
  /// passive info toast.
  abiInfo,
}

/// One recovery event emitted by `_attemptRecovery`. The timestamp lets
/// the UI distinguish a freshly-emitted event from a stale leftover when
/// the listener wakes up mid-flight.
class RecoveryToastEvent {
  RecoveryToastEvent({required this.kind, required this.at});

  final RecoveryToastKind kind;
  final DateTime at;
}

/// Notifier the `SttServerStateNotifier` pushes recovery outcomes into.
class RecoveryToastNotifier extends Notifier<RecoveryToastEvent?> {
  @override
  RecoveryToastEvent? build() => null;

  void report(RecoveryToastKind kind) {
    state = RecoveryToastEvent(kind: kind, at: DateTime.now());
  }

  void clear() {
    state = null;
  }
}

/// Riverpod handle for [RecoveryToastNotifier].
final recoveryToastNotifierProvider =
    NotifierProvider<RecoveryToastNotifier, RecoveryToastEvent?>(
      RecoveryToastNotifier.new,
    );
