/// Compact inline tag editor with progressive-disclosure add mode.
///
/// Shows existing tags as removable accent-tinted pills. Tap the "+" pill
/// or press the T shortcut to enter add mode — an inline search/create
/// field with type-ahead autocomplete.
///
/// Mobile-first: remove icons always visible, generous touch targets,
/// progressive disclosure hides complexity until needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/data/database.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

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

  /// Called by keyboard shortcut (T) to enter add mode.
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

    return TapRegion(
      onTapOutside: _isAddMode ? (_) => _closeAddMode() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Empty state: clickable placeholder ──
          if (widget.tags.isEmpty && !_isAddMode)
            Semantics(
              button: true,
              label: widget.hintText,
              child: GestureDetector(
                onTap: enterAddMode,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: WpSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.plus,
                          size: WpIconSize.sm,
                          color: accent.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: WpSpacing.xxs),
                        Text(
                          widget.hintText,
                          style: TextStyle(
                            fontSize: 13,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Tag pills + "+" trigger ──
          if (widget.tags.isNotEmpty || _isAddMode)
            Wrap(
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in widget.tags)
                  _TagChip(
                    tag: tag,
                    isDark: widget.isDark,
                    onRemove: () => widget.onRemove(tag.id),
                  ),
                if (!_isAddMode && widget.tags.isNotEmpty)
                  _AddTagPill(
                    isDark: widget.isDark,
                    onTap: enterAddMode,
                    semanticsLabel: widget.hintText,
                  ),
              ],
            ),

          // ── Inline search input (add mode only) ──
          if (_isAddMode) ...[
            const SizedBox(height: WpSpacing.xs),
            SizedBox(
              height: 40,
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      _closeAddMode();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey ==
                            LogicalKeyboardKey.backspace &&
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
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: widget.searchHintText,
                    hintStyle: TextStyle(fontSize: 13, color: textMuted),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(
                          left: WpSpacing.sm, right: WpSpacing.xs),
                      child: Icon(LucideIcons.search,
                          size: WpIconSize.sm, color: textMuted),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minHeight: 0, minWidth: 0),
                    suffixIcon: Semantics(
                      button: true,
                      label: 'Close',
                      child: GestureDetector(
                        onTap: _closeAddMode,
                        child: Padding(
                          padding: const EdgeInsets.all(WpSpacing.xs),
                          child: Icon(LucideIcons.x,
                              size: WpIconSize.sm, color: textMuted),
                        ),
                      ),
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(minHeight: 0, minWidth: 0),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.sm,
                      vertical: WpSpacing.xs,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: WpRadius.borderSm,
                      borderSide: BorderSide(color: borderCol),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: WpRadius.borderSm,
                      borderSide: BorderSide(color: borderCol),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: WpRadius.borderSm,
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    widget.onSearchChanged?.call(v.trim());
                    setState(() {});
                  },
                  onSubmitted: _submit,
                ),
              ),
            ),
            // Suggestions dropdown
            if (_filteredSuggestions.isNotEmpty)
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
        ],
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
// "+" pill — visually matches tag chips, acts as add-mode trigger
// ---------------------------------------------------------------------------

class _AddTagPill extends StatefulWidget {
  const _AddTagPill({
    required this.isDark,
    required this.onTap,
    required this.semanticsLabel,
  });

  final bool isDark;
  final VoidCallback onTap;
  final String semanticsLabel;

  @override
  State<_AddTagPill> createState() => _AddTagPillState();
}

class _AddTagPillState extends State<_AddTagPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: AnimatedContainer(
              duration: WpMotion.fast,
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xxs + 2,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: _isHovered ? 0.08 : 0.0),
                borderRadius: WpRadius.borderFull,
                border: Border.all(
                  color: accent.withValues(alpha: _isHovered ? 0.4 : 0.2),
                ),
              ),
              child: Icon(
                LucideIcons.plus,
                size: WpIconSize.xs,
                color: accent.withValues(alpha: _isHovered ? 0.7 : 0.4),
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
