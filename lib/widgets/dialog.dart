/// Reusable WhisPaste dialog with frosted glass backdrop.
///
/// Use [showWpDialog] convenience function for standard dialogs.
/// Use [showWpConfirmDialog] for yes/no confirmations.
/// Use [showWpFormDialog] + [WpFormDialogShell] for dialogs with form fields.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';

/// How much room a dialog card asks for.
///
/// A *named* axis rather than a free `width` parameter, for the reason
/// `WpSearchField`'s library docs spell out at length: a free number produces
/// N accidents instead of N decisions, and dialogs are the last place that can
/// afford to drift. Two values is the whole vocabulary — add a third only when
/// a case genuinely cannot be answered by either.
enum WpDialogSize {
  /// The default: a column of short form fields, a confirmation, a message.
  standard,

  /// Twice the measure, for a dialog whose *content is a document* — text the
  /// user writes and re-reads rather than fills in. Currently the snippet
  /// editor, whose body holds multi-paragraph prompt templates and which read
  /// as a slot rather than an editor at [standard].
  wide,
}

/// Width every WhisPaste dialog card shares — content dialogs, confirmations
/// and form dialogs alike. Clamped against the viewport in [_WpDialogSurface].
const double _kDialogWidth = 420;

/// Width of a [WpDialogSize.wide] card. ~85 characters at the 13 dp form
/// metrics, i.e. the same prose measure History caps its transcript at.
const double _kWideDialogWidth = 760;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows a WhisPaste-styled dialog.
///
/// [title] is rendered as `titleLarge`. [content] is the body widget.
/// Provide [actions] for custom button rows; otherwise no buttons are shown.
///
/// Set [dismissible] to `false` for a dialog the user must not walk away from
/// (a destructive operation in flight, for instance): the barrier stops
/// dismissing on tap and a `PopScope` blocks the back/Esc route pop. Such a
/// dialog is responsible for popping itself once its work is done.
///
/// [useRootNavigator] pushes onto the root navigator — needed when the dialog
/// must outlive a nested navigator (e.g. a settings page being torn down by
/// the very operation the dialog reports on).
Future<T?> showWpDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
  bool dismissible = true,
  bool useRootNavigator = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // painted by the transition builder
    transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
    useRootNavigator: useRootNavigator,
    pageBuilder: (_, a2, a3) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return PopScope(
        canPop: dismissible,
        child: _WpDialogBarrier(
          animation: animation,
          child: _WpDialogContainer(
            animation: animation,
            title: title,
            content: content,
            actions: actions,
          ),
        ),
      );
    },
  );
}

/// Shows a confirmation dialog. Returns `true` if confirmed, `false` or
/// `null` otherwise.
///
/// Set [destructive] to `true` to render the confirm button in error color
/// (for delete / reset operations).
Future<bool> showWpConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
    pageBuilder: (_, a2, a3) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return _WpDialogBarrier(
        animation: animation,
        child: _WpConfirmContent(
          animation: animation,
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          destructive: destructive,
        ),
      );
    },
  );
  return result ?? false;
}

/// Shows a form dialog with the WhisPaste glass barrier.
///
/// Use for dialogs that contain form fields (text inputs, dropdowns, etc.)
/// rather than simple confirmations. The [builder] receives the [Animation]
/// for coordinating entrance/exit transitions.
Future<T?> showWpFormDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, Animation<double> animation)
  builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
    pageBuilder: (_, a2, a3) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return _WpDialogBarrier(
        animation: animation,
        child: builder(ctx, animation),
      );
    },
  );
}

// ---------------------------------------------------------------------------

