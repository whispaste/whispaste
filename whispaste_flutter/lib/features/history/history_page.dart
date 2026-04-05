import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import 'data/database.dart';
import 'data/providers.dart';
import 'data/sample_data.dart';

/// History page — recorded transcriptions with search, filter, and grouping.
///
/// Uses a chat-style layout: flat rows with hover highlight, date group
/// headers, and conversational preview. Inspired by ChatGPT/WhatsApp list
/// views — scannable, warm, and fast to navigate.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _searchController = TextEditingController();
  // Sample mode — shows preview data until real recording is connected
  late List<HistoryEntry> _sampleEntries;
  String? _selectedEntryId;

  @override
  void initState() {
    super.initState();
    _sampleEntries = generateSampleEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  HistoryFilter _activeFilter = HistoryFilter.all;

  List<HistoryEntry> get _filteredEntries {
    var entries = _sampleEntries;
    final search = _searchController.text.toLowerCase().trim();

    // Apply filter
    final now = DateTime.now();
    switch (_activeFilter) {
      case HistoryFilter.today:
        entries = entries
            .where((e) =>
                e.timestamp.year == now.year &&
                e.timestamp.month == now.month &&
                e.timestamp.day == now.day)
            .toList();
      case HistoryFilter.week:
        final weekAgo = now.subtract(const Duration(days: 7));
        entries = entries.where((e) => e.timestamp.isAfter(weekAgo)).toList();
      case HistoryFilter.favorites:
        entries = entries.where((e) => e.pinned).toList();
      case HistoryFilter.all:
        break;
    }

    // Apply search
    if (search.isNotEmpty) {
      entries = entries
          .where((e) =>
              e.title.toLowerCase().contains(search) ||
              e.content.toLowerCase().contains(search))
          .toList();
    }

    return entries;
  }

  List<DateGroup> get _groupedEntries {
    final entries = _filteredEntries;
    if (entries.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayEntries = <HistoryEntry>[];
    final yesterdayEntries = <HistoryEntry>[];
    final weekEntries = <HistoryEntry>[];
    final olderEntries = <HistoryEntry>[];

    for (final e in entries) {
      final d = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      if (d == today) {
        todayEntries.add(e);
      } else if (d == yesterday) {
        yesterdayEntries.add(e);
      } else if (d.isAfter(weekAgo)) {
        weekEntries.add(e);
      } else {
        olderEntries.add(e);
      }
    }

    return [
      if (todayEntries.isNotEmpty)
        DateGroup(label: 'Today', entries: todayEntries),
      if (yesterdayEntries.isNotEmpty)
        DateGroup(label: 'Yesterday', entries: yesterdayEntries),
      if (weekEntries.isNotEmpty)
        DateGroup(label: 'This Week', entries: weekEntries),
      if (olderEntries.isNotEmpty)
        DateGroup(label: 'Older', entries: olderEntries),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = _groupedEntries;
    final hasResults = groups.isNotEmpty;

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Search & filter toolbar
          _SearchToolbar(
            controller: _searchController,
            activeFilter: _activeFilter,
            isDark: isDark,
            onFilterChanged: (f) => setState(() => _activeFilter = f),
            onSearchChanged: () => setState(() {}),
            resultCount: _filteredEntries.length,
          ),
          // Divider
          Container(
            height: 1,
            color: isDark
                ? WpColorsDark.borderSubtle
                : WpColorsLight.borderSubtle,
          ),
          // Content
          Expanded(
            child: hasResults
                ? _EntryList(
                    groups: groups,
                    isDark: isDark,
                    selectedId: _selectedEntryId,
                    onEntryTap: (entry) => setState(() {
                      _selectedEntryId = entry.id;
                    }),
                    onCopy: _copyEntry,
                    onPin: _togglePin,
                    onDelete: _deleteEntry,
                  )
                : _searchController.text.isNotEmpty
                    ? WpEmptyState(
                        icon: LucideIcons.searchX,
                        title: 'No results',
                        hint:
                            'No transcriptions match "${_searchController.text}".\nTry a different search term.',
                      )
                    : const WpEmptyState(
                        icon: LucideIcons.mic,
                        title: 'No recordings yet',
                        hint:
                            'Press the record button or use the hotkey to start dictating.\nYour transcriptions will appear here.',
                      ),
          ),
        ],
      ),
    );
  }

  void _copyEntry(HistoryEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ),
    );
  }

  void _togglePin(HistoryEntry entry) {
    setState(() {
      final idx = _sampleEntries.indexWhere((e) => e.id == entry.id);
      if (idx >= 0) {
        final old = _sampleEntries[idx];
        _sampleEntries[idx] = HistoryEntry(
          id: old.id,
          content: old.content,
          title: old.title,
          timestamp: old.timestamp,
          durationSec: old.durationSec,
          processingDurationSec: old.processingDurationSec,
          language: old.language,
          languageHint: old.languageHint,
          tags: old.tags,
          pinned: !old.pinned,
          source: old.source,
          model: old.model,
          isLocal: old.isLocal,
          costUsd: old.costUsd,
          projectId: old.projectId,
          archived: old.archived,
          titleEdited: old.titleEdited,
          deletedAt: old.deletedAt,
        );
      }
    });
  }

  void _deleteEntry(HistoryEntry entry) {
    setState(() {
      _sampleEntries.removeWhere((e) => e.id == entry.id);
      if (_selectedEntryId == entry.id) _selectedEntryId = null;
    });
  }
}

