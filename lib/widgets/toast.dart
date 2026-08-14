/// Premium toast notification widget — slides in from the bottom-right with
/// themed styling, icon, and smooth animation. Replaces default SnackBars.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/telemetry_service.dart';
import 'wp_button.dart';

/// Toast severity levels — controls icon, color, and animation style.
enum WpToastType { success, error, info, warning }

/// Copies [text] to the clipboard, counts a `copy` telemetry event under
/// [category], and shows the standard "Copied to clipboard" toast.
///
/// The shared shape behind every list page's row-level copy action
/// (History, Snippets, …) — pulled out once two independent pages needed
/// the identical four lines, rather than duplicated per page.
void copyToClipboardWithToast({
  required BuildContext context,
  required WidgetRef ref,
  required String text,
  required String category,
}) {
  Clipboard.setData(ClipboardData(text: text));
  ref
      .read(telemetrySessionAggregatorProvider)
      .count(category: category, action: 'copy');
  if (!context.mounted) return;
  WpToast.show(
    context,
    message: L10n.of(context).historyCopiedToClipboard,
    type: WpToastType.success,
    duration: const Duration(seconds: 2),
  );
}

/// Bundled label + callback for an actionable toast.
///
/// Use with [WpToast.show]'s [WpToast.show.action] parameter to render a
/// trailing text-button on the toast card. The PRD-driven actions are
/// things like „Einstellungen öffnen", „Erneut versuchen", „App schließen"
/// and „Diagnose kopieren" — each one points the user at a single concrete
/// next step instead of a generic „Etwas ist schiefgelaufen"-Meldung.
///
/// Equivalent to passing the legacy [WpToast.show.actionLabel] /
/// [WpToast.show.onAction] pair, but bundles the two together so call
/// sites cannot forget one half. Tapping the button fires [onPressed] and
/// dismisses the toast.
class WpToastAction {
  const WpToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Show a premium toast notification.
///
/// Usage:
/// ```dart
/// WpToast.show(context, message: 'Copied!', type: WpToastType.success);
/// ```
class WpToast {
  WpToast._();

  static final _log = AppLogger('Toast');

  /// Show a toast.
  ///
  /// Pass [action] (preferred) or the legacy [actionLabel]+[onAction] pair
  /// to render an action button on the toast card. When both are passed,
  /// [action] wins. The action button fires its callback and then
  /// dismisses the toast.
  static void show(
    BuildContext context, {
    required String message,
    WpToastType type = WpToastType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    WpToastAction? action,
  }) {
    // The bundled [WpToastAction] is the canonical surface — fall back to
    // the legacy split pair so older call sites keep working unchanged.
    final String? resolvedLabel = action?.label ?? actionLabel;
    final VoidCallback? resolvedOnAction = action?.onPressed ?? onAction;
    // Route toast messages through the logging pipeline so they appear
    // in the `flutter run` terminal in debug mode.
    //
    // Error-toasts go in at warning level so they land as Sentry breadcrumbs
    // (context for any later crash), not as standalone Sentry issues — the
    // overwhelming majority are user-config noise (mute mic, blocked
    // permission), not bugs. The underlying failure that triggered the toast
    // should emit its own captureException at the source if it is actually
    // a bug.
    switch (type) {
      case WpToastType.error:
        _log.warning('TOAST: $message');
      case WpToastType.warning:
        _log.warning('TOAST: $message');
      case WpToastType.success:
        _log.info('TOAST: $message');
      case WpToastType.info:
        _log.info('TOAST: $message');
    }

    // Screen readers get no visual cue that a toast appeared, so announce it
    // explicitly — the toast card itself is only a visual overlay, not a
    // focusable widget a screen reader would land on.
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );

    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    late final AnimationController controller;
    var dismissed = false;

    void dismiss() {
      if (dismissed) return;
      dismissed = true;
      try {
        controller.reverse().then((_) {
          try {
            if (entry.mounted) entry.remove();
          } catch (e) {
            _log.debug('Toast overlay entry remove failed (non-fatal): $e');
          }
          try {
            controller.dispose();
          } catch (e) {
            _log.debug(
              'Toast animation controller dispose failed (non-fatal): $e',
            );
          }
        });
      } catch (e) {
        // Controller already disposed or in bad state — force cleanup.
        _log.debug('Toast reverse animation failed, forcing cleanup: $e');
        try {
          if (entry.mounted) entry.remove();
        } catch (e2) {
          _log.debug(
            'Toast force-cleanup entry remove failed (non-fatal): $e2',
          );
        }
      }
    }

