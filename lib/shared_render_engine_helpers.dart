/// Shared helpers for the floating-button and floating-overlay render engines.
///
/// Both engines need a gesture-detector widget with identical semantics:
/// drag-to-move, tap, and secondary/long-press, as well as a shared pattern
/// for resolving the persisted semantics label asynchronously.  Extracting
/// those pieces here removes the structural duplication between the two
/// entrypoints.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/persisted_l10n.dart';

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
    _resolveSemanticsLabel();
  }

  Future<void> _resolveSemanticsLabel() async {
    final l10n = await resolvePersistedL10n();
    if (mounted) setState(() => semanticsLabel = labelOf(l10n));
  }

  @override
  void dispose() {
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
