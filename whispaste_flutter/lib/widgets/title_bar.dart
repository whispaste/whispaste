import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'brand_logo.dart';

/// Premium custom window title bar.
///
/// Features the real WhisPaste brand logo, a thin accent gradient stripe,
/// and refined window controls. macOS uses native traffic lights.
class WpTitleBar extends StatelessWidget {
  const WpTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Thin accent gradient stripe at very top
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: isDark
                ? WpColorsDark.accentGradient
                : WpColorsLight.accentGradient,
          ),
        ),
        // Title bar body
        GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          child: Container(
            height: WpLayout.appBarHeight - 2,
            decoration: BoxDecoration(
              color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? WpColorsDark.borderSubtle
                      : WpColorsLight.borderSubtle,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: WpSpacing.sm),
                // Brand logo — crisp, real asset
                const WpBrandLogo(size: 20),
                const SizedBox(width: WpSpacing.xs),
                // App name
                Text(
                  'WhisPaste',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: WpSpacing.xxs),
                // Version badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: WpRadius.borderFull,
                  ),
                  child: Text(
                    'v1.2',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const Spacer(),
                // Window controls
                _WindowButton(
                  icon: LucideIcons.minus,
                  onPressed: () => windowManager.minimize(),
                  hoverColor: isDark ? WpColorsDark.hover : WpColorsLight.hover,
                ),
                _MaximizeButton(
                  hoverColor: isDark ? WpColorsDark.hover : WpColorsLight.hover,
                ),
                _WindowButton(
                  icon: LucideIcons.x,
                  onPressed: () => windowManager.close(),
                  hoverColor: const Color(0xFFE81123),
                  hoverIconColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    this.hoverIconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color? hoverIconColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          width: 46,
          height: WpLayout.appBarHeight - 2,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: WpIconSize.sm,
            color: _isHovered && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : cs.secondary,
          ),
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  const _MaximizeButton({required this.hoverColor});

  final Color hoverColor;

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
    final cs = Theme.of(context).colorScheme;

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
          width: 46,
          height: WpLayout.appBarHeight - 2,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            _isMaximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
            size: WpIconSize.xs,
            color: cs.secondary,
          ),
        ),
      ),
    );
  }
}
