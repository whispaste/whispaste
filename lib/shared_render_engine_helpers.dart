/// Shared helpers for the floating-button and floating-overlay render engines.
///
/// Both engines need a gesture-detector widget with identical semantics:
/// drag-to-move, tap, and secondary/long-press, as well as a shared pattern
/// for resolving the persisted semantics label asynchronously.  Extracting
/// those pieces here removes the structural duplication between the two
/// entrypoints.
library;

import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/persisted_l10n.dart';

/// Detaches a secondary render engine from the embedder's app-lifecycle
/// stream.
///
/// Every macOS `FlutterEngine` derives an app-lifecycle state from two
/// per-engine flags (`_active` / `_visible`) that are fed exclusively by
/// **app-global** `NSApplication` activation and occlusion notifications, and
/// both start out `NO`: `FlutterAppLifecycleRegistrar.addDelegate` never
/// replays the current state to a late registrant. A secondary engine that
/// boots after launch therefore carries a stale `_visible = NO` until macOS
/// happens to post the next occlusion change — and for a close-to-tray app
/// that fires rarely, while `applicationWillResignActive` (which maps
/// `_active = NO` + stale `_visible = NO` straight onto
/// `AppLifecycleState.hidden`) fires every time the user clicks back into the
/// app they are dictating into.
///
/// A single bogus `hidden` is enough to wedge such an engine for the rest of
/// the session: [SchedulerBinding] answers it with `framesEnabled = false`,
/// after which `scheduleFrame()` is a no-op, so every `setState` and every
/// running [AnimationController] updates state without ever producing a
/// frame. The panel then keeps showing whatever was last composited (for the
/// overlay: the fully transparent frame its hide snapshot left behind), no
/// matter how healthy the native shell and the relay channel are.
///
/// These engines have no meaningful app lifecycle of their own — their real
/// visibility is governed solely by their native host's show/hide, which is
/// already relayed in-band (the picker's `setItems`/`panelHidden`, the
/// overlay's `FloatingOverlaySnapshot.visible`). So the correct lifecycle for
/// them is "always live"; replacing the `flutter/lifecycle` handler unhooks
/// [SchedulerBinding] and `FocusManager` from the bogus embedder signal.
///
/// Callers MUST gate their continuous animations on the relayed visibility
/// instead — with frames never lifecycle-disabled any more, an ungated
/// `repeat()` would repaint an ordered-out window for the whole session.
///
/// First diagnosed live for the Snippet-Picker engine (2026-08-13), then for
/// the floating overlay (2026-09-01) with the same signature: the render
/// engine logs every relayed snapshot while the native panel reports
/// `isVisible=true` at a correct on-screen frame, and nothing is painted.
void detachFromEmbedderAppLifecycle() {
  SystemChannels.lifecycle.setMessageHandler((message) async => message);
}

/// Abstract base for the two render-engine State classes.
///
/// Provides:
/// - [semanticsLabel] storage with a language-appropriate default.
/// - [initRenderEngine]: notifies the native shell channel, then asynchronously
///   resolves the persisted locale and updates [semanticsLabel] via [setState].
/// - [disposeRenderEngine]: subclasses call this from [State.dispose] before
///   `super.dispose()` to dispose their channel without repeating the pattern.
/// Minimal lifecycle contract shared by both render-engine channels.
///
/// Implemented by [FloatingButtonRenderChannel] and [OverlayRenderChannel]
/// so that [RenderEngineState] can manage the channel lifecycle without
/// depending on either concrete type.
abstract interface class RenderChannel {
  void notifyReady();

  /// Reports an uncaught Dart error from this render engine back to the
  /// native shell, best-effort (fire-and-forget, no native receiver required).
  ///
  /// Investigation note (`.scratch/floating-overlay-render-gap/issues/01`):
  /// before this existed, an exception thrown while rebuilding the render
  /// engine's widget tree (e.g. reacting to a relayed snapshot) had NO
  /// visibility anywhere — not in `NSLog`/`log show`, not in the app's
  /// persistent log — because it never crosses back to the main engine that
  /// owns `AppLogger`. Wiring it through [FlutterError.onError] turns a
  /// silently-frozen overlay into a diagnosable log entry.
  void reportError(String message);
  void dispose();
}

abstract class RenderEngineState<
  W extends StatefulWidget,
  C extends RenderChannel
