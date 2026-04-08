import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Lightweight markdown formatting toolbar for text editing.
///
/// Provides inline formatting (bold, italic, bullet list, heading)
/// and integrates with a [TextEditingController] to wrap/prefix
/// selected text or insert at cursor.
class WpMarkdownToolbar extends StatelessWidget {
  const WpMarkdownToolbar({
    super.key,
    required this.controller,
    required this.isDark,
    required this.focusNode,
  });

  final TextEditingController controller;
  final bool isDark;
  final FocusNode focusNode;

  void _wrapSelection(String prefix, [String? suffix]) {
    suffix ??= prefix;
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid) return;

    final before = text.substring(0, sel.start);
    final selected = text.substring(sel.start, sel.end);
    final after = text.substring(sel.end);

    // If already wrapped, unwrap
    if (selected.startsWith(prefix) && selected.endsWith(suffix)) {
      final unwrapped =
          selected.substring(prefix.length, selected.length - suffix.length);
      controller.value = TextEditingValue(
        text: '$before$unwrapped$after',
        selection: TextSelection(
          baseOffset: sel.start,
          extentOffset: sel.start + unwrapped.length,
        ),
      );
    } else {
      final wrapped = '$prefix$selected$suffix';
      controller.value = TextEditingValue(
        text: '$before$wrapped$after',
        selection: TextSelection(
          baseOffset: sel.start,
          extentOffset: sel.start + wrapped.length,
        ),
      );
    }

    focusNode.requestFocus();
  }

  void _toggleLinePrefix(String prefix) {
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid) return;

    // Find the start of the current line
    final lineStart = text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0);
    final actualStart = lineStart == -1 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', sel.end);
    final actualEnd = lineEnd == -1 ? text.length : lineEnd;

    final lines = text.substring(actualStart, actualEnd).split('\n');
    final allPrefixed = lines.every((l) => l.startsWith(prefix));

    final transformed = lines.map((l) {
      if (allPrefixed) {
        return l.startsWith(prefix) ? l.substring(prefix.length) : l;
      }
      return l.startsWith(prefix) ? l : '$prefix$l';
    }).join('\n');

    final before = text.substring(0, actualStart);
    final after = text.substring(actualEnd);

    final diff = transformed.length - (actualEnd - actualStart);
    controller.value = TextEditingValue(
      text: '$before$transformed$after',
      selection: TextSelection(
        baseOffset: sel.start + (sel.start > actualStart ? diff : 0),
        extentOffset: sel.end + diff,
      ),
    );

    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final divColor = mutedColor.withValues(alpha: 0.2);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.6),
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarButton(
            icon: LucideIcons.bold,
            tooltip: 'Bold (Ctrl+B)',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _wrapSelection('**'),
          ),
          _ToolbarButton(
            icon: LucideIcons.italic,
            tooltip: 'Italic (Ctrl+I)',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _wrapSelection('_'),
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
            color: divColor,
          ),
          _ToolbarButton(
            icon: LucideIcons.heading,
            tooltip: 'Heading',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _toggleLinePrefix('## '),
          ),
          _ToolbarButton(
            icon: LucideIcons.list,
            tooltip: 'Bullet list (Ctrl+Shift+L)',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _toggleLinePrefix('- '),
          ),
          _ToolbarButton(
            icon: LucideIcons.listOrdered,
            tooltip: 'Numbered list',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _toggleLinePrefix('1. '),
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
            color: divColor,
          ),
          _ToolbarButton(
            icon: LucideIcons.quote,
            tooltip: 'Quote',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _toggleLinePrefix('> '),
          ),
          _ToolbarButton(
            icon: LucideIcons.code,
            tooltip: 'Code',
            isDark: isDark,
            accent: accent,
            muted: mutedColor,
            onTap: () => _wrapSelection('`'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: WpMotion.hoverOut,
            padding: const EdgeInsets.all(WpSpacing.xs),
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: WpRadius.borderSm,
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered ? widget.accent : widget.muted,
            ),
          ),
        ),
      ),
    );
  }
}
