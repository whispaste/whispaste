import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'brand_wordmark.dart';

/// Gaming-launcher–style title bar with brand wordmark PNG.
///
/// Seamless dark background, real brand wordmark image (theme-aware),
/// subtle window controls. No borders — flows into the content.
class WpTitleBar extends StatelessWidget {
  const WpTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: WpLayout.appBarHeight,
        decoration: BoxDecoration(
          gradient: isDark ? WpColorsDark.frameGradient : null,
          color: isDark ? null : WpColorsLight.background,
        ),
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.lg),
        child: Row(
          children: [
            // Brand wordmark PNG — prominent, gaming-launcher scale
            const WpBrandWordmark(height: 34),
            const Spacer(),
            // Window controls — all subtle gray, no red close
            _WindowButton(
              icon: LucideIcons.minus,
              onPressed: () => windowManager.minimize(),
              isDark: isDark,
            ),
            _MaximizeButton(isDark: isDark),
            _WindowButton(
              icon: LucideIcons.x,
              onPressed: () => windowManager.close(),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle window control button — muted by default, visible on hover.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final mutedColor = widget.isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;
    final hoverBg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
    final hoverFg = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          width: 40,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? hoverBg
                : (widget.isDark
                    ? WpColorsDark.hoverTransparent
                    : WpColorsLight.hoverTransparent),
            borderRadius: BorderRadius.circular(WpRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 15,
            color: _isHovered ? hoverFg : mutedColor,
          ),
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  const _MaximizeButton({required this.isDark});

  final bool isDark;

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  bool _isHovered = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = widget.isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;
    final hoverBg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
    final hoverFg = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () async {
          if (_isMaximized) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
          if (mounted) setState(() => _isMaximized = !_isMaximized);
        },
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          width: 40,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? hoverBg
                : (widget.isDark
                    ? WpColorsDark.hoverTransparent
                    : WpColorsLight.hoverTransparent),
            borderRadius: BorderRadius.circular(WpRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(
            _isMaximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
            size: 14,
            color: _isHovered ? hoverFg : mutedColor,
          ),
        ),
      ),
    );
  }
}
