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
    required this.onAdd,
    required this.onRemove,
    this.suggestions = const [],
    this.suggestionCounts = const {},
    this.onSearchChanged,
    required this.hintText,
    required this.searchHintText,
    this.inlineLabel,
  });

  final List<Tag> tags;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove; // tagId
  final List<Tag> suggestions;
  final Map<String, int> suggestionCounts;
  final ValueChanged<String>? onSearchChanged;

  /// Required rather than defaulted, for the reason spelled out on
  /// [WpSection.padding]: a default no caller wants is not a default, it is a
  /// trap. Both existing call sites pass a localized string; the defaults
  /// they replaced were the hardcoded English 'Add tag…' / 'Search or
  /// create…', so a third caller that forgot them would have shipped
  /// untranslated placeholder text into a German or Hebrew UI without any
  /// warning. Making them required moves that from a silent runtime defect
  /// to a compile error.
  final String hintText;
  final String searchHintText;

  /// Optional inline label widget rendered as the first element in the Wrap.
  final Widget? inlineLabel;

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
        if (trimmed.isNotEmpty && !widget.tags.any((t) => t.name == trimmed)) {
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
          final exact = suggestions.where((s) => s.name == query).firstOrNull;
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
    const accent = WpColors.accent;
    const textPrimary = WpColors.textPrimary;
    const textMuted = WpColors.textMuted;
    const surfaceEl = WpColors.surfaceElevated;
    const borderCol = WpColors.borderSubtle;
    final l10n = L10n.of(context);

    // Collapse tags when not editing.
    final visibleTags = _isAddMode
        ? widget.tags
        : widget.tags.take(_kMaxVisibleTags).toList();
    final hiddenCount = _isAddMode
        ? 0
        : max(0, widget.tags.length - _kMaxVisibleTags);

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
              if (widget.inlineLabel != null) widget.inlineLabel!,
              for (final tag in visibleTags)
                _TagChip(tag: tag, onRemove: () => widget.onRemove(tag.id)),
              if (hiddenCount > 0)
                // loam-ignore: a11y-interactive-semantics – semantics provided in _OverflowChip.build
                _OverflowChip(count: hiddenCount, onTap: enterAddMode),
              if (_isAddMode)
                _buildInlineField(
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  accent: accent,
                  borderCol: borderCol,
                )
              else
                // loam-ignore: a11y-interactive-semantics – semantics provided in _AddTagTrigger.build
                _AddTagTrigger(
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
                  padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
                  children: [
                    for (var i = 0; i < suggestions.length; i++)
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _SuggestionTile.build
                      _SuggestionTile(
                        tag: suggestions[i],
                        count: widget.suggestionCounts[suggestions[i].id],
                        isSelected: i == _selectedIndex,
                        onTap: () => _selectSuggestion(suggestions[i]),
                      ),
                    if (showCreate)
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _CreateTagTile.build
                      _CreateTagTile(
                        text: _controller.text.trim().toLowerCase(),
                        isSelected: _selectedIndex == suggestions.length,
                        label: l10n.historyCreateTag(
                          _controller.text.trim().toLowerCase(),
                        ),
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
        style: TextStyle(fontSize: WpTypography.body, color: textPrimary),
        decoration: InputDecoration(
          hintText: widget.searchHintText,
          hintStyle: TextStyle(fontSize: WpTypography.small, color: textMuted),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs + 2,
          ),
          suffixIcon: hasText
              ? GestureDetector(
                  onTap: () => _submit(_controller.text),
                  child: Padding(
                    padding: const EdgeInsets.only(right: WpSpacing.xxs),
                    child: Icon(
                      LucideIcons.cornerDownLeft,
                      size: 14,
                      color: textMuted,
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            maxWidth: 32,
            maxHeight: 32,
          ),
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
  const _TagChip({required this.tag, required this.onRemove});

  final Tag tag;
  final VoidCallback onRemove;

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const accent = WpColors.accent;
    const chipFill = WpColors.accentChipFill;
    const chipFillHover = WpColors.accentChipFillHover;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: WpMotion.durationFor(context, WpMotion.fast),
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs + 2,
        ),
        decoration: BoxDecoration(
          color: _isHovered ? chipFillHover : chipFill,
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.tag.name,
              style: const TextStyle(
                fontSize: WpTypography.body,
                color: accent,
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
                  // 2px pad enlarges the remove icon's tap area without
                  // inflating the compact chip height.
                  padding: const EdgeInsets.all(2),
                  child: AnimatedOpacity(
                    opacity: _isHovered ? 0.9 : 0.35,
                    duration: WpMotion.durationFor(
                      context,
                      _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
                    ),
                    child: const Icon(
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
  const _OverflowChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const textMuted = WpColors.textMuted;

    // Keep an explicit label here and exclude the visible text instead (the
    // `SettingRow` shape rather than the `MergeSemantics` one): "+12" is a
    // fine glyph but a useless accessible name, so the name has to be
    // written out. The old label was the hardcoded English "+12 more tags"
    // in an app that ships German and Hebrew — a screen reader user on any
    // other locale got an untranslated string.
    return Semantics(
      button: true,
      label: L10n.of(context).tagOverflowMore(count),
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
            border: Border.all(color: textMuted.withValues(alpha: 0.2)),
          ),
          child: ExcludeSemantics(
            child: Text(
              '+$count',
              style: const TextStyle(
                fontSize: WpTypography.small,
                color: textMuted,
                fontWeight: FontWeight.w500,
              ),
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
  const _AddTagTrigger({required this.onTap, this.label});

  final VoidCallback onTap;
  final String? label;

  @override
  State<_AddTagTrigger> createState() => _AddTagTriggerState();
}

class _AddTagTriggerState extends State<_AddTagTrigger> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const accent = WpColors.accent;
    const textMuted = WpColors.textMuted;

    // Two shapes in one control, so the semantics has to branch with it.
    // With a label the trigger renders that same string as `Text`, so the
    // wrapper must not repeat it (house idiom: MergeSemantics + a label-less
    // Semantics, and a single tap target here makes merging safe). Without
    // one it is a bare "+" icon and does need a spoken name — which used to
    // be the hardcoded English 'Add tag' in an app shipping German and
    // Hebrew. `notesAddTag` is that string, already translated.
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: widget.label == null ? L10n.of(context).notesAddTag : null,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
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
                      style: const TextStyle(
                        fontSize: WpTypography.small,
                        color: textMuted,
                      ),
                    ),
                  ],
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
// Suggestion tile
// ---------------------------------------------------------------------------

class _SuggestionTile extends StatefulWidget {
  const _SuggestionTile({
    required this.tag,
    required this.onTap,
    this.count,
    this.isSelected = false,
  });

  final Tag tag;
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
    const textPrimary = WpColors.textPrimary;
    const accent = WpColors.accent;
    const hoverBg = WpColors.hover;

    // House idiom (`section.dart`): MergeSemantics + a *label-less*
    // Semantics — a `label:` is prepended to the subtree's text, not a
    // replacement for it, so the `Text(widget.tag.name)` below made every
    // suggestion announce its tag twice.
    //
    // `selected: widget.isSelected` is the substantive half: focus stays in
    // the inline text field (`autofocus: true`, line ~355) while the arrow
    // keys move `_selectedIndex` through this list. The highlight was purely
    // a background colour, so without the flag a screen reader reported
    // nothing at all as the user arrowed down.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.isSelected,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.sm,
              ),
              color: (_isHovered || widget.isSelected)
                  ? hoverBg
                  : Colors.transparent,
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
                      style: const TextStyle(
                        fontSize: WpTypography.body,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  if (widget.count != null && widget.count! > 0)
                    // The bare glyph "12" reads as a naked number once the
                    // row is merged ("Arbeit, 12"). `tagUsageCount` is the
                    // same number spelled out — it already exists in all
                    // three locales for the tag-management list, and it is
                    // what this column has always meant.
                    Semantics(
                      label: L10n.of(context).tagUsageCount(widget.count!),
                      excludeSemantics: true,
                      child: Text(
                        '${widget.count}',
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          color: textPrimary.withValues(alpha: 0.4),
                        ),
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
// "Create" tile -- shown when typed text is novel
// ---------------------------------------------------------------------------

class _CreateTagTile extends StatefulWidget {
  const _CreateTagTile({
    required this.text,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  final String text;
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
    const textPrimary = WpColors.textPrimary;
    const accent = WpColors.accent;
    const hoverBg = WpColors.hover;

    // Same construction and same reasoning as `_SuggestionRow` above: the
    // create-row is the last stop of the very same arrow-key walk
    // (`_selectedIndex == suggestions.length`), so it needs `selected:` for
    // the same reason, and its `Text(widget.label)` made it announce twice.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.isSelected,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.sm,
              ),
              color: (_isHovered || widget.isSelected)
                  ? hoverBg
                  : Colors.transparent,
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.plus,
                    size: WpIconSize.sm,
                    color: accent,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: WpTypography.body,
                        color: textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
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