// ---------------------------------------------------------------------------
// Search & filter toolbar
// ---------------------------------------------------------------------------

class _SearchToolbar extends StatelessWidget {
  const _SearchToolbar({
    required this.controller,
    required this.activeFilter,
    required this.isDark,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.resultCount,
  });

  final TextEditingController controller;
  final HistoryFilter activeFilter;
  final bool isDark;
  final ValueChanged<HistoryFilter> onFilterChanged;
  final VoidCallback onSearchChanged;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Search transcriptions…',
              prefixIcon: Icon(
                LucideIcons.search,
                size: WpIconSize.sm,
                color:
                    isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: WpIconSize.sm,
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                      onPressed: () {
                        controller.clear();
                        onSearchChanged();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.xs + 2,
              ),
            ),
            onChanged: (_) => onSearchChanged(),
          ),
          const SizedBox(height: WpSpacing.sm),
          // Filter chips + result count
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: 'All',
                        isActive: activeFilter == HistoryFilter.all,
                        onTap: () => onFilterChanged(HistoryFilter.all),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: 'Today',
                        isActive: activeFilter == HistoryFilter.today,
                        onTap: () => onFilterChanged(HistoryFilter.today),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: 'This Week',
                        isActive: activeFilter == HistoryFilter.week,
                        onTap: () => onFilterChanged(HistoryFilter.week),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: 'Favorites',
                        icon: LucideIcons.star,
                        isActive: activeFilter == HistoryFilter.favorites,
                        onTap: () => onFilterChanged(HistoryFilter.favorites),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
              // Result count
              if (controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: WpSpacing.sm),
                  child: Text(
                    '$resultCount result${resultCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? WpColorsDark.textMuted
                          : WpColorsLight.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry list with date groups
// ---------------------------------------------------------------------------

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    // Build a flat list of widgets: section headers + entry rows
    final items = <Widget>[];

    for (final group in groups) {
      items.add(_DateHeader(label: group.label, isDark: isDark));
      for (final entry in group.entries) {
        items.add(
          _HistoryEntryRow(
            entry: entry,
            isDark: isDark,
            isSelected: entry.id == selectedId,
            onTap: () => onEntryTap(entry),
            onCopy: () => onCopy(entry),
            onPin: () => onPin(entry),
            onDelete: () => onDelete(entry),
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: WpSpacing.xs,
        bottom: WpSpacing.xxl,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

// ---------------------------------------------------------------------------
// Date group header
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.md, WpSpacing.xl, WpSpacing.xxs,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History entry row — flat, ChatGPT/WhatsApp-inspired
// ---------------------------------------------------------------------------

class _HistoryEntryRow extends StatefulWidget {
  const _HistoryEntryRow({
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  State<_HistoryEntryRow> createState() => _HistoryEntryRowState();
}

class _HistoryEntryRowState extends State<_HistoryEntryRow> {
  bool _isHovered = false;

  String get _timeLabel {
    final t = widget.entry.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  String get _durationLabel {
    final secs = widget.entry.durationSec.round();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
  }

  List<String> get _tags {
    try {
      final decoded = jsonDecode(widget.entry.tags);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    // Row background
    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = Colors.transparent;
    }

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          margin: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderSm,
            border: widget.isSelected
                ? Border.all(color: accent.withValues(alpha: 0.2))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Title + metadata + actions
              Row(
                children: [
                  // Pin indicator
                  if (widget.entry.pinned) ...[
                    Icon(LucideIcons.pin, size: 12, color: accent),
                    const SizedBox(width: WpSpacing.xxs),
                  ],
                  // Title
                  Expanded(
                    child: Text(
                      widget.entry.title.isNotEmpty
                          ? widget.entry.title
                          : 'Untitled recording',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  // Hover actions
                  if (_isHovered) ...[
                    _RowAction(
                      icon: LucideIcons.copy,
                      tooltip: 'Copy text',
                      isDark: isDark,
                      onTap: widget.onCopy,
                    ),
                    _RowAction(
                      icon: widget.entry.pinned
                          ? LucideIcons.pinOff
                          : LucideIcons.pin,
                      tooltip:
                          widget.entry.pinned ? 'Unpin' : 'Pin to top',
                      isDark: isDark,
                      onTap: widget.onPin,
                    ),
                    _RowAction(
                      icon: LucideIcons.trash2,
                      tooltip: 'Delete',
                      isDark: isDark,
                      onTap: widget.onDelete,
                      isDestructive: true,
                    ),
                  ] else ...[
                    // Time label (when not hovering)
                    Text(
                      _timeLabel,
                      style: TextStyle(fontSize: 11, color: textMuted),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: WpSpacing.xxs),
              // Row 2: Content preview
              Text(
                widget.entry.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs + 2),
              // Row 3: Tags + metadata chips
              Row(
                children: [
                  // Duration
                  _MetaChip(
                    icon: LucideIcons.clock,
                    label: _durationLabel,
                    isDark: isDark,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  // Language
                  if (widget.entry.language.isNotEmpty) ...[
                    _MetaChip(
                      icon: LucideIcons.globe,
                      label: widget.entry.language.toUpperCase(),
                      isDark: isDark,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                  ],
                  // Local/Cloud indicator
                  _MetaChip(
                    icon: widget.entry.isLocal
                        ? LucideIcons.hardDrive
                        : LucideIcons.cloud,
                    label: widget.entry.isLocal ? 'Local' : 'Cloud',
                    isDark: isDark,
                  ),
                  const Spacer(),
                  // Tags (max 2 visible)
                  ..._buildTags(textMuted, accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTags(Color textMuted, Color accent) {
    final tags = _tags;
    if (tags.isEmpty) return [];

    final visible = tags.take(2).toList();
    final remaining = tags.length - visible.length;

    return [
      for (final tag in visible) ...[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xxs + 2,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: WpRadius.borderSm,
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 10,
              color: accent.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
      if (remaining > 0)
        Text(
          '+$remaining',
          style: TextStyle(fontSize: 10, color: textMuted),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Row action button (hover-only)
// ---------------------------------------------------------------------------

class _RowAction extends StatefulWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<_RowAction> createState() => _RowActionState();
}

class _RowActionState extends State<_RowAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    if (widget.isDestructive && _isHovered) {
      iconColor = widget.isDark ? WpColorsDark.error : WpColorsLight.error;
    } else if (_isHovered) {
      iconColor = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      iconColor = widget.isDark
          ? WpColorsDark.textMuted
          : WpColorsLight.textMuted;
    }

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xxs,
              vertical: 2,
            ),
            child: AnimatedContainer(
              duration: WpMotion.fast,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _isHovered
                    ? (widget.isDark ? WpColorsDark.active : WpColorsLight.active)
                    : Colors.transparent,
                borderRadius: WpRadius.borderSm,
              ),
              child: Icon(widget.icon, size: 14, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metadata chip (duration, language, local/cloud)
// ---------------------------------------------------------------------------

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip
// ---------------------------------------------------------------------------

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
      bg = widget.isDark
          ? WpColorsDark.accentSubtle
          : WpColorsLight.accentSubtle;
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
          duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
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
