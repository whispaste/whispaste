/// Dedicated Flutter entrypoint for the macOS floating-overlay render engine.
///
/// ADR 0002 (Approach 1 / Variant B) makes the native overlay window a
/// lifecycle-only shell: it no longer draws with CoreGraphics, it hosts a
/// **second, headless-ish Flutter engine** whose only job is to paint the
/// shared [WpFloatingOverlayView]. That engine is booted by the Swift
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

import 'core/accessibility/accessibility_reply_binding.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/theme/overlay_design_spec.dart';
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
  bootstrapFloatingOverlayEngine();
  debugPrint('[overlay-engine] runFloatingOverlayEngine booted');
  runApp(const _OverlayRenderApp());
}

/// Everything [runFloatingOverlayEngine] does before `runApp` — the
/// process-wide invariants this engine needs, split out so they are testable
/// without booting a widget tree that talks to the native shell.
///
/// The lifecycle detach is load-bearing, not hygiene: without it a single
/// app-global `AppLifecycleState.hidden` (which a close-to-tray app receives
/// on any `applicationWillResignActive` while this late-booted engine still
/// carries the embedder's stale `_visible = NO`) sets `framesEnabled = false`
/// here for the rest of the session. The panel is then ordered front over a
/// surface that never gets a new frame, so the overlay stays invisible for
/// every recording after the one that booted the engine — the live
/// 2026-09-01 report. See [detachFromEmbedderAppLifecycle] for the full
/// mechanism; [WpFloatingOverlayView] gates its continuous animations on
/// [FloatingOverlaySnapshot.visible] so an always-live engine still stops
/// repainting an ordered-out panel.
@visibleForTesting
void bootstrapFloatingOverlayEngine() {
  WpRenderEngineBinding.ensureInitialized();
  detachFromEmbedderAppLifecycle();
}

/// Whether a click at [position] (window-local) lands on the pill's X.
///
/// The geometry comes from [OverlayDesignSpec.closeHitRect], the same numbers
/// the painter places the glyph with. The pill width is the state's target
/// width, which the animated width settles on. A notice card replaces the
/// pill and has no X.
@visibleForTesting
bool isCloseTap(FloatingOverlaySnapshot snapshot, Offset position) {
  if (!snapshot.visible || snapshot.notice != null) return false;
  final sizeSpec = OverlayDesignSpec.sizeFor(snapshot.size);
  final width = OverlayDesignSpec.pillWidthForText(
    WpFloatingOverlayView.designStateFor(snapshot.state),
    sizeSpec,
    OverlayDesignSpec.layoutFor(snapshot.size),
    WpFloatingOverlayView.statusTextFor(snapshot),
    secondaryText: WpFloatingOverlayView.secondaryTextFor(snapshot),
  );
  final hit = OverlayDesignSpec.closeHitRect(
    variant: snapshot.size,
    showCancel: snapshot.appearance.showCancel,
    pillWidth: width,
  );
  return hit != null && hit.contains(position);
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
    label: '',
  );
  List<double> _bars = const [];

  /// Acknowledges the first painted frame of each show to the native shell
  /// (ticket phase 2 frame heartbeat). Created lazily: `channel` exists only
  /// after [initState].
  late final OverlayFrameHeartbeat _heartbeat = OverlayFrameHeartbeat(
    onFrame: () => channel.frameRendered(),
  );

  @override
  OverlayRenderChannel createChannel() => OverlayRenderChannel(
    name: _renderChannelName,
    onSnapshot: _onSnapshot,
    onWaveformBars: (b) => setState(() => _bars = b),
  );

  @override
  String labelOf(L10n l10n) => l10n.a11yRecordingOverlay;

  void _onSnapshot(FloatingOverlaySnapshot s) {
    final previous = _snapshot;
    setState(() => _snapshot = s);
    _heartbeat.onSnapshot(visible: s.visible);
    // The main engine pre-localises [FloatingOverlaySnapshot.label] for the
    // active locale, so it's announced verbatim — only on an actual state
    // change while the overlay is visible, never on every relayed snapshot
    // (waveform updates land ~30/s and share the same state). A frame the
    // main engine has read out already stays quiet (#633).
    if (s.visible && !s.announced && s.state != previous.state) {
      announce(s.label);
    }
    // A notice card (overlay F2) is announced once when it appears or its
    // kind changes, not on every countdown tick.
    final notice = s.notice;
    if (s.visible && notice != null && notice.kind != previous.notice?.kind) {
      announce(notice.announcement);
    }
  }

  /// The static role label plus the currently-painted status text (mirrors
  /// [WpFloatingOverlayView.statusTextFor]), so a screen-reader user who
  /// explores this element on demand — not just one listening for the
  /// [announce] fired on state change — also hears the current state
  /// instead of only a generic "recording overlay".
  String get _composedSemanticsLabel {
    if (!_snapshot.visible) return semanticsLabel;
    final statusText = WpFloatingOverlayView.statusTextFor(_snapshot);
    return statusText.isEmpty ? semanticsLabel : '$semanticsLabel, $statusText';
  }

  /// A click on the painted X cancels the dictation; a click anywhere else
  /// toggles recording. Notice cards have no X and keep their own buttons.
  void _onTapAt(Offset position) {
    if (isCloseTap(_snapshot, position)) {
      channel.closeClicked();
    } else {
      channel.bodyClicked();
    }
  }

  @override
  Widget build(BuildContext context) => buildRenderEngineRoot(
    // While hidden the snapshot renders an empty box; the native shell is what
    // orders the panel out. The empty box alone would make every resize of the
    // hidden panel stall, see [HiddenSurfaceFill].
    semanticsLabel: _composedSemanticsLabel,
    onTap: channel.bodyClicked,
    onTapAt: _onTapAt,
    onPanStart: channel.startDrag,
    onSecondaryOrLongPress: channel.showContextMenu,
    child: HiddenSurfaceFill(
      hidden: !_snapshot.visible,
      child: WpFloatingOverlayView(
        snapshot: _snapshot,
        waveformBars: _bars,
        onNoticeAction: (action) => channel.noticeAction(action.id),
        onPillWidth: channel.pillWidth,
      ),
    ),
  );
}
