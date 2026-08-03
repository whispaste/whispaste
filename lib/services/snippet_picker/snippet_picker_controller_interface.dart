/// Pure interface for the Snippet-Picker controller (dictation-automations
/// ticket 06). Kept separate from the factory layer so platform
/// implementations avoid a circular dependency, mirroring
/// `floating_button_controller_interface.dart`.
library;

import 'snippet_picker_events.dart';

/// Platform-agnostic interface for the native Snippet-Picker panel.
///
/// A one-shot surface, unlike the floating button/overlay controllers:
/// [show] opens the panel with a fixed snapshot of items near the given
/// position and returns as soon as the panel is on screen — it does **not**
/// wait for the user's selection. The eventual pick (or cancellation)
/// arrives later, asynchronously, on [events]. This matters for the
/// recording pipeline: dispatch must return promptly so it can reach its
/// `done` state without waiting on user interaction (ticket 06's dispatch
/// AC).
abstract class SnippetPickerController {
  /// Shows the panel near screen position ([x], [y]) — logical pixels,
  /// bottom-left origin (matches [ScreenRetriever] / macOS screen
  /// coordinates). [items] are `{'id': ..., 'title': ..., 'body': ...}`
  /// maps; `body` is included so the panel's search can filter on it, not
  /// just the title.
  Future<void> show({
    required double x,
    required double y,
    required List<Map<String, String>> items,
  });

  /// Hides the panel (keeps the native window for reuse).
  Future<void> hide();

  /// Stream of events from the native panel — an item pick, a dismissal, or
  /// a render-engine boot diagnostic.
  Stream<SnippetPickerEvent> get events;

  /// Destroys the native window and releases resources.
  Future<void> dispose();
}
