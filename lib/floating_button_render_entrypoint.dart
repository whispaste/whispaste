/// Dedicated Flutter entrypoint for the macOS floating-button render engine.
///
/// ADR 0002 (Approach 1 / Variant B) makes the native button window a
/// lifecycle-only shell: it no longer draws with CoreGraphics, it hosts a
/// **second, headless-ish Flutter engine** whose only job is to paint the
/// shared [FloatingButtonView]. That engine is booted by the Swift
/// `FloatingButtonHost` with the `floatingButtonMain` entrypoint and pinned
/// into a transparent non-activating [FloatingButtonPanel].
///
/// ## The seam
///
/// The app's MAIN engine is untouched: `MacOSFloatingButtonController` still
/// pushes `show` / `setState` / `setTheme` / etc. over the
/// `com.whispaste.floating_button` channel to the native host. The host then
/// **relays** those payloads to THIS engine over a private render channel
/// (`com.whispaste.floating_button_render`). Interaction goes the other way:
/// this engine asks the host to start a native window drag, to show the native
/// context menu, or reports a tap — the host translates that into the existing
/// main-engine events. So the whole service/controller/event contract stays
/// exactly as it was; only the pixels move from native CoreGraphics to the
/// shared Dart painter.
library;

import 'package:flutter/widgets.dart';

import 'services/floating_button/floating_button_controller_interface.dart';
import 'services/floating_button/floating_button_render_channel.dart';
import 'widgets/floating_button/floating_button_view.dart';

/// Private channel between the native button shell and this render engine.
///
/// Distinct from the public `com.whispaste.floating_button` channel the main
/// engine uses — the two engines never share a binary messenger, so the names
/// must not collide.
const String _renderChannelName = 'com.whispaste.floating_button_render';

/// Boots the button render engine.
///
/// The actual `@pragma('vm:entry-point') floatingButtonMain` lives in
/// `main.dart` (the root library) because macOS `runWithEntrypoint:` resolves
/// the entrypoint name only against the root library — it has no `libraryURI`
/// variant. That thin entrypoint delegates here so the real wiring stays in
/// this cohesive, unit-tested file.
void runFloatingButtonEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[button-engine] runFloatingButtonEngine booted');
  runApp(const _ButtonRenderApp());
}

class _ButtonRenderApp extends StatefulWidget {
  const _ButtonRenderApp();

  @override
  State<_ButtonRenderApp> createState() => _ButtonRenderAppState();
}

class _ButtonRenderAppState extends State<_ButtonRenderApp> {
  late final FloatingButtonRenderChannel _channel;

  FloatingButtonVisualState _state = FloatingButtonVisualState.idle;
  double _diameter = 56;

  @override
  void initState() {
    super.initState();
    _channel = FloatingButtonRenderChannel(
      name: _renderChannelName,
      onState: (s) => setState(() => _state = s),
      onDiameter: (d) => setState(() => _diameter = d),
    );
    // Handler is now registered — tell the native shell to flush any render
    // state it cached while this engine was still booting.
    _channel.notifyReady();
  }

  @override
  void dispose() {
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No Material/Scaffold and no background fill: the engine surface is
    // cleared by the native shell, so anything we don't paint stays
    // transparent. Directionality is provided defensively for any future
    // text-bearing descendant; the painter itself needs none.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _ButtonGestureLayer(
        onTap: _channel.clicked,
        onPanStart: _channel.startDrag,
        onSecondary: _channel.showContextMenu,
        child: FloatingButtonView(state: _state, diameter: _diameter),
      ),
    );
  }
}

/// Forwards the three coarse button interactions to the native shell.
///
/// Drag to move, tap to toggle recording, right-click / long-press for the
/// context menu — mirroring the old native-drawing view's mouse handlers.
class _ButtonGestureLayer extends StatelessWidget {
  const _ButtonGestureLayer({
    required this.onTap,
    required this.onPanStart,
    required this.onSecondary,
    required this.child,
  });

  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final VoidCallback onSecondary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onPanStart(),
      onSecondaryTap: onSecondary,
      onLongPress: onSecondary,
      child: child,
    );
  }
}
