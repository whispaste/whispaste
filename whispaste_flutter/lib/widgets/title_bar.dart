import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'brand_logo.dart';

/// Gaming-dashboard–style title bar with brand wordmark.
///
/// Inspired by Steam/Dixper: seamless dark background, bold wordmark,
/// subtle window controls. The bar flows into the content — no separator.
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
        // Seamless — same background as the app, no border
        color: isDark ? WpColorsDark.background : WpColorsLight.background,
        child: Row(
          children: [
            const SizedBox(width: WpSpacing.md),
            // Brand logo icon — bold, accent-colored
            const WpBrandLogo(size: 26),
            const SizedBox(width: WpSpacing.sm),
            // Dual-color wordmark: "Whis" light + "paste" accent
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Whis',
                    style: TextStyle(
                      color: isDark
                          ? WpColorsDark.textPrimary
                          : WpColorsLight.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  TextSpan(
                    text: 'paste',
                    style: TextStyle(
                      color: isDark
                          ? WpColorsDark.accent
                          : WpColorsLight.accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Window controls — compact, subtle, gaming-style
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
              isClose: true,
            ),
            const SizedBox(width: WpSpacing.xxs),
          ],
        ),
      ),
    );
  }
}

/// Compact window control button — muted by default, visible on hover.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.isDark,
    this.isClose = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final bool isClose;

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
    final hoverBg = widget.isClose
        ? const Color(0xFFE81123)
        : (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover);
    final hoverFg = widget.isClose
        ? Colors.white
        : (widget.isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          width: 40,
          height: 30,
          decoration: BoxDecoration(
            color: _isHovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(WpRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 14,
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
          duration: WpMotion.fast,
          width: 40,
          height: 30,
          decoration: BoxDecoration(
            color: _isHovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(WpRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(
            _isMaximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
            size: 13,
            color: _isHovered ? hoverFg : mutedColor,
          ),
        ),
      ),
    );
  }
}
