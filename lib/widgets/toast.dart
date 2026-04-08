/// Premium toast notification widget — slides in from the bottom-right with
/// themed styling, icon, and smooth animation. Replaces default SnackBars.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Toast severity levels — controls icon, color, and animation style.
enum WpToastType { success, error, info, warning }

/// Show a premium toast notification.
///
/// Usage:
/// ```dart
/// WpToast.show(context, message: 'Copied!', type: WpToastType.success);
/// ```
class WpToast {
  WpToast._();

  static final _log = AppLogger('Toast');

  static void show(
    BuildContext context, {
    required String message,
    WpToastType type = WpToastType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Route toast messages through the logging pipeline so they appear
    // in the `flutter run` terminal in debug mode.
    switch (type) {
      case WpToastType.error:
        _log.error('TOAST: $message');
      case WpToastType.warning:
        _log.warning('TOAST: $message');
      case WpToastType.success:
        _log.info('TOAST: $message');
      case WpToastType.info:
        _log.info('TOAST: $message');
    }

    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    late final AnimationController controller;

    controller = AnimationController(
      vsync: overlay,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );

    entry = OverlayEntry(
      builder: (context) => _WpToastOverlay(
        message: message,
        type: type,
        animation: controller,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: () {
          controller.reverse().then((_) {
            entry.remove();
            controller.dispose();
          });
        },
      ),
    );

    overlay.insert(entry);
    controller.forward();

    // Auto-dismiss after duration
    Future.delayed(duration, () {
      if (controller.isAnimating || controller.isCompleted) {
        controller.reverse().then((_) {
          if (entry.mounted) entry.remove();
          controller.dispose();
        });
      }
    });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 56,
      right: WpSpacing.lg,
      left: null,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1.5),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        )),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: _ToastCard(
            message: message,
            type: type,
            isDark: isDark,
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
    required this.isDark,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final WpToastType type;
  final bool isDark;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  (IconData, Color) _iconAndColor() {
    return switch (type) {
      WpToastType.success => (
          LucideIcons.circleCheck,
          isDark ? WpColorsDark.success : WpColorsLight.success,
        ),
      WpToastType.error => (
          LucideIcons.circleAlert,
          isDark ? WpColorsDark.error : WpColorsLight.error,
        ),
      WpToastType.warning => (
          LucideIcons.triangleAlert,
          isDark ? WpColorsDark.warning : WpColorsLight.warning,
        ),
      WpToastType.info => (
          LucideIcons.info,
          isDark ? WpColorsDark.accent : WpColorsLight.accent,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconAndColor();
    final surfaceBg = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final borderColor =
        isDark ? WpColorsDark.borderDefault : WpColorsLight.borderDefault;

    return Material(
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
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
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
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Action button (optional)
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: WpSpacing.sm),
                TextButton(
                  onPressed: () {
                    onAction!();
                    onDismiss();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.sm,
                      vertical: WpSpacing.xs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
              const SizedBox(width: WpSpacing.xs),
              // Close button
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(WpRadius.full),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: isDark
                        ? WpColorsDark.textMuted
                        : WpColorsLight.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