>
    extends State<W> {
  /// The ARIA / TalkBack label for the render-engine surface.
  ///
  /// Initialised to the English default (no Localizations ancestor available
  /// in a secondary engine); updated asynchronously after [initState].
  String semanticsLabel;

  RenderEngineState(this.semanticsLabel);

  /// The channel managed by this engine. Initialised in [initState].
  late final C channel;

  /// The resolved localisation, once [_resolveSemanticsLabel] completes.
  ///
  /// Null until then (no [Localizations] ancestor exists in a secondary
  /// engine, so subclasses that need more than [semanticsLabel] — e.g. a
  /// per-state screen-reader announcement — read this instead of hardcoding
  /// English).
  @protected
  L10n? get l10n => _l10n;
  L10n? _l10n;

  /// Posts a screen-reader announcement for this engine's surface.
  ///
  /// Both the floating button and the floating overlay are the app's only
  /// feedback for the core recording workflow that lives outside the main
  /// window; without an explicit announcement a screen-reader user gets no
  /// signal at all when recording starts, finishes transcribing, or errors.
  @protected
  void announce(String message) {
    if (!mounted || message.isEmpty) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  /// Creates the concrete channel. Called by [initState].
  ///
  /// Subclasses return the platform-specific channel with all callbacks wired.
  @protected
  C createChannel();

  /// Extracts the semantics label from the resolved [L10n].
  ///
  /// Called after the persisted locale is resolved to update [semanticsLabel].
  @protected
  String labelOf(L10n l10n);

  @override
  void initState() {
    super.initState();
    channel = createChannel();
    channel.notifyReady();
    _installErrorReporting();
    _resolveSemanticsLabel();
  }

  /// Routes uncaught Flutter errors in this render engine back to the native
  /// shell (via [RenderChannel.reportError]) in addition to the default
  /// console dump — see [RenderChannel.reportError] for why this matters.
  ///
  /// Installed once per engine instance; a fresh engine (e.g. after the
  /// native host's boot-race retry) reinstalls it via a new [initState].
  ///
  /// Restored to the framework default in [dispose] — mainly relevant for
  /// tests and hot-restart (a real render engine's root widget lives for the
  /// isolate's lifetime and is never disposed while the engine keeps
  /// running), but cheap and correct hygiene regardless: it stops a stale
  /// closure from ever calling [RenderChannel.reportError] on an already-
  /// disposed [channel].
  void _installErrorReporting() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      channel.reportError(details.exceptionAsString());
    };
  }

  Future<void> _resolveSemanticsLabel() async {
    final resolved = await resolvePersistedL10n();
    _l10n = resolved;
    if (mounted) setState(() => semanticsLabel = labelOf(resolved));
  }

  @override
  void dispose() {
    FlutterError.onError = FlutterError.presentError;
    channel.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------

/// Wraps [child] in the standard render-engine root widget tree:
/// a [Directionality] (always LTR) containing a [RenderEngineGestureLayer].
///
/// Extracted here because both the button and overlay State.build() bodies
/// share this exact outer structure; only the inner [child] differs.
Widget buildRenderEngineRoot({
  required String semanticsLabel,
  required VoidCallback onTap,
  required VoidCallback onPanStart,
  required VoidCallback onSecondaryOrLongPress,
  required Widget child,
}) {
  // No Material/Scaffold and no background fill: the engine surface is
  // cleared by the native shell, so anything we don't paint stays
  // transparent.  Directionality is provided defensively for any future
  // text-bearing descendant; the painter itself needs none.
  return Directionality(
    textDirection: TextDirection.ltr,
    // loam-ignore: a11y-interactive-semantics – semantics provided in RenderEngineGestureLayer.build
    child: RenderEngineGestureLayer(
      semanticsLabel: semanticsLabel,
      onTap: onTap,
      onPanStart: onPanStart,
      onSecondaryOrLongPress: onSecondaryOrLongPress,
      child: child,
    ),
  );
}

/// Wraps [child] with a [Semantics] button and a [GestureDetector] that
/// forwards the three coarse interactions used by both render engines.
///
/// - [onTap] — primary action (toggle recording / body click).
/// - [onPanStart] — native window drag.
/// - [onSecondaryOrLongPress] — context menu (right-click or long-press).
class RenderEngineGestureLayer extends StatelessWidget {
  const RenderEngineGestureLayer({
    super.key,
    required this.semanticsLabel,
    required this.onTap,
    required this.onPanStart,
    required this.onSecondaryOrLongPress,
    required this.child,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final VoidCallback onSecondaryOrLongPress;
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
        onSecondaryTap: onSecondaryOrLongPress,
        onLongPress: onSecondaryOrLongPress,
        child: child,
      ),
    );
  }
}
