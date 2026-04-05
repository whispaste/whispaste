import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/tokens.dart';

/// Custom window title bar matching the premium design.
///
/// On Windows/Linux: drag area + app title + minimize/maximize/close buttons.
/// On macOS: transparent title bar (traffic lights handled natively).
class WpTitleBar extends StatelessWidget {
  const WpTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    // macOS uses native traffic lights — no custom title bar needed
    if (Platform.isMacOS) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

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
        color: cs.surface,
        child: Row(
          children: [
            const SizedBox(width: WpSpacing.md),
            // App brand icon
            Icon(Icons.mic_rounded, size: 18, color: cs.primary),
            const SizedBox(width: WpSpacing.xs),
            Text(
              'WhisPaste',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // Window controls
            _WindowButton(
              icon: Icons.remove,
              onPressed: () => windowManager.minimize(),
              hoverColor: cs.outlineVariant,
            ),
            _MaximizeButton(hoverColor: cs.outlineVariant),
            _WindowButton(
              icon: Icons.close,
              onPressed: () => windowManager.close(),
              hoverColor: const Color(0xFFE81123),
              hoverIconColor: Colors.white,
            ),
          ],
        ),
      ),
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
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          width: 46,
          height: WpLayout.appBarHeight,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 16,
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
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () async {
          if (_isMaximized) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
          if (mounted) {
            setState(() => _isMaximized = !_isMaximized);
          }
        },
        child: AnimatedContainer(
          duration: WpMotion.fast,
          width: 46,
          height: WpLayout.appBarHeight,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            size: 14,
            color: cs.secondary,
          ),
        ),
      ),
    );
  }
}
