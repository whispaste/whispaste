import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Clearance for the native macOS traffic lights (about 14 px in, ~70 px wide).
const double _macTrafficLightClearance = 80;

/// Window title bar of the app shell (chat-08): one row across the whole frame.
///
/// It stands on the window frame gradient and carries only the window title
/// ("WhisPaste", centred) and, on Windows and Linux, the window controls. The
/// brand lock-up lives in the sidebar, not here. On macOS the native traffic
/// lights sit in the clearance at the reading start; that row is forced to LTR
/// so the clearance always lands on the physical left, also in Hebrew. The whole
/// bar is a drag area, double-tap zooms or restores.
class WpTitleBar extends StatelessWidget {
  const WpTitleBar({super.key, this.actions = const []});

  /// Widgets placed left of the window controls (minimize/maximize/close).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    final l10n = L10n.of(context);
    final titleStyle = Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(color: WpColors.frame.textSecondary);

    final row = Row(
      children: [
        if (isMac) const SizedBox(width: _macTrafficLightClearance),
        Expanded(
          child: Center(
            child: Text(
              'WhisPaste',
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ...actions,
        if (!isMac) ...[
          // loam-ignore: a11y-interactive-semantics – semantics provided in _WindowButton.build
          _WindowButton(
            icon: LucideIcons.minus,
            onPressed: () => windowManager.minimize(),
            semanticLabel: l10n.titleBarMinimizeLabel,
          ),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _MaximizeButton.build
          const _MaximizeButton(),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _WindowButton.build
          _WindowButton(
            icon: LucideIcons.x,
            onPressed: () => windowManager.close(),
            semanticLabel: l10n.titleBarCloseLabel,
          ),
        ],
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        // macOS convention: double-tap the title bar to zoom.
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: SizedBox(
        height: WpLayout.appBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
          // On Windows and Linux the row follows the text direction on
          // purpose: a right-to-left window there mirrors its caption buttons
          // to the left, as Windows and GNOME do for RTL apps (UIA-VIS-03).
          child: isMac
              ? Directionality(textDirection: TextDirection.ltr, child: row)
              : row,
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
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'WindowButton');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = WpColors.frame.textMuted;
    final hoverBg = WpColors.frame.hover;
    final hoverFg = WpColors.frame.textSecondary;

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: widget.onPressed,
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(WpRadius.sm),
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.hoverIn),
              curve: WpMotion.defaultCurve,
              width: 40,
              height: 32,
              decoration: BoxDecoration(
                color: _isHovered || _focusNode.hasFocus
                    ? hoverBg
                    : WpColors.frame.hoverTransparent,
                borderRadius: BorderRadius.circular(WpRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: WpIconSize.sm,
                color: _isHovered || _focusNode.hasFocus ? hoverFg : mutedColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  const _MaximizeButton();

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  bool _isHovered = false;
  bool _isMaximized = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MaximizeButton');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = WpColors.frame.textMuted;
    final hoverBg = WpColors.frame.hover;
    final hoverFg = WpColors.frame.textSecondary;

    final l10n = L10n.of(context);
    return Semantics(
      label: _isMaximized
          ? l10n.titleBarRestoreLabel
          : l10n.titleBarMaximizeLabel,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
              if (mounted) setState(() => _isMaximized = !_isMaximized);
            },
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(WpRadius.sm),
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.hoverIn),
              curve: WpMotion.defaultCurve,
              width: 40,
              height: 32,
              decoration: BoxDecoration(
                color: _isHovered || _focusNode.hasFocus
                    ? hoverBg
                    : WpColors.frame.hoverTransparent,
                borderRadius: BorderRadius.circular(WpRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                _isMaximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
                size: WpIconSize.xs,
                color: _isHovered || _focusNode.hasFocus ? hoverFg : mutedColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
