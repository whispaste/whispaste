import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';

/// History page — recorded transcriptions with search, filter, and grouping.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _searchController = TextEditingController();
  String _activeFilter = 'all';

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
        // Search & filter toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.xs,
          ),
          child: Column(
            children: [
              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search transcriptions…',
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: WpIconSize.sm,
                    color: isDark
                        ? WpColorsDark.textMuted
                        : WpColorsLight.textMuted,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            size: WpIconSize.sm,
                            color: isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.md,
                    vertical: WpSpacing.xs + 2,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: WpSpacing.sm),
              // Filter chips
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'All',
                      isActive: _activeFilter == 'all',
                      onTap: () => setState(() => _activeFilter = 'all'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    _FilterChip(
                      label: 'Today',
                      isActive: _activeFilter == 'today',
                      onTap: () => setState(() => _activeFilter = 'today'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    _FilterChip(
                      label: 'This Week',
                      isActive: _activeFilter == 'week',
                      onTap: () => setState(() => _activeFilter = 'week'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    _FilterChip(
                      label: 'Favorites',
                      icon: LucideIcons.star,
                      isActive: _activeFilter == 'favorites',
                      onTap: () =>
                          setState(() => _activeFilter = 'favorites'),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        // Content — empty state for now, will be replaced with real data
        const Expanded(
          child: WpEmptyState(
            icon: LucideIcons.mic,
            title: 'No recordings yet',
            hint:
                'Press the record button or use the hotkey to start dictating.\nYour transcriptions will appear here.',
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.isDark,
    this.icon,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? icon;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (widget.isActive) {
      bg = widget.isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
      fg = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_isHovered) {
      bg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
      fg = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderFull,
            border: widget.isActive
                ? Border.all(
                    color: (widget.isDark
                            ? WpColorsDark.accent
                            : WpColorsLight.accent)
                        .withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 13, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
