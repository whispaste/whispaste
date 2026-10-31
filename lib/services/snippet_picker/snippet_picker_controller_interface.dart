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
///
/// ## Cross-platform shell contract (visual-refresh-2026 ticket 28)
///
/// Every native shell that hosts this controller — today only
/// [MacOSSnippetPickerController] via `SnippetPickerHost.swift`, with
/// Windows/Linux counterparts to follow behind this same interface — must
/// honor two fixed points so the Dart panel's assumptions hold everywhere:
///
/// - **Panel size is fixed at 360×420** (logical px). The Dart panel
///   (`lib/snippet_picker_render_entrypoint.dart`) never reports a measured
///   size back to its host, so a shell that sizes to content instead of
///   this fixed value would clip or letterbox the panel.
/// - **Position is read natively by the shell itself**, anchored at the
///   cursor — never passed from Dart. See [show] below for why.
///
/// **Second-engine boot, verified per platform:** macOS and Windows resolve
/// a *named* Dart entrypoint against the root library
/// (`runWithEntrypoint:`/`set_dart_entrypoint`, both used today by the
/// floating-button/-overlay shells for `floatingButtonMain`/
/// `floatingOverlayMain`) — a Windows Snippet-Picker shell can boot
/// `snippetPickerMain` (`lib/main.dart`) the same way. **Linux has no such
/// API**: its GTK embedder only exposes
/// `fl_dart_project_set_dart_entrypoint_arguments`, so
/// `linux/runner/floating_button_window.cc`/`floating_overlay_window.cc`
/// instead pass a marker argument (`--floating-button`/`--floating-overlay`)
/// that `lib/main.dart`'s `main()` branches on before `runApp()`. A future
/// Linux shell cannot call `snippetPickerMain` by name; it needs the same
/// args-branch pattern (e.g. `--snippet-picker`) added to `main()`, not a
/// second named pragma-vm-entry function.
abstract class SnippetPickerController {
  /// Shows the panel near the current mouse position.
  ///
  /// The position itself is read natively (each platform host queries its
  /// own cursor API directly) rather than passed from Dart — a prior
  /// version passed coordinates from `package:screen_retriever`, but that
  /// package converts to a top-down y for Flutter's own coordinate space,
  /// which does not match the bottom-left-origin space native positioning
  /// code on macOS actually needs; mixing the two silently mirrored the
  /// panel vertically except near screen center, where they coincide.
  /// [items] are `{'id': ..., 'title': ..., 'body': ...}` maps; `body` is
  /// included so the panel's search can filter on it, not just the title.
  Future<void> show({required List<Map<String, String>> items});

  /// Hides the panel (keeps the native window for reuse).
  Future<void> hide();

  /// Stream of events from the native panel — an item pick, a dismissal, or
  /// a render-engine boot diagnostic.
  Stream<SnippetPickerEvent> get events;

  /// Destroys the native window and releases resources.
  Future<void> dispose();
}