    controller = AnimationController(
      vsync: overlay,
      duration: WpMotion.durationFor(
        context,
        const Duration(milliseconds: 300),
      ),
      reverseDuration: WpMotion.durationFor(
        context,
        const Duration(milliseconds: 200),
      ),
    );

    entry = OverlayEntry(
      builder: (context) => _WpToastOverlay(
        message: message,
        type: type,
        animation: controller,
        actionLabel: resolvedLabel,
        onAction: resolvedOnAction,
        onDismiss: dismiss,
      ),
    );

    overlay.insert(entry);
    controller.forward();

    // Auto-dismiss after duration — guarded by the same `dismissed` flag.
    Future.delayed(duration, dismiss);
  }
}

class _WpToastOverlay extends StatelessWidget {
  const _WpToastOverlay({
    required this.message,
    required this.type,
    required this.animation,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final WpToastType type;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 56,
      right: WpSpacing.lg,
      left: null,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            ),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: _ToastCard(
            message: message,
            type: type,
            onDismiss: onDismiss,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.message,
    required this.type,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final WpToastType type;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Line budget for the message, grown in step with the system text size.
  ///
  /// The card is capped at 400 px wide, so a long message is wrapped rather
  /// than widened, and the cap exists to stop a toast from turning into a
  /// wall of text. But a *fixed* cap silently shrinks how much of the message
  /// survives as the user raises the system text size: the same string that
  /// fits four lines at 1.0× needs six at 1.6×, and the tail — usually the
  /// actionable half, e.g. „Bitte WhisPaste manuell aus Systemeinstellungen →
  /// Bedienungshilfen entfernen" — is what the ellipsis eats. Users who need
  /// large text are the last ones who should get the abbreviated instruction.
  ///
  /// So the budget scales with the text scaler and only the *ratio* stays
  /// fixed: the card grows to roughly the same fraction of the window it
  /// occupies at 1.0×. The upper clamp keeps a pathologically long message
  /// (an interpolated exception string) from filling the screen.
  ///
  /// Screen-reader users were never affected — the `Semantics(label:)` below
  /// and `sendAnnouncement()` in [WpToast.show] both carry the full string
  /// regardless of what the ellipsis hides. This is a sighted-user-only fix.
  static int _maxLines(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    return (4 * scale).ceil().clamp(4, 8);
  }

  (IconData, Color) _iconAndColor() {
    return switch (type) {
      WpToastType.success => (LucideIcons.circleCheck, WpColors.success),
      WpToastType.error => (LucideIcons.circleAlert, WpColors.error),
      WpToastType.warning => (LucideIcons.triangleAlert, WpColors.warning),
      WpToastType.info => (LucideIcons.info, WpColors.accent),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconAndColor();
    const surfaceBg = WpColors.surfaceElevated;
    const textPrimary = WpColors.textPrimary;
    const borderColor = WpColors.borderDefault;

    return Semantics(
      // Not a liveRegion: WpToast.show() already calls sendAnnouncement()
      // explicitly once, precisely when the toast is inserted — combining
      // that with liveRegion risks a double announcement (liveRegion fires
      // its own announcement on semantics-tree changes). The label here is
      // for a screen-reader user who navigates directly to the toast — the
      // rendered message below is excluded so it is not stated twice, and
      // because that `Text` is clipped to `_maxLines` with an ellipsis while
      // this label carries the message whole.
      //
      // Not `MergeSemantics`: a toast can hold an action button and always
      // holds a close button, and merging would swallow both.
      label: message,
      container: true,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: surfaceBg,
              borderRadius: BorderRadius.circular(WpRadius.md),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Accent line
                Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                // Icon
                Icon(icon, size: 18, color: color),
                const SizedBox(width: WpSpacing.sm),
                // Message
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      // labelMedium = Type/label role (13 / 500). Compact
                      // line-height (1.3 vs theme's 1.4) preserved for the
                      // tight toast card layout.
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: textPrimary,
                        height: 1.3,
                      ),
                      maxLines: _maxLines(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // Action button (optional)
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(width: WpSpacing.sm),
                  // The status colour stays on the icon and the accent line;
                  // the action reads as an action, in the one colour every
                  // other action in the app uses.
                  WpButton(
                    label: actionLabel!,
                    variant: WpButtonVariant.ghost,
                    size: WpButtonSize.dense,
                    onPressed: () {
                      onAction!();
                      onDismiss();
                    },
                  ),
                ],
                const SizedBox(width: WpSpacing.xs),
                // Close button
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(WpRadius.full),
                  child: const Padding(
                    padding: EdgeInsets.all(WpSpacing.xxs),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: WpColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