class _WpDialogBarrier extends StatelessWidget {
  const _WpDialogBarrier({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(parent: animation, curve: Curves.easeOut);

    // On Windows frameless windows, BackdropFilter + ImageFilter.blur is
    // broken, so fall back to a solid semi-transparent overlay.
    final bool useBlur = !Platform.isWindows;

    final barrierColor = WpColors.background.withValues(alpha: 0.92);

    return FadeTransition(
      opacity: opacity,
      child: Stack(
        children: [
          // Barrier layer
          Positioned.fill(
            child: useBlur
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: ColoredBox(color: wpDialogBarrierColor()),
                  )
                : ColoredBox(color: barrierColor),
          ),
          // Dialog
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog surface — the one card every WhisPaste dialog is built on
// ---------------------------------------------------------------------------

/// The card behind every dialog in the app: pre-composited frost
/// ([WpColors.floatingSurface]), [WpRadius.borderLg], the tinted
/// [WpColors.cardEdgeHighlight] rim, [WpShadows.elevated] — plus the two
/// behaviours every dialog wants and none should re-derive:
///
/// * It grows softly. An [AnimatedContainer] alone cannot animate an intrinsic
///   height change, so the body sits in an [AnimatedSize] — a dialog whose
///   content changes (a form gaining a row, a progress label rewrapping)
///   eases into its new height instead of jumping.
/// * It never runs off screen. Width and height are clamped to the viewport,
///   which is what keeps dialogs whole at large system text sizes; the
///   scrollable body lives in [child] via a [Flexible].
class _WpDialogSurface extends StatelessWidget {
  const _WpDialogSurface({
    required this.animation,
    required this.child,
    this.size = WpDialogSize.standard,
  });

  final Animation<double> animation;
  final Widget child;
  final WpDialogSize size;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final viewport = MediaQuery.sizeOf(context);
    // Leave a gutter so the card never touches the window edge, and never
    // demand more than the window offers.
    final requested = switch (size) {
      WpDialogSize.standard => _kDialogWidth,
      WpDialogSize.wide => _kWideDialogWidth,
    };
    final width = math.max(
      0.0,
      math.min(requested, viewport.width - WpSpacing.xl * 2),
    );
    final maxHeight = math.max(0.0, viewport.height - WpSpacing.xl * 2);

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: WpMotion.durationFor(context, WpMotion.fast),
            curve: WpMotion.defaultCurve,
            width: width,
            constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
            padding: const EdgeInsets.all(WpSpacing.lg),
            decoration: BoxDecoration(
              // Card material, pre-composited: a dialog floats over a
              // 92 %-opaque barrier, so a translucent frost would tint the
              // barrier rather than the ambient and vanish. See
              // `WpColors.floatingSurface` for the derivation. The rim is the
              // tinted `cardEdgeHighlight`, not a neutral white hairline —
              // same edge every card in the app carries.
              color: WpColors.floatingSurface,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: WpColors.cardEdgeHighlight),
              // The one sanctioned shadow family: this really does float.
              boxShadow: WpShadows.elevated,
            ),
            child: WpAnimatedSize(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog container — card with slide-up + fade animation
// ---------------------------------------------------------------------------

class _WpDialogContainer extends StatelessWidget {
  const _WpDialogContainer({
    required this.animation,
    required this.title,
    required this.content,
    this.actions,
  });

  final Animation<double> animation;
  final String title;
  final Widget content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _WpDialogSurface(
      animation: animation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: WpSpacing.sm),

          // Body — scrolls rather than overflowing once the card hits the
          // viewport ceiling (long content, large system text size).
          Flexible(child: SingleChildScrollView(child: content)),

          // Actions
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.lg),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form dialog shell — the body every form dialog wears
// ---------------------------------------------------------------------------

/// Standard body for a [showWpFormDialog] whose content is a form.
///
/// Carries the same card as every other dialog plus the two things a form
/// dialog needs on top of a plain one: an explanatory [subtitle] under the
/// title (a form asks for input, so it owes the user a sentence on what the
/// input does) and the soft growth of [_WpDialogSurface] for fields and rows
/// that appear as the user types.
class WpFormDialogShell extends StatelessWidget {
  const WpFormDialogShell({
    super.key,
    required this.animation,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.actions,
    this.size = WpDialogSize.standard,
  });

  final Animation<double> animation;
  final String title;

  /// How much room the card asks for — see [WpDialogSize].
  final WpDialogSize size;

  /// One sentence on what this form does. Required on purpose — the Snippets
  /// dialog shipped without one and read noticeably barer than its twin.
  final String subtitle;

  /// The form fields, laid out in a column.
  final List<Widget> fields;

  /// Trailing button row (cancel / submit).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _WpDialogSurface(
      animation: animation,
      size: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: WpColors.textMuted,
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: fields,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm content — self-contained dialog body with cancel / confirm buttons
// ---------------------------------------------------------------------------

class _WpConfirmContent extends StatelessWidget {
  const _WpConfirmContent({
    required this.animation,
    required this.title,
    required this.message,
    this.confirmLabel,
    this.cancelLabel,
    this.destructive = false,
  });

  final Animation<double> animation;
  final String title;
  final String message;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final resolvedCancel =
        cancelLabel ?? MaterialLocalizations.of(context).cancelButtonLabel;
    final resolvedConfirm =
        confirmLabel ?? MaterialLocalizations.of(context).okButtonLabel;

    return _WpDialogSurface(
      animation: animation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: WpSpacing.sm),
          Flexible(
            child: SingleChildScrollView(
              child: Text(message, style: theme.textTheme.bodyLarge),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              WpButton(
                label: resolvedCancel,
                variant: WpButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: WpSpacing.sm),
              WpButton(
                label: resolvedConfirm,
                variant: WpButtonVariant.primary,
                tone: destructive ? WpButtonTone.danger : WpButtonTone.accent,
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
