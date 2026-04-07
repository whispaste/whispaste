/// Command palette — Ctrl+K modal overlay for quick entry-scoped actions.
///
/// Frosted glass backdrop, fuzzy text search, keyboard navigation (↑/↓/Enter/Esc).
/// Animates in with fade + slide-up (300ms). Dark glass panel with accent selection.
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A single command entry in the palette.
class WpCommand {
  const WpCommand({
    required this.id,
    required this.label,
    required this.icon,
    this.shortcutHint,
    this.onExecute,
  });

  final String id;
  final String label;
  final IconData icon;

  /// Optional keyboard shortcut hint shown on the right (e.g. "Ctrl+C").
  final String? shortcutHint;

  /// Called when the command is selected (Enter or click).
  final VoidCallback? onExecute;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows the command palette as a modal overlay.
///
/// Returns the [WpCommand.id] of the executed command, or `null` if dismissed.
Future<String?> showWpCommandPalette({
  required BuildContext context,
  required List<WpCommand> commands,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: WpMotion.smooth,
    pageBuilder: (_, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, a2, child) {
      return _PaletteBarrier(
        animation: animation,
        child: _PaletteContent(
          animation: animation,
          commands: commands,
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Barrier — frosted glass (non-Windows) or solid overlay (Windows)
// ---------------------------------------------------------------------------

class _PaletteBarrier extends StatelessWidget {
  const _PaletteBarrier({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
    );
    final bool useBlur = !Platform.isWindows;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final barrierColor = isDark
        ? WpColorsDark.background.withValues(alpha: 0.92)
        : WpColorsLight.background.withValues(alpha: 0.88);

    return FadeTransition(
      opacity: opacity,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
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
          ),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Palette content — search box + filtered command list
// ---------------------------------------------------------------------------

class _PaletteContent extends StatefulWidget {
  const _PaletteContent({
    required this.animation,
    required this.commands,
  });

  final Animation<double> animation;
  final List<WpCommand> commands;

  @override
  State<_PaletteContent> createState() => _PaletteContentState();
}

class _PaletteContentState extends State<_PaletteContent> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  int _selectedIndex = 0;

  List<WpCommand> get _filtered {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return widget.commands;
    return widget.commands.where((c) => _fuzzyMatch(c.label, query)).toList();
  }

  /// Simple fuzzy match: all query characters appear in order in the label.
  static bool _fuzzyMatch(String label, String query) {
    final lower = label.toLowerCase();
    var qi = 0;
    for (var i = 0; i < lower.length && qi < query.length; i++) {
      if (lower[i] == query[qi]) qi++;
    }
    return qi == query.length;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Autofocus the search field after the frame renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _selectedIndex = 0;
    });
  }

  void _execute(WpCommand command) {
    Navigator.of(context).pop(command.id);
    command.onExecute?.call();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final filtered = _filtered;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty && _selectedIndex < filtered.length) {
        _execute(filtered[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, -0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOut,
    ));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    final panelBg = isDark
        ? WpColorsDark.surfaceElevated.withValues(alpha: 0.97)
        : WpColorsLight.surfaceElevated.withValues(alpha: 0.97);
    final borderColor =
        isDark ? WpColorsDark.borderDefault : WpColorsLight.borderDefault;
    final searchHint =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentSubtle =
        isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    final hoverColor = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    final dividerColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;

    return Align(
      alignment: const Alignment(0, -0.3),
      child: SlideTransition(
        position: slide,
        child: Focus(
          onKeyEvent: _handleKey,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 480,
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
              decoration: BoxDecoration(
                color: panelBg,
                borderRadius: WpRadius.borderLg,
                border: Border.all(color: borderColor),
                boxShadow: WpShadows.elevated,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Search input ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WpSpacing.md, WpSpacing.md, WpSpacing.md, 0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: TextStyle(color: textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: L10n.of(context).commandPaletteHint,
                        hintStyle: TextStyle(color: searchHint, fontSize: 14),
                        prefixIcon: Padding(
                          padding:
                              const EdgeInsets.only(left: 12, right: 8),
                          child: Icon(
                            LucideIcons.search,
                            size: WpIconSize.sm,
                            color: searchHint,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: WpSpacing.sm,
                        ),
                      ),
                    ),
                  ),

                  Divider(height: 1, color: dividerColor),

                  // ── Command list ──────────────────────────────────
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(WpSpacing.xl),
                      child: Text(
                        L10n.of(context).commandPaletteNoResults,
                        style: TextStyle(color: searchHint, fontSize: 13),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: WpSpacing.xs,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final cmd = filtered[index];
                          final isSelected = index == _selectedIndex;

                          return _CommandTile(
                            command: cmd,
                            isSelected: isSelected,
                            accent: accent,
                            accentSubtle: accentSubtle,
                            hoverColor: hoverColor,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            onTap: () => _execute(cmd),
                            onHover: () {
                              if (_selectedIndex != index) {
                                setState(() => _selectedIndex = index);
                              }
                            },
                          );
                        },
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

// ---------------------------------------------------------------------------
// Individual command row
// ---------------------------------------------------------------------------

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.command,
    required this.isSelected,
    required this.accent,
    required this.accentSubtle,
    required this.hoverColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
    required this.onHover,
  });

  final WpCommand command;
  final bool isSelected;
  final Color accent;
  final Color accentSubtle;
  final Color hoverColor;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          curve: WpMotion.defaultCurve,
          margin: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xs,
            vertical: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: isSelected ? accentSubtle : Colors.transparent,
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              Icon(
                command.icon,
                size: WpIconSize.sm,
                color: isSelected ? accent : textSecondary,
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Text(
                  command.label,
                  style: TextStyle(
                    color: isSelected ? textPrimary : textSecondary,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (command.shortcutHint != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.12)
                        : textSecondary.withValues(alpha: 0.1),
                    borderRadius: WpRadius.borderSm,
                  ),
                  child: Text(
                    command.shortcutHint!,
                    style: TextStyle(
                      color: isSelected ? accent : textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
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
