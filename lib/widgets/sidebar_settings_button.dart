/// Settings shortcut button pinned to the sidebar bottom.
///
/// Mirrors the visual style of regular [WpSidebar] items — icon-only at 72 px
/// width with active-indicator bar, hover highlight, and accent tint.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Sidebar settings gear — pinned to the bottom of the nav rail.
class WpSidebarSettingsButton extends StatefulWidget {
  const WpSidebarSettingsButton({
    super.key,
    required this.isActive,
    required this.onTap,
  });

  final bool isActive;
  final VoidCallback onTap;

  @override
  State<WpSidebarSettingsButton> createState() =>
      _WpSidebarSettingsButtonState();
}

class _WpSidebarSettingsButtonState extends State<WpSidebarSettingsButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final Color iconColor;
    final Color bgColor;

    if (widget.isActive) {
      iconColor = isDark ? WpColorsDark.accent : WpColorsLight.accent;
      bgColor = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      iconColor = isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
      bgColor = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      iconColor = isDark ? WpColorsDark.textSecondary : WpColorsLight.textMuted;
      bgColor = isDark
          ? WpColorsDark.hoverTransparent
          : WpColorsLight.hoverTransparent;
    }

    return Semantics(
      label: l10n.navSettings,
      button: true,
      selected: widget.isActive,
      child: Tooltip(
        message: l10n.navSettings,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              width: WpLayout.sidebarWidth,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.isActive)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          gradient: isDark
                              ? WpColorsDark.accentWarmGradient
                              : WpColorsLight.accentWarmGradient,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(WpRadius.sm),
                            bottomRight: Radius.circular(WpRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  AnimatedContainer(
                    duration: WpMotion.hoverIn,
                    curve: WpMotion.defaultCurve,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(WpRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.settings,
                      color: iconColor,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
