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
/// [actions] are placed left of the window controls (e.g. theme toggle).
class WpTitleBar extends StatelessWidget {
  const WpTitleBar({super.key, this.actions = const []});

  /// Widgets placed left of the window controls (minimize/maximize/close).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return _MacOSTitleBar(actions: actions);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.lg),
        child: Row(
          children: [
            // Brand wordmark PNG — prominent, gaming-launcher scale
            const WpBrandWordmark(height: 34),
            const Spacer(),
            // Custom actions (theme toggle, etc.)
            ...actions,
            if (actions.isNotEmpty) const SizedBox(width: WpSpacing.sm),
            // Window controls — all subtle gray, no red close
            // loam-ignore: a11y-interactive-semantics – semantics provided in _WindowButton.build
            _WindowButton(
              icon: LucideIcons.minus,
              onPressed: () => windowManager.minimize(),
              isDark: isDark,
              semanticLabel: 'Minimize window',
            ),
            _MaximizeButton(isDark: isDark),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _WindowButton.build
            _WindowButton(
              icon: LucideIcons.x,
              onPressed: () => windowManager.close(),
              isDark: isDark,
              semanticLabel: 'Close window',
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
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final String semanticLabel;

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

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: WpMotion.hoverIn,
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
          duration: WpMotion.hoverIn,
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

/// macOS title bar with drag support and traffic-light clearance.
///
/// The native traffic lights sit at ~14px inset. A 56px left padding
/// clears them plus a comfortable margin. No custom window controls
/// are rendered — macOS traffic lights handle minimize/maximize/close.
class _MacOSTitleBar extends StatelessWidget {
  const _MacOSTitleBar({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // Force LTR so the 56-px traffic-light clearance always sits on the
    // physical left, regardless of the app locale (e.g. Hebrew RTL).
    // The native macOS traffic lights are always top-left — they are not
    // affected by Flutter's Directionality — so the Row must stay LTR here.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () async {
          // macOS convention: double-tap title bar toggles zoom.
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        },
        child: SizedBox(
          height: WpLayout.appBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.lg),
            child: Row(
              children: [
                // Clear native traffic lights (~68px + margin).
                const SizedBox(width: 56),
                const WpBrandWordmark(height: 34),
                const Spacer(),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
