/// Compact inline tag editor — Notion-style.
///
/// Tags display as removable accent-tinted pills in a single Wrap row.
/// An inline text field sits among the chips for immediate typing.
/// Supports comma-separated entry, Enter to confirm, Backspace to
/// remove last tag, and "+N more" collapse when many tags exist.
library;

import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/data/database.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Maximum tags shown when not in add mode.
const _kMaxVisibleTags = 5;

class WpTagInput extends StatefulWidget {
  const WpTagInput({
    super.key,
    required this.tags,
    required this.isDark,
    required this.onAdd,
    required this.onRemove,
    this.suggestions = const [],
    this.suggestionCounts = const {},
    this.onSearchChanged,
    this.hintText = 'Add tag…',
    this.searchHintText = 'Search or create…',
  });

  final List<Tag> tags;
  final bool isDark;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove; // tagId
  final List<Tag> suggestions;
  final Map<String, int> suggestionCounts;
  final ValueChanged<String>? onSearchChanged;
  final String hintText;
  final String searchHintText;

  @override
  State<WpTagInput> createState() => WpTagInputState();
}

class WpTagInputState extends State<WpTagInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isAddMode = false;

  /// Called externally (clickable header, etc.) to enter add mode.
  void enterAddMode() {
    if (_isAddMode) {
      _focusNode.requestFocus();
      return;
    }
    setState(() => _isAddMode = true);
    widget.onSearchChanged?.call('');
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final trimmed = text.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    if (widget.tags.any((t) => t.name == trimmed)) {
      _controller.clear();
      return;
    }
    widget.onAdd(trimmed);
    _controller.clear();
    widget.onSearchChanged?.call('');
    _focusNode.requestFocus(); // Keep add mode open (consistent with suggestion tap)
  }

  void _selectSuggestion(Tag tag) {
    if (widget.tags.any((t) => t.id == tag.id)) return;
    widget.onAdd(tag.name);
    _controller.clear();
    widget.onSearchChanged?.call('');
    _focusNode.requestFocus();
  }

  void _handleInputChanged(String value) {
    // Comma-separated tag entry: split, submit each, clear.
    if (value.contains(',')) {
      for (final part in value.split(',')) {
        final trimmed = part.trim().toLowerCase();
        if (trimmed.isNotEmpty &&
            !widget.tags.any((t) => t.name == trimmed)) {
          widget.onAdd(trimmed);
        }
      }
      _controller.clear();
      widget.onSearchChanged?.call('');
      _focusNode.requestFocus();
      setState(() {});
      return;
    }
    widget.onSearchChanged?.call(value.trim());
    setState(() {});
  }

  void _closeAddMode() {
    setState(() => _isAddMode = false);
    _controller.clear();
    widget.onSearchChanged?.call('');
    _focusNode.unfocus();
  }

  List<Tag> get _filteredSuggestions {
    final query = _controller.text.trim().toLowerCase();
    final existingIds = widget.tags.map((t) => t.id).toSet();
    return widget.suggestions
        .where((t) => !existingIds.contains(t.id))
        .where((t) => query.isEmpty || t.name.contains(query))
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = widget.isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;
    final surfaceEl = widget.isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderCol = widget.isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    // Collapse tags when not editing.
    final visibleTags = _isAddMode
        ? widget.tags
        : widget.tags.take(_kMaxVisibleTags).toList();
    final hiddenCount =
        _isAddMode ? 0 : max(0, widget.tags.length - _kMaxVisibleTags);

    return TapRegion(
      onTapOutside: _isAddMode ? (_) => _closeAddMode() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Unified tag row: chips + inline input / trigger ──
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in visibleTags)
                _TagChip(
                  tag: tag,
                  isDark: widget.isDark,
                  onRemove: () => widget.onRemove(tag.id),
                ),
              if (hiddenCount > 0)
                _OverflowChip(
                  count: hiddenCount,
                  isDark: widget.isDark,
                  onTap: enterAddMode,
                ),
              if (_isAddMode)
                _buildInlineField(
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  accent: accent,
                  borderCol: borderCol,
                )
              else
                _AddTagTrigger(
                  isDark: widget.isDark,
                  label: widget.tags.isEmpty ? widget.hintText : null,
                  onTap: enterAddMode,
                ),
            ],
          ),

          // ── Suggestions dropdown ──
          if (_isAddMode && _filteredSuggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xxs),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: surfaceEl,
                  borderRadius: WpRadius.borderSm,
                  border: Border.all(color: borderCol),
                  boxShadow: WpShadows.card,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding:
                      const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
                  itemCount: _filteredSuggestions.length,
                  itemBuilder: (_, i) {
                    final tag = _filteredSuggestions[i];
                    return _SuggestionTile(
                      tag: tag,
                      isDark: widget.isDark,
                      count: widget.suggestionCounts[tag.id],
                      onTap: () => _selectSuggestion(tag),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Inline text field — sits at the end of the tag Wrap.
  Widget _buildInlineField({
    required Color textPrimary,
    required Color textMuted,
    required Color accent,
    required Color borderCol,
  }) {
    return SizedBox(
      width: 140,
      height: 30,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _closeAddMode();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.backspace &&
                _controller.text.isEmpty &&
                widget.tags.isNotEmpty) {
              widget.onRemove(widget.tags.last.id);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: widget.searchHintText,
            hintStyle: TextStyle(fontSize: 12, color: textMuted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: WpSpacing.xxs,
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: borderCol),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: borderCol),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
          onChanged: _handleInputChanged,
          onSubmitted: _submit,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tag chip — clean accent-tinted pill (no # prefix)
// ---------------------------------------------------------------------------

class _TagChip extends StatefulWidget {
  const _TagChip({
    required this.tag,
    required this.isDark,
    required this.onRemove,
  });

  final Tag tag;
  final bool isDark;
  final VoidCallback onRemove;

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: WpMotion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs + 2,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: _isHovered ? 0.18 : 0.10),
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.tag.name,
              style: TextStyle(
                fontSize: 13,
                color: accent.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: WpSpacing.xxs),
            Semantics(
              button: true,
              label: 'Remove ${widget.tag.name}',
              child: GestureDetector(
                onTap: widget.onRemove,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AnimatedOpacity(
                    opacity: _isHovered ? 0.9 : 0.35,
                    duration:
                        _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
                    child: Icon(
                      LucideIcons.x,
                      size: WpIconSize.xs,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "+N" overflow chip — taps to reveal all tags
// ---------------------------------------------------------------------------

class _OverflowChip extends StatelessWidget {
  const _OverflowChip({
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  final int count;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Semantics(
      button: true,
      label: '+$count more tags',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            borderRadius: WpRadius.borderFull,
            border: Border.all(
              color: textMuted.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            '+$count',
            style: TextStyle(
              fontSize: 12,
              color: textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact add trigger — "+" icon with optional label
// ---------------------------------------------------------------------------

class _AddTagTrigger extends StatefulWidget {
  const _AddTagTrigger({
    required this.isDark,
    required this.onTap,
    this.label,
  });

  final bool isDark;
  final VoidCallback onTap;
  final String? label;

  @override
  State<_AddTagTrigger> createState() => _AddTagTriggerState();
}

class _AddTagTriggerState extends State<_AddTagTrigger> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Semantics(
      button: true,
      label: widget.label ?? 'Add tag',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: _isHovered ? 0.08 : 0.0),
              borderRadius: WpRadius.borderFull,
              border: Border.all(
                color: accent.withValues(alpha: _isHovered ? 0.4 : 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.plus,
                  size: WpIconSize.xs,
                  color: accent.withValues(alpha: _isHovered ? 0.7 : 0.4),
                ),
                if (widget.label != null) ...[
                  const SizedBox(width: WpSpacing.xxs),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: 12,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suggestion tile
// ---------------------------------------------------------------------------

class _SuggestionTile extends StatefulWidget {
  const _SuggestionTile({
    required this.tag,
    required this.isDark,
    required this.onTap,
    this.count,
  });

  final Tag tag;
  final bool isDark;
  final VoidCallback onTap;
  final int? count;

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final hoverBg =
        widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.sm,
          ),
          color: _isHovered ? hoverBg : Colors.transparent,
          child: Row(
            children: [
              Icon(
                LucideIcons.hash,
                size: WpIconSize.sm,
                color: accent.withValues(alpha: 0.6),
              ),
              const SizedBox(width: WpSpacing.xs),
              Expanded(
                child: Text(
                  widget.tag.name,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                ),
              ),
              if (widget.count != null && widget.count! > 0)
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 12,
                    color: textPrimary.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
