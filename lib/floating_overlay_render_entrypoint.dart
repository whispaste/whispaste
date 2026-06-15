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
import 'core/l10n/persisted_l10n.dart';
import 'services/floating_overlay/floating_overlay_controller_interface.dart';
import 'services/floating_overlay/overlay_render_channel.dart';
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

class _OverlayRenderAppState extends State<_OverlayRenderApp> {
  late final OverlayRenderChannel _channel;

  FloatingOverlaySnapshot _snapshot = const FloatingOverlaySnapshot(
    visible: false,
    state: OverlayVisualState.recording,
    isDark: true,
    compact: false,
    label: '',
  );
  List<double> _bars = const [];

  // Defaults to the English label until the persisted locale resolves; this
  // engine has no Localizations ancestor, so the string is looked up directly.
  String _semanticsLabel = lookupL10n(const Locale('en')).a11yRecordingOverlay;

  @override
  void initState() {
    super.initState();
    _channel = OverlayRenderChannel(
      name: _renderChannelName,
      onSnapshot: (s) => setState(() => _snapshot = s),
      onWaveformBars: (b) => setState(() => _bars = b),
    );
    // Handler is now registered — tell the native shell to flush any render
    // state it cached while this engine was still booting.
    _channel.notifyReady();
    _resolveSemanticsLabel();
  }

  Future<void> _resolveSemanticsLabel() async {
    final l10n = await resolvePersistedL10n();
    if (mounted) setState(() => _semanticsLabel = l10n.a11yRecordingOverlay);
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
      child: _OverlayGestureLayer(
        semanticsLabel: _semanticsLabel,
        // While hidden the snapshot still renders an (empty) box; the native
        // shell is what orders the panel out, so we simply paint nothing
        // meaningful until the next visible snapshot arrives.
        onPanStart: _channel.startDrag,
        onTap: _channel.bodyClicked,
        onSecondaryTapOrLongPress: _channel.showContextMenu,
        child: FloatingOverlayView(snapshot: _snapshot, waveformBars: _bars),
      ),
    );
  }
}

/// Forwards the three coarse overlay interactions to the native shell.
///
/// Fine-grained hit targets (the dedicated close `×` and stop button regions)
/// are a follow-up; the whole pill currently behaves like the spike's: drag to
/// move, tap to toggle recording, right-click for the context menu.
class _OverlayGestureLayer extends StatelessWidget {
  const _OverlayGestureLayer({
    required this.semanticsLabel,
    required this.onPanStart,
    required this.onTap,
    required this.onSecondaryTapOrLongPress,
    required this.child,
  });

  final String semanticsLabel;
  final VoidCallback onPanStart;
  final VoidCallback onTap;
  final VoidCallback onSecondaryTapOrLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: (_) => onPanStart(),
        onSecondaryTap: onSecondaryTapOrLongPress,
        onLongPress: onSecondaryTapOrLongPress,
        child: child,
      ),
    );
  }
}
