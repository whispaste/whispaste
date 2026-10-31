/// Events emitted by the native Snippet-Picker panel window.
sealed class SnippetPickerEvent {
  const SnippetPickerEvent();
}

/// The user clicked a snippet in the list — insert its body.
class SnippetPickerItemSelected extends SnippetPickerEvent {
  const SnippetPickerItemSelected(this.id);
  final String id;
}

/// The panel was dismissed without a selection (Esc, click outside, …).
class SnippetPickerCancelled extends SnippetPickerEvent {
  const SnippetPickerCancelled();
}

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
