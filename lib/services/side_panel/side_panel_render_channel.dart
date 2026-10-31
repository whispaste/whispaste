import 'package:flutter/services.dart';

import '../../shared_render_engine_helpers.dart' show RenderChannel;
import 'side_panel_snapshot.dart';

/// The render-engine side of the side-panel shell seam, mirroring
/// [OverlayRenderChannel]'s split between native-shell plumbing and the
/// widget tree that actually paints.
///
/// Lives inside the dedicated panel Flutter engine. It receives the
/// snapshot relayed from the native shell (`updateSnapshot`, itself relayed
/// from [SidePanelService] over the public `com.whispaste.side_panel`
/// channel) and relays the two interactions the panel widget tree can
/// produce back to the native shell (`rowClicked` / `hoverLeft`), which the
/// native shell forwards to the main engine unchanged -- the wire shape
/// matches [MethodChannelSidePanelController.parseNativeEvent] exactly so no
/// reshaping happens on the native side. It owns no window state itself.
///
/// Kept separate from the entrypoint so the wiring is unit-testable without
/// booting a second engine.
class SidePanelRenderChannel implements RenderChannel {
  SidePanelRenderChannel({
    required String name,
    required this.onSnapshot,
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(name) {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Called with a fully-resolved snapshot relayed from the main engine.
  final void Function(SidePanelSnapshot snapshot) onSnapshot;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'updateSnapshot':
        final args = call.arguments;
        if (args is Map) {
          onSnapshot(SidePanelSnapshot.fromMap(args));
        }
        return null;
      default:
        return null;
    }
  }

  /// Reports a tap on the row identified by [section]/[id] within the last
  /// snapshot this engine received.
  void rowClicked(SidePanelSection section, String id) {
    _channel.invokeMethod('rowClicked', {'section': section.name, 'id': id});
  }

  /// Starts a native OS drag-out for [row] (issue 11), reporting its full
  /// insertable content (or image bytes) so the native host can begin an
  /// `NSDraggingSession` without a round-trip back to the main engine.
  /// Fire-and-forget: the native host answers with an actual drag, not a
  /// method-channel reply this engine needs to react to.
  void beginDrag(SidePanelSection section, SidePanelRow row) {
    _channel.invokeMethod('beginDrag', {
      'section': section.name,
      'id': row.id,
      'kind': row.kind.name,
      'content': row.content,
      'imageBytes': row.imageBytes,
    });
  }

  /// Reports the pointer leaving the panel (and its edge sensor zone) --
  /// the native shell orders the panel closed and relays this to the main
  /// engine as [SidePanelHoverLeft].
  void hoverLeft() {
    _channel.invokeMethod('hoverLeft');
  }

  @override
  void notifyReady() {
    _channel.invokeMethod('ready');
  }

  @override
  void reportError(String message) {
    _channel.invokeMethod('reportError', {'message': message});
  }

  /// Detaches the handler. The engine outlives individual app widgets, so
  /// this is mainly for tests and hot-restart hygiene.
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
