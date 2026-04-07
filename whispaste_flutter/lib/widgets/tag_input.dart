/// Compact inline tag editor with type-ahead autocomplete.
///
/// Shows existing tags as removable chips + a text field for adding new ones.
/// Suggestions come from [frequentTags] and [searchTags] in the database.
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
    this.onSearchChanged,
    this.hintText = 'Add tag…',
    this.focusNode,
  });

  final List<Tag> tags;
  final bool isDark;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove; // tagId
  final List<Tag> suggestions;
  final ValueChanged<String>? onSearchChanged;
  final String hintText;
  final FocusNode? focusNode;

  @override
  State<WpTagInput> createState() => _WpTagInputState();
}

class _WpTagInputState extends State<WpTagInput> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _showSuggestions = _focusNode.hasFocus;
    });
    if (_focusNode.hasFocus && _controller.text.isEmpty) {
      widget.onSearchChanged?.call('');
    }
  }

  void _submit(String text) {
    final trimmed = text.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    // Don't add duplicates
    if (widget.tags.any((t) => t.name == trimmed)) {
      _controller.clear();
      return;
    }
    widget.onAdd(trimmed);
    _controller.clear();
    widget.onSearchChanged?.call('');
  }

  void _selectSuggestion(Tag tag) {
    if (widget.tags.any((t) => t.id == tag.id)) return;
    widget.onAdd(tag.name);
    _controller.clear();
    widget.onSearchChanged?.call('');
    _focusNode.requestFocus();
  }

  List<Tag> get _filteredSuggestions {
    final query = _controller.text.trim().toLowerCase();
    final existingIds = widget.tags.map((t) => t.id).toSet();
    return widget.suggestions
        .where((t) => !existingIds.contains(t.id))
        .where((t) => query.isEmpty || t.name.contains(query))
        .take(8)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tag chips + input row
        Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Existing tags as removable chips
            for (final tag in widget.tags)
              _TagChip(
                tag: tag,
                isDark: widget.isDark,
                onRemove: () => widget.onRemove(tag.id),
              ),
            // Inline text input
            SizedBox(
              width: 140,
              height: 28,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  // Delete last tag on backspace with empty field
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace &&
                      _controller.text.isEmpty &&
                      widget.tags.isNotEmpty) {
                    widget.onRemove(widget.tags.last.id);
                  }
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(fontSize: 12, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: widget.tags.isEmpty ? widget.hintText : '+',
                    hintStyle: TextStyle(fontSize: 12, color: textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.xs,
                      vertical: 4,
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
          ],
        ),
        // Suggestions dropdown
        if (_showSuggestions && _filteredSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WpSpacing.xxs),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: surfaceEl,
                borderRadius: WpRadius.borderSm,
                border: Border.all(color: borderCol),
                boxShadow: WpShadows.subtle,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: _filteredSuggestions.length,
                itemBuilder: (_, i) {
                  final tag = _filteredSuggestions[i];
                  return _SuggestionTile(
                    tag: tag,
                    isDark: widget.isDark,
                    onTap: () => _selectSuggestion(tag),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Removable tag chip
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
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: _isHovered ? 0.18 : 0.1),
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#${widget.tag.name}',
              style: TextStyle(
                fontSize: 12,
                color: accent.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_isHovered) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onRemove,
                child: Icon(
                  LucideIcons.x,
                  size: 12,
                  color: accent.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
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
  });

  final Tag tag;
  final bool isDark;
  final VoidCallback onTap;

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
    final hoverBg =
        widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs,
          ),
          color: _isHovered ? hoverBg : Colors.transparent,
          child: Row(
            children: [
              Icon(
                LucideIcons.hash,
                size: 13,
                color: textPrimary.withValues(alpha: 0.5),
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                widget.tag.name,
                style: TextStyle(fontSize: 12, color: textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
