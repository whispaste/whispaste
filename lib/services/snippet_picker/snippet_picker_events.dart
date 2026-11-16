/// Events emitted by the native Snippet-Picker panel window.
sealed class SnippetPickerEvent {
  const SnippetPickerEvent();
}

/// The user clicked a snippet in the list — insert its body.
class SnippetPickerItemSelected extends SnippetPickerEvent {
  const SnippetPickerItemSelected(this.id);
  final String id;
}

/// The panel was dismissed without a selection (Esc, the panel's own cancel).
class SnippetPickerCancelled extends SnippetPickerEvent {
  const SnippetPickerCancelled();
}

/// Why the native panel lost keyboard focus (or saw a click elsewhere).
///
/// The native shells only report; whether the picker closes is decided once,
/// in Dart ([snippetPickerClosesOnFocusLoss]), so all three platforms follow
/// the same rule (#1680).
enum SnippetPickerFocusLossCause {
  /// A mouse button went down outside the panel: the user chose to leave.
  outsideClick,

  /// Focus moved without a click outside (a notification, another app
  /// raising itself, a keyboard app switch). The shell can see clicks, so a
  /// later click outside still reports [outsideClick].
  other,

  /// The shell cannot tell a click from any other focus change (Linux on
  /// Wayland: an XWayland client never sees clicks on native Wayland
  /// windows), so focus loss is the only sign the user went elsewhere.
  unknown;

  /// Parses the native `cause` string; anything unrecognised is [unknown],
  /// which closes, the safe side for an old or new shell.
  static SnippetPickerFocusLossCause parse(Object? raw) => switch (raw) {
    'click' => outsideClick,
    'other' => other,
    _ => unknown,
  };
}

/// The panel lost focus or saw a click outside it, see [cause].
class SnippetPickerFocusLost extends SnippetPickerEvent {
  const SnippetPickerFocusLost(this.cause);
  final SnippetPickerFocusLossCause cause;
}

/// Whether a focus loss closes the picker (#1680).
///
/// The picker stays open while the user is still choosing: a focus change
/// the user did not cause (a notification, the target app repainting) keeps
/// it on screen. It closes on Esc, on a pick, and on a click outside. Where
/// the shell cannot see clicks ([SnippetPickerFocusLossCause.unknown]), a
/// focus loss still closes it, because a picker that stays after the user
/// went elsewhere would float over their work with no click to end it.
bool snippetPickerClosesOnFocusLoss(SnippetPickerFocusLossCause cause) =>
    cause != SnippetPickerFocusLossCause.other;

/// The native shell reported a diagnostic about the dedicated render-engine
/// boot handshake — see `SnippetPickerHost.swift`'s `renderReady` race, the
/// same boot-race class as `FloatingButtonRenderEngineDiagnostic`.
class SnippetPickerRenderEngineDiagnostic extends SnippetPickerEvent {
  const SnippetPickerRenderEngineDiagnostic(
    this.message, {
    required this.isError,
  });
  final String message;
  final bool isError;
}
