/// Reusable WhisPaste dialog with frosted glass backdrop.
///
/// Use [showWpDialog] convenience function for standard dialogs.
/// Use [showWpConfirmDialog] for yes/no confirmations.
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows a WhisPaste-styled dialog.
///
/// [title] is rendered as `titleLarge`. [content] is the body widget.
/// Provide [actions] for custom button rows; otherwise no buttons are shown.
Future<T?> showWpDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // painted by the transition builder
    transitionDuration: WpMotion.smooth,
    pageBuilder: (_, a2, a3) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return _WpDialogBarrier(
        animation: animation,
        child: _WpDialogContainer(
          animation: animation,
          title: title,
          content: content,
          actions: actions,
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
    transitionDuration: WpMotion.smooth,
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
    transitionDuration: WpMotion.smooth,
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
    final opacity = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
    );

    // On Windows frameless windows, BackdropFilter + ImageFilter.blur is
    // broken, so fall back to a solid semi-transparent overlay.
    final bool useBlur = !Platform.isWindows;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final barrierColor = isDark
        ? WpColorsDark.background.withValues(alpha: 0.92)
        : WpColorsLight.background.withValues(alpha: 0.88);

    return FadeTransition(
      opacity: opacity,
      child: Stack(
        children: [
          // Barrier layer
          Positioned.fill(
            child: useBlur
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: ColoredBox(
                      color: (isDark
                              ? const Color(0xFF000000)
                              : const Color(0xFFFFFFFF))
                          .withValues(alpha: isDark ? 0.45 : 0.35),
                    ),
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
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 420,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(WpSpacing.lg),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.surfaceElevated
                  : WpColorsLight.surfaceElevated,
              borderRadius: WpRadius.borderLg,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderSubtle
                    : WpColorsLight.borderSubtle,
              ),
              boxShadow: WpShadows.elevated,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: WpSpacing.sm),

                // Body
                content,

                // Actions
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(height: WpSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
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
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final confirmColor =
        destructive ? colorScheme.error : colorScheme.primary;
    final confirmFg =
        destructive ? colorScheme.onError : colorScheme.onPrimary;

    final resolvedCancel =
        cancelLabel ?? MaterialLocalizations.of(context).cancelButtonLabel;
    final resolvedConfirm = confirmLabel ??
        MaterialLocalizations.of(context).okButtonLabel;

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 420,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(WpSpacing.lg),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.surfaceElevated
                  : WpColorsLight.surfaceElevated,
              borderRadius: WpRadius.borderLg,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderSubtle
                    : WpColorsLight.borderSubtle,
              ),
              boxShadow: WpShadows.elevated,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: WpSpacing.sm),
                Text(message, style: theme.textTheme.bodyLarge),
                const SizedBox(height: WpSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(resolvedCancel),
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: confirmFg,
                      ),
                      child: Text(resolvedConfirm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
