/// Shared infrastructure for the app's post-recording prompt dialogs (review,
/// support): the fade-in barrier scaffold ([showWpAnimatedPromptDialog]) and
/// the delayed, show-once-at-a-time trigger ([WpPostRecordingPromptDelay]).
/// Extracted so each prompt's own watcher/dialog file can focus on its
/// content instead of re-deriving this boilerplate — unlike
/// [package:whispaste/widgets/dialog.dart]'s `showWpFormDialog`,
/// [showWpAnimatedPromptDialog] uses a flat barrier (no blur), which is the
/// deliberate, lighter-weight treatment these transient prompts use.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/prompt_timing.dart';

/// Shows [contentBuilder] behind a fading, flat-color barrier.
///
/// [contentBuilder] receives the shared entrance [Animation] so the caller's
/// content can drive its own slide/scale transition in sync with the barrier
/// fade.
Future<T?> showWpAnimatedPromptDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, Animation<double> animation)
  contentBuilder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, _, _) {
      final opacity = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final isDark = Theme.of(ctx).brightness == Brightness.dark;

      return FadeTransition(
        opacity: opacity,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: wpDialogBarrierColor(isDark)),
            ),
            contentBuilder(ctx, animation),
          ],
        ),
      );
    },
  );
}

/// Mixin providing the shared "wait [kPostRecordingPromptDelay], then show
/// at most once at a time, cancel-safe on dispose" pattern used by the app's
/// post-recording prompt watchers.
mixin WpPostRecordingPromptDelay<T extends StatefulWidget> on State<T> {
  Timer? _promptDelay;
  bool _promptDialogShowing = false;

  @override
  void dispose() {
    _promptDelay?.cancel();
    super.dispose();
  }

  /// Starts the delayed trigger if [shouldShow] is true and no trigger is
  /// already pending or in flight. [onDelayElapsed] fires after the delay,
  /// only if the widget is still mounted.
  void maybeShowAfterDelay(bool shouldShow, VoidCallback onDelayElapsed) {
    if (!shouldShow || _promptDialogShowing) return;
    _promptDialogShowing = true;
    _promptDelay = Timer(kPostRecordingPromptDelay, () {
      if (!mounted) {
        _promptDialogShowing = false;
        return;
      }
      onDelayElapsed();
    });
  }

  /// Call once the dialog has closed (any resolution) so a future prompt can
  /// trigger again.
  void markPromptDialogClosed() {
    _promptDialogShowing = false;
  }
}
