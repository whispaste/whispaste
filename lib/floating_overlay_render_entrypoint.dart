/// Dedicated Flutter entrypoint for the macOS floating-overlay render engine.
///
/// ADR 0002 (Approach 1 / Variant B) makes the native overlay window a
/// lifecycle-only shell: it no longer draws with CoreGraphics, it hosts a
/// **second, headless-ish Flutter engine** whose only job is to paint the
/// shared [FloatingOverlayView]. That engine is booted by the Swift
/// `FloatingOverlayHost` with the `floatingOverlayMain` entrypoint and pinned
/// into a transparent non-activating `NSPanel`.
///
/// ## The seam
///
/// The app's MAIN engine is untouched: `FloatingOverlayService` still pushes
/// `updateSnapshot` / `setWaveformBars` over the
/// `com.whispaste.floating_overlay` channel to the native host. The host then
/// **relays** those payloads to THIS engine over a private render channel
/// ([_renderChannelName]). Interaction goes the other way: this engine asks the
/// host to start a native window drag, to show the native context menu, or
/// reports a body tap — the host translates that into the existing
/// main-engine events. So the whole service/controller/event contract stays
/// exactly as it was; only the pixels move from native CoreGraphics to the
/// shared Dart painter.
library;

import 'package:flutter/widgets.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'services/floating_overlay/floating_overlay_controller_interface.dart';
import 'services/floating_overlay/overlay_render_channel.dart';
import 'shared_render_engine_helpers.dart';
import 'widgets/floating_overlay/floating_overlay_view.dart';

/// Private channel between the native overlay shell and this render engine.
///
/// Distinct from the public `com.whispaste.floating_overlay` channel the main
/// engine uses — the two engines never share a binary messenger, so the names
/// must not collide.
const String _renderChannelName = 'com.whispaste.floating_overlay_render';

/// Boots the overlay render engine.
///
/// The actual `@pragma('vm:entry-point') floatingOverlayMain` lives in
/// `main.dart` (the root library) because macOS `runWithEntrypoint:` resolves
/// the entrypoint name only against the root library — it has no `libraryURI`
/// variant. That thin entrypoint delegates here so the real wiring stays in
/// this cohesive, unit-tested file.
void runFloatingOverlayEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[overlay-engine] runFloatingOverlayEngine booted');
  runApp(const _OverlayRenderApp());
}

class _OverlayRenderApp extends StatefulWidget {
  const _OverlayRenderApp();

  @override
  State<_OverlayRenderApp> createState() => _OverlayRenderAppState();
}

class _OverlayRenderAppState
    extends RenderEngineState<_OverlayRenderApp, OverlayRenderChannel> {
  _OverlayRenderAppState()
    : super(lookupL10n(const Locale('en')).a11yRecordingOverlay);

  FloatingOverlaySnapshot _snapshot = const FloatingOverlaySnapshot(
    visible: false,
    state: OverlayVisualState.recording,
    isDark: true,
    compact: false,
    label: '',
  );
  List<double> _bars = const [];

  @override
  OverlayRenderChannel createChannel() => OverlayRenderChannel(
    name: _renderChannelName,
    onSnapshot: (s) => setState(() => _snapshot = s),
    onWaveformBars: (b) => setState(() => _bars = b),
  );

  @override
  String labelOf(L10n l10n) => l10n.a11yRecordingOverlay;

  @override
  Widget build(BuildContext context) => buildRenderEngineRoot(
    // While hidden the snapshot still renders an (empty) box; the native
    // shell is what orders the panel out, so we simply paint nothing
    // meaningful until the next visible snapshot arrives.
    semanticsLabel: semanticsLabel,
    onTap: channel.bodyClicked,
    onPanStart: channel.startDrag,
    onSecondaryOrLongPress: channel.showContextMenu,
    child: FloatingOverlayView(snapshot: _snapshot, waveformBars: _bars),
  );
}
