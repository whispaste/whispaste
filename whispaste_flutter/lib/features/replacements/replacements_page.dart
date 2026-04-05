import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';

/// Voice Shortcuts (Replacements) page — auto-replace words during dictation.
class ReplacementsPage extends StatefulWidget {
  const ReplacementsPage({super.key});

  @override
  State<ReplacementsPage> createState() => _ReplacementsPageState();
}

class _ReplacementsPageState extends State<ReplacementsPage> {
  final _searchController = TextEditingController();

  // Placeholder data — will be replaced by Riverpod state + persistence
  final List<_Replacement> _replacements = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.sm,
          ),
          child: Row(
            children: [
              // Search
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search shortcuts…',
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: WpIconSize.sm,
                      color: isDark
                          ? WpColorsDark.textMuted
                          : WpColorsLight.textMuted,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.md,
                      vertical: WpSpacing.xs + 2,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              // Add button
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(LucideIcons.plus, size: WpIconSize.sm),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _replacements.isEmpty
              ? const WpEmptyState(
                  icon: LucideIcons.replace,
                  title: 'No voice shortcuts yet',
                  hint:
                      'Add shortcuts to auto-replace words during dictation.\n'
                      'Example: "btw" → "by the way"',
                  actionLabel: 'Add Shortcut',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.xl,
                    vertical: WpSpacing.xs,
                  ),
                  itemCount: _replacements.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: WpSpacing.xs),
                  itemBuilder: (context, index) {
                    final r = _replacements[index];
                    return _ReplacementTile(
                      replacement: r,
                      isDark: isDark,
                      onDelete: () {
                        setState(() => _replacements.removeAt(index));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showAddDialog() {
    // TODO: Show add replacement dialog
  }
}

class _Replacement {
  const _Replacement({
    required this.trigger,
    required this.replacement,
  });

  final String trigger;
  final String replacement;
}

class _ReplacementTile extends StatefulWidget {
  const _ReplacementTile({
    required this.replacement,
    required this.isDark,
    required this.onDelete,
  });

  final _Replacement replacement;
  final bool isDark;
  final VoidCallback onDelete;

  @override
  State<_ReplacementTile> createState() => _ReplacementTileState();
}

class _ReplacementTileState extends State<_ReplacementTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: WpMotion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
              : (widget.isDark
                  ? WpColorsDark.surfaceElevated
                  : WpColorsLight.surfaceElevated),
          borderRadius: WpRadius.borderMd,
          border: Border.all(
            color: _isHovered
                ? (widget.isDark
                    ? WpColorsDark.glassBorder
                    : WpColorsLight.borderDefault)
                : (widget.isDark
                    ? WpColorsDark.borderSubtle
                    : WpColorsLight.borderSubtle),
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.arrowRightLeft,
              size: WpIconSize.sm,
              color: widget.isDark
                  ? WpColorsDark.accent
                  : WpColorsLight.accent,
            ),
            const SizedBox(width: WpSpacing.sm),
            // Trigger
            Text(
              '"${widget.replacement.trigger}"',
              style: TextStyle(
                color: widget.isDark
                    ? WpColorsDark.textPrimary
                    : WpColorsLight.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Icon(
              LucideIcons.arrowRight,
              size: 12,
              color: widget.isDark
                  ? WpColorsDark.textMuted
                  : WpColorsLight.textMuted,
            ),
            const SizedBox(width: WpSpacing.sm),
            // Replacement
            Expanded(
              child: Text(
                '"${widget.replacement.replacement}"',
                style: TextStyle(
                  color: widget.isDark
                      ? WpColorsDark.textSecondary
                      : WpColorsLight.textSecondary,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Delete on hover
            if (_isHovered)
              IconButton(
                icon: Icon(
                  LucideIcons.trash2,
                  size: WpIconSize.sm,
                  color: widget.isDark
                      ? WpColorsDark.error
                      : WpColorsLight.error,
                ),
                onPressed: widget.onDelete,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ],
        ),
      ),
    );
  }
}
