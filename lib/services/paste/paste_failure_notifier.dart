import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop_paste/desktop_paste_controller_interface.dart';
import 'paster.dart';

/// One paste-failure event observed by the UI.
class PasteFailureEvent {
  PasteFailureEvent({
    required this.outcome,
    this.secureInputHolder,
    this.fieldType = FocusedFieldType.unknown,
  });

  final PasteOutcome outcome;

  /// The app holding macOS secure input, set for [PasteOutcome.secureInput]
  /// when the lookup found one (F35-8).
  final SecureInputHolder? secureInputHolder;

  /// The focused field's type at paste time (#949); the general password-field
  /// hint of an unconfirmed paste only applies while it is unknown.
  final FocusedFieldType fieldType;
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

  void report(
    PasteOutcome outcome, {
    SecureInputHolder? secureInputHolder,
    FocusedFieldType fieldType = FocusedFieldType.unknown,
  }) {
    state = PasteFailureEvent(
      outcome: outcome,
      secureInputHolder: secureInputHolder,
      fieldType: fieldType,
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
