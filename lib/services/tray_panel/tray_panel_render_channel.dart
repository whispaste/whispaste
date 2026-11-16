import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show FocusManager;

import '../../core/logging/app_logger.dart';
import '../../shared_render_engine_helpers.dart' show RenderChannel;
import 'tray_panel_protocol.dart';

final _log = AppLogger('TrayPanelRenderChannel');

/// Render-engine side of the tray panel shell seam. Receives snapshots
/// (`setContent`) and the shell's show/hide signals, reports button presses
/// and dismissals back (`action`, `cancel`).
class TrayPanelRenderChannel implements RenderChannel {
  TrayPanelRenderChannel({
    required String name,
    required this.onContent,
    required this.onPanelHidden,
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(name) {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// A fresh snapshot; [shown] is true for the first one of a show.
  final void Function(TrayPanelContent content, {required bool shown})
  onContent;
  final void Function() onPanelHidden;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'setContent':
        final args = call.arguments;
        final content = TrayPanelContent.tryParse(args);
        if (content != null) {
          onContent(content, shown: args is Map && args['shown'] == true);
        }
        return null;
      case 'panelHidden':
        onPanelHidden();
        return null;
      case 'moveFocus':
        // Windows: arrow keys never reach the reparented Flutter child, the
        // shell forwards them instead.
        final args = call.arguments;
        final delta = args is Map ? args['delta'] : null;
        final focus = FocusManager.instance.primaryFocus;
        if (delta is int && focus != null) {
          delta < 0 ? focus.previousFocus() : focus.nextFocus();
        }
        return null;
      default:
        return null;
    }
  }

  void action(String id) => _channel.invokeMethod('action', {'action': id});

  /// Escape pressed inside the panel.
  void cancel() => _channel.invokeMethod('cancel');

  /// The painted height changed (content or a picker opened); the shell sizes
  /// its window to [height] logical px and keeps the edge at the tray icon.
  void resize(double height) =>
      _channel.invokeMethod('resize', {'height': height});

  @override
  void notifyReady() => _channel.invokeMethod('ready');

  @override
  void reportError(String message) {
    _log.error('[tray-panel-engine-ERROR] $message');
    _channel.invokeMethod('reportError', {'message': message});
  }

  @override
  void dispose() => _channel.setMethodCallHandler(null);
}
