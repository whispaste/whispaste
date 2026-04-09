/// Compact inline tag editor — Notion-style.
///
/// Tags display as removable accent-tinted pills in a single Wrap row.
/// An inline text field sits among the chips for immediate typing.
/// Supports comma-separated entry, Enter to confirm, Backspace to
/// remove last tag, and "+N more" collapse when many tags exist.
/// A "Create" row appears when the typed text is novel.
library;

import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/data/database.dart';
import '../core/l10n/generated/app_localizations.dart';
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

  /// Index into the combined dropdown list (suggestions + optional "Create").
  /// -1 means no selection (typed text will be used as-is on Enter).
  int _selectedIndex = -1;

  /// Called externally (clickable header, etc.) to enter add mode.
  void enterAddMode() {
    if (_isAddMode) {
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      _isAddMode = true;
      _selectedIndex = -1;
    });
    widget.onSearchChanged?.call('');
  }

  /// Also callable externally — used by focusTagInput() alias.
  void focusTagInput() => enterAddMode();

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
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
    setState(() => _selectedIndex = -1);
    _focusNode.requestFocus();
  }

  void _selectSuggestion(Tag tag) {
    if (widget.tags.any((t) => t.id == tag.id)) return;
    widget.onAdd(tag.name);
    _controller.clear();
    widget.onSearchChanged?.call('');
    setState(() => _selectedIndex = -1);
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
      setState(() => _selectedIndex = -1);
      return;
    }
    widget.onSearchChanged?.call(value.trim());
    // Reset selection when input changes — suggestions will differ.
    setState(() => _selectedIndex = -1);
  }

  void _closeAddMode() {
    setState(() {
      _isAddMode = false;
      _selectedIndex = -1;
    });
    _controller.clear();
    widget.onSearchChanged?.call('');
    _focusNode.unfocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final suggestions = _filteredSuggestions;
    final showCreate = _isAddMode && _canCreateNewTag;
    final totalItems = suggestions.length + (showCreate ? 1 : 0);

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _closeAddMode();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.backspace:
        if (_controller.text.isEmpty && widget.tags.isNotEmpty) {
          widget.onRemove(widget.tags.last.id);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowDown:
        if (totalItems > 0) {
          setState(() {
            _selectedIndex = (_selectedIndex + 1).clamp(0, totalItems - 1);
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowUp:
        if (totalItems > 0) {
          setState(() {
            _selectedIndex = (_selectedIndex - 1).clamp(-1, totalItems - 1);
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (_selectedIndex >= 0 && _selectedIndex < suggestions.length) {
          _selectSuggestion(suggestions[_selectedIndex]);
        } else if (_selectedIndex == suggestions.length && showCreate) {
          _submit(_controller.text);
        } else if (_controller.text.trim().isNotEmpty) {
          // No dropdown selection — check for exact match, else create.
          final query = _controller.text.trim().toLowerCase();
          final exact =
              suggestions.where((s) => s.name == query).firstOrNull;
          if (exact != null) {
            _selectSuggestion(exact);
          } else {
            _submit(_controller.text);
          }
        }
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
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

  /// Whether the current input text is a novel tag (not matching any existing
  /// suggestion and not already assigned).
  bool get _canCreateNewTag {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return false;
    if (widget.tags.any((t) => t.name == query)) return false;
    // Check if any suggestion matches exactly.
    if (widget.suggestions.any((t) => t.name == query)) return false;
    return true;
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
    final l10n = L10n.of(context);

    // Collapse tags when not editing.
    final visibleTags = _isAddMode
        ? widget.tags
        : widget.tags.take(_kMaxVisibleTags).toList();
    final hiddenCount =
        _isAddMode ? 0 : max(0, widget.tags.length - _kMaxVisibleTags);

    final suggestions = _filteredSuggestions;
    final showCreate = _isAddMode && _canCreateNewTag;
    final showDropdown = _isAddMode && (suggestions.isNotEmpty || showCreate);

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

          // ── Suggestions + Create dropdown ──
          if (showDropdown)
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
                child: ListView(
                  shrinkWrap: true,
                  padding:
                      const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
                  children: [
                    for (var i = 0; i < suggestions.length; i++)
                      _SuggestionTile(
                        tag: suggestions[i],
                        isDark: widget.isDark,
                        count: widget.suggestionCounts[suggestions[i].id],
                        isSelected: i == _selectedIndex,
                        onTap: () => _selectSuggestion(suggestions[i]),
                      ),
                    if (showCreate)
                      _CreateTagTile(
                        text: _controller.text.trim().toLowerCase(),
                        isDark: widget.isDark,
                        isSelected:
                            _selectedIndex == suggestions.length,
                        label: l10n.historyCreateTag(
                            _controller.text.trim().toLowerCase()),
                        onTap: () => _submit(_controller.text),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Inline text field — sits at the end of the tag Wrap. Pill-styled.
  Widget _buildInlineField({
    required Color textPrimary,
    required Color textMuted,
    required Color accent,
    required Color borderCol,
  }) {
    final hasText = _controller.text.trim().isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 60, maxWidth: 200),
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
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs + 2,
          ),
          suffixIcon: hasText
              ? GestureDetector(
                  onTap: () => _submit(_controller.text),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      LucideIcons.cornerDownLeft,
                      size: 14,
                      color: textMuted,
                    ),
                  ),
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(maxWidth: 32, maxHeight: 32),
          border: OutlineInputBorder(
            borderRadius: WpRadius.borderFull,
            borderSide: BorderSide(color: borderCol),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: WpRadius.borderFull,
            borderSide: BorderSide(color: borderCol),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: WpRadius.borderFull,
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
        ),
        onChanged: _handleInputChanged,
        onSubmitted: _submit,
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
    this.isSelected = false,
  });

  final Tag tag;
  final bool isDark;
  final VoidCallback onTap;
  final int? count;
  final bool isSelected;

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
          color: (_isHovered || widget.isSelected) ? hoverBg : Colors.transparent,
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

// ---------------------------------------------------------------------------
// "Create" tile -- shown when typed text is novel
// ---------------------------------------------------------------------------

class _CreateTagTile extends StatefulWidget {
  const _CreateTagTile({
    required this.text,
    required this.isDark,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  final String text;
  final bool isDark;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  State<_CreateTagTile> createState() => _CreateTagTileState();
}

class _CreateTagTileState extends State<_CreateTagTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final hoverBg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;

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
          color: (_isHovered || widget.isSelected) ? hoverBg : Colors.transparent,
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: WpIconSize.sm,
                color: accent,
              ),
              const SizedBox(width: WpSpacing.xs),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: textPrimary,
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