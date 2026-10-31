import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../shared_render_engine_helpers.dart' show RenderChannel;

final _log = AppLogger('SnippetPickerRenderChannel');

/// A snippet as relayed to the render engine — mirrors the `{'id', 'title',
/// 'body'}` map shape [MacOSSnippetPickerController.show] sends natively.
class SnippetPickerRenderItem {
  const SnippetPickerRenderItem({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;

  static SnippetPickerRenderItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final body = raw['body'];
    if (id is! String || title is! String || body is! String) return null;
    return SnippetPickerRenderItem(id: id, title: title, body: body);
  }
}

/// The render-engine side of the Snippet-Picker shell seam (dictation-
/// automations ticket 06), mirroring [FloatingButtonRenderChannel]'s split
/// between native-shell plumbing and the widget tree that actually paints.
///
/// Lives inside the dedicated picker Flutter engine. It receives the item
/// list from the native shell (`setItems`, sent once per `show()`) and
/// relays the two possible outcomes back (`selectItem` / `cancel`). Kept
/// separate from the entrypoint so the wiring is unit-testable without
/// booting a second engine.
class SnippetPickerRenderChannel implements RenderChannel {
  SnippetPickerRenderChannel({
    required String name,
    required this.onItems,
    required this.onSubmit,
    required this.onPanelHidden,
    required this.onMoveHighlight,
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(name) {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Called when the native shell relays a fresh item list for this `show()`.
  final void Function(List<SnippetPickerRenderItem> items) onItems;

  /// Called when the native shell's own `NSEvent` monitor sees Return/Enter
  /// while the picker panel is key — a local monitor bypasses the search
  /// field's embedded `NSTextInputClient` entirely (see
  /// `SnippetPickerHost.returnMonitor`), the same fix already applied to
  /// Escape for the identical reason: that embedded proxy's
  /// `doCommandBySelector:` forwarding to Flutter's text-input channel is
  /// fragile and stopped reliably delivering `insertNewline:` (which used to
  /// reach `TextInputAction.done`/`onSubmitted`) after the panel's view
  /// controller started being detached/reattached on every `show()`.
  final VoidCallback onSubmit;

  /// Called when the native shell's `dismiss()` orders the panel off screen.
  ///
  /// Exists because this engine is deliberately detached from the embedder's
  /// app lifecycle (see `detachFromEmbedderAppLifecycle` in the entrypoint):
  /// with frames never lifecycle-disabled any more, the panel's own glass
  /// animations must be gated on the *relayed* visibility instead, or the
  /// drift cycle would keep repainting an invisible panel for the rest of
  /// the app session. `setItems` is the matching "panel shown" signal.
  final VoidCallback onPanelHidden;

  /// Called when the native shell's VK_UP/VK_DOWN subclass on the render
  /// engine's own HWND (see `snippet_picker_window.h` on Windows) intercepts
  /// an arrow key — Windows' Flutter embedder never delivers those as
  /// `LogicalKeyboardKey` events to this engine's widget tree (confirmed via
  /// on-device testing, ticket 29), the same routing gap Return/Escape hit
  /// on macOS, just for a different pair of keys. [delta] is -1 (up) or +1
  /// (down).
  final void Function(int delta) onMoveHighlight;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'setItems':
        final args = call.arguments;
        if (args is Map) {
          final raw = args['items'];
          if (raw is List) {
            onItems([
              for (final entry in raw) ?SnippetPickerRenderItem.tryParse(entry),
            ]);
          }
        }
        return null;
      case 'submitHighlighted':
        onSubmit();
        return null;
      case 'panelHidden':
        onPanelHidden();
        return null;
      case 'moveHighlight':
        final args = call.arguments;
        if (args is Map) {
          final delta = args['delta'];
          if (delta is int) onMoveHighlight(delta);
        }
        return null;
      default:
        return null;
    }
  }

  /// Reports that the user clicked the snippet with [id] — the native shell
  /// closes the panel and relays this to the main engine as `onItemSelected`.
  void selectItem(String id) {
    _channel.invokeMethod('selectItem', {'id': id});
  }

  /// Reports a dismissal without a selection (Esc, focus lost) — the native
  /// shell closes the panel and relays this as `onCancelled`.
  void cancel() {
    _channel.invokeMethod('cancel');
  }

  @override
  void notifyReady() {
    _channel.invokeMethod('ready');
  }

  @override
  void reportError(String message) {
    _log.error('[snippet-picker-engine-ERROR] $message');
    _channel.invokeMethod('reportError', {'message': message});
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
