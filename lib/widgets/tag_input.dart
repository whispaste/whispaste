/// Compact inline tag editor with type-ahead autocomplete.
///
/// Shows existing tags as removable chips + a text field for adding new ones.
/// Suggestions come from [frequentTags] and [searchTags] in the database.
///
/// Mobile-first: remove icons always visible, touch targets ≥ 48px,
/// interactive icons ≥ 20px.
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
    this.focusNode,
  });

  final List<Tag> tags;
  final bool isDark;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove; // tagId
  final List<Tag> suggestions;
  final Map<String, int> suggestionCounts;
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
            for (final tag in widget.tags)
              _TagChip(
                tag: tag,
                isDark: widget.isDark,
                onRemove: () => widget.onRemove(tag.id),
              ),
            // Inline text input — flexible width, proper height for touch
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
              child: SizedBox(
                height: 36,
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
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
                    style: TextStyle(fontSize: 13, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: widget.tags.isEmpty ? widget.hintText : '+',
                      hintStyle: TextStyle(fontSize: 13, color: textMuted),
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
            ),
          ],
        ),
        // Suggestions dropdown
        if (_showSuggestions && _filteredSuggestions.isNotEmpty)
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
                padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Removable tag chip — remove icon always visible (mobile-first)
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
          color: accent.withValues(alpha: _isHovered ? 0.18 : 0.1),
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#${widget.tag.name}',
              style: TextStyle(
                fontSize: 13,
                color: accent.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: WpSpacing.xxs),
            // Always visible — opacity increases on hover
            GestureDetector(
              onTap: widget.onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: AnimatedOpacity(
                  opacity: _isHovered ? 0.9 : 0.4,
                  duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
                  child: Icon(
                    LucideIcons.x,
                    size: WpIconSize.sm,
                    color: accent,
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
