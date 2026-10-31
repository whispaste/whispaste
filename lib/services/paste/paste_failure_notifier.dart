import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop_paste/desktop_paste_controller_interface.dart';
import 'paster.dart';

/// One paste-failure event observed by the UI.
class PasteFailureEvent {
  PasteFailureEvent({required this.outcome, this.secureInputHolder});

  final PasteOutcome outcome;

  /// The app holding macOS secure input, set for [PasteOutcome.secureInput]
  /// when the lookup found one (F35-8).
  final SecureInputHolder? secureInputHolder;
}

/// Notifier that the [RecordingOrchestrator] pushes paste failures into and
/// the UI (status bar banner, settings indicator) listens to.
///
/// State is the most recent failure or `null` if nothing has failed since
/// the last [clear]. Settings UIs that show "permission missing" badges
/// read [state]; transient toasts watch for changes.
class PasteFailureNotifier extends Notifier<PasteFailureEvent?> {
  @override
  PasteFailureEvent? build() => null;

  void report(PasteOutcome outcome, {SecureInputHolder? secureInputHolder}) {
    state = PasteFailureEvent(
      outcome: outcome,
      secureInputHolder: secureInputHolder,
    );
  }

  void clear() {
    state = null;
  }
}

final pasteFailureNotifierProvider =
    NotifierProvider<PasteFailureNotifier, PasteFailureEvent?>(
      PasteFailureNotifier.new,
    );
