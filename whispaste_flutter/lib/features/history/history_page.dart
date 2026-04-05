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

  HistoryEntry? get _selectedEntry {
    if (_selectedEntryId == null) return null;
    final idx = _sampleEntries.indexWhere((e) => e.id == _selectedEntryId);
    return idx >= 0 ? _sampleEntries[idx] : null;
  }

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
          // Master-detail content
          Expanded(
            child: hasResults
                ? _MasterDetail(
                    groups: groups,
                    isDark: isDark,
                    selectedEntry: _selectedEntry,
                    onEntryTap: (entry) => setState(() {
                      _selectedEntryId = entry.id;
                    }),
                    onCopy: _copyEntry,
                    onPin: _togglePin,
                    onDelete: _deleteEntry,
                    onCloseDetail: () =>
                        setState(() => _selectedEntryId = null),
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
// Master-detail layout
// ---------------------------------------------------------------------------

class _MasterDetail extends StatelessWidget {
  const _MasterDetail({
    required this.groups,
    required this.isDark,
    required this.selectedEntry,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onCloseDetail,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final HistoryEntry? selectedEntry;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final VoidCallback onCloseDetail;

  @override
  Widget build(BuildContext context) {
    if (selectedEntry == null) {
      // Full-width list (no detail selected)
      return _EntryList(
        groups: groups,
        isDark: isDark,
        selectedId: null,
        onEntryTap: onEntryTap,
        onCopy: onCopy,
        onPin: onPin,
        onDelete: onDelete,
      );
    }

    // Side-by-side: list + detail
    return Row(
      children: [
        // Entry list (narrower)
        SizedBox(
          width: 340,
          child: _EntryList(
            groups: groups,
            isDark: isDark,
            selectedId: selectedEntry!.id,
            onEntryTap: onEntryTap,
            onCopy: onCopy,
            onPin: onPin,
            onDelete: onDelete,
          ),
        ),
        // Divider
        Container(
          width: 1,
          color: isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle,
        ),
        // Detail panel
        Expanded(
          child: _DetailPanel(
            entry: selectedEntry!,
            isDark: isDark,
            onClose: onCloseDetail,
            onCopy: () => onCopy(selectedEntry!),
            onPin: () => onPin(selectedEntry!),
            onDelete: () => onDelete(selectedEntry!),
          ),
        ),
      ],
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
// Date group header — ChatGPT-style time divider
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final lineColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.md, WpSpacing.xl, WpSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content type avatar colors — gives each entry visual identity
// ---------------------------------------------------------------------------

/// Derives a warm avatar color from the entry's first tag or title.
Color _avatarColor(HistoryEntry entry, bool isDark) {
  // Palette of warm, distinguishable hues (not harsh, not glow)
  const palette = [
    Color(0xFF22D3EE), // cyan (default)
    Color(0xFF8B5CF6), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFF10B981), // emerald
    Color(0xFFF472B6), // pink
    Color(0xFF3B82F6), // blue
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
  ];
  // Hash from title for consistent color per entry
  final hash = entry.title.isNotEmpty
      ? entry.title.codeUnits.fold<int>(0, (a, b) => a + b)
      : entry.id.codeUnits.fold<int>(0, (a, b) => a + b);
  return palette[hash % palette.length];
}

/// Icon for the entry avatar — based on content/source hints.
IconData _avatarIcon(HistoryEntry entry) {
  final title = entry.title.toLowerCase();
  final tags = entry.tags.toLowerCase();

  if (tags.contains('meeting') || title.contains('meeting') || title.contains('standup')) {
    return LucideIcons.users;
  }
  if (tags.contains('email') || title.contains('email') || title.contains('follow')) {
    return LucideIcons.mail;
  }
  if (tags.contains('blog') || tags.contains('writing') || title.contains('blog') || title.contains('draft')) {
    return LucideIcons.penLine;
  }
  if (tags.contains('personal') || tags.contains('recipe')) {
    return LucideIcons.heart;
  }
  if (tags.contains('feedback') || title.contains('feedback') || title.contains('review')) {
    return LucideIcons.messageSquare;
  }
  if (tags.contains('project') || title.contains('project') || title.contains('brief')) {
    return LucideIcons.folderOpen;
  }
  if (tags.contains('idea') || tags.contains('team')) {
    return LucideIcons.lightbulb;
  }
  if (title.contains('reminder') || title.contains('todo')) {
    return LucideIcons.bellRing;
  }
  return LucideIcons.mic;
}

// ---------------------------------------------------------------------------
// History entry row — WhatsApp/ChatGPT/Discord-inspired
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

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final avatarCol = _avatarColor(widget.entry, isDark);

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
            horizontal: WpSpacing.xs,
            vertical: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderMd,
            // Left accent stripe for selected entry (Discord-style)
            border: widget.isSelected
                ? Border(
                    left: BorderSide(color: accent, width: 3),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar — colored circle with content-type icon
              _EntryAvatar(
                color: avatarCol,
                icon: _avatarIcon(widget.entry),
                isPinned: widget.entry.pinned,
                isDark: isDark,
              ),
              const SizedBox(width: WpSpacing.sm),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Title + time/actions
                    Row(
                      children: [
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
                        // Hover actions OR time
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
                        ] else
                          Text(
                            _timeLabel,
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Row 2: Content preview — single line, WhatsApp-style
                    Text(
                      widget.entry.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Row 3: Subtle inline metadata (duration + language)
                    Row(
                      children: [
                        Icon(LucideIcons.clock, size: 10, color: textMuted),
                        const SizedBox(width: 3),
                        Text(
                          _durationLabel,
                          style: TextStyle(fontSize: 10, color: textMuted),
                        ),
                        if (widget.entry.language.isNotEmpty) ...[
                          const SizedBox(width: WpSpacing.xs),
                          Text(
                            '·',
                            style: TextStyle(
                                fontSize: 10, color: textMuted),
                          ),
                          const SizedBox(width: WpSpacing.xs),
                          Text(
                            widget.entry.language.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (!widget.entry.isLocal) ...[
                          const SizedBox(width: WpSpacing.xs),
                          Text(
                            '·',
                            style: TextStyle(
                                fontSize: 10, color: textMuted),
                          ),
                          const SizedBox(width: WpSpacing.xs),
                          Icon(LucideIcons.cloud, size: 10, color: textMuted),
                        ],
                      ],
                    ),
                  ],
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
// Entry avatar — colored circle with icon (Discord/WhatsApp identity)
// ---------------------------------------------------------------------------

class _EntryAvatar extends StatelessWidget {
  const _EntryAvatar({
    required this.color,
    required this.icon,
    required this.isPinned,
    required this.isDark,
  });

  final Color color;
  final IconData icon;
  final bool isPinned;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          // Avatar circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 16,
              color: color.withValues(alpha: isDark ? 0.9 : 0.8),
            ),
          ),
          // Pin badge — small dot in corner
          if (isPinned)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel — opens on entry selection (ChatGPT/Notion detail view)
// ---------------------------------------------------------------------------

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.entry,
    required this.isDark,
    required this.onClose,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  String get _fullTimestamp {
    final t = entry.timestamp;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year} at '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  String get _durationLabel {
    final secs = entry.durationSec.round();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
  }

  List<String> get _tags {
    try {
      final decoded = jsonDecode(entry.tags);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final avatarCol = _avatarColor(entry, isDark);

    return Container(
      color: isDark
          ? WpColorsDark.surface
          : WpColorsLight.surface,
      child: Column(
        children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl, WpSpacing.md, WpSpacing.md, WpSpacing.sm,
            ),
            child: Row(
              children: [
                _EntryAvatar(
                  color: avatarCol,
                  icon: _avatarIcon(entry),
                  isPinned: entry.pinned,
                  isDark: isDark,
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title.isNotEmpty ? entry.title : 'Untitled',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fullTimestamp,
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                _DetailAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copy text',
                  isDark: isDark,
                  onTap: onCopy,
                ),
                _DetailAction(
                  icon: entry.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                  tooltip: entry.pinned ? 'Unpin' : 'Pin',
                  isDark: isDark,
                  onTap: onPin,
                ),
                _DetailAction(
                  icon: LucideIcons.trash2,
                  tooltip: 'Delete',
                  isDark: isDark,
                  onTap: onDelete,
                  isDestructive: true,
                ),
                const SizedBox(width: WpSpacing.xxs),
                _DetailAction(
                  icon: LucideIcons.x,
                  tooltip: 'Close',
                  isDark: isDark,
                  onTap: onClose,
                ),
              ],
            ),
          ),
          // Divider
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
            color: isDark
                ? WpColorsDark.borderSubtle
                : WpColorsLight.borderSubtle,
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WpSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full text
                  SelectableText(
                    entry.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: textPrimary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xxl),
                  // Metadata section
                  Container(
                    padding: const EdgeInsets.all(WpSpacing.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? WpColorsDark.surfaceElevated
                          : WpColorsLight.surfaceElevated,
                      borderRadius: WpRadius.borderMd,
                      border: Border.all(
                        color: isDark
                            ? WpColorsDark.borderSubtle
                            : WpColorsLight.borderSubtle,
                      ),
                    ),
                    child: Column(
                      children: [
                        _DetailMetaRow(
                          icon: LucideIcons.clock,
                          label: 'Duration',
                          value: _durationLabel,
                          isDark: isDark,
                        ),
                        if (entry.language.isNotEmpty)
                          _DetailMetaRow(
                            icon: LucideIcons.globe,
                            label: 'Language',
                            value: entry.language.toUpperCase(),
                            isDark: isDark,
                          ),
                        _DetailMetaRow(
                          icon: entry.isLocal
                              ? LucideIcons.hardDrive
                              : LucideIcons.cloud,
                          label: 'Processed',
                          value: entry.isLocal ? 'On device' : 'Cloud',
                          isDark: isDark,
                        ),
                        if (entry.model.isNotEmpty)
                          _DetailMetaRow(
                            icon: LucideIcons.cpu,
                            label: 'Model',
                            value: entry.model,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
                  // Tags
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: WpSpacing.md),
                    Wrap(
                      spacing: WpSpacing.xs,
                      runSpacing: WpSpacing.xs,
                      children: [
                        for (final tag in _tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.sm,
                              vertical: WpSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: WpRadius.borderFull,
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 12,
                                color: accent.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel action button
// ---------------------------------------------------------------------------

class _DetailAction extends StatefulWidget {
  const _DetailAction({
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
  State<_DetailAction> createState() => _DetailActionState();
}

class _DetailActionState extends State<_DetailAction> {
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
          child: AnimatedContainer(
            duration: WpMotion.fast,
            padding: const EdgeInsets.all(WpSpacing.xs),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                      ? WpColorsDark.hover
                      : WpColorsLight.hover)
                  : Colors.transparent,
              borderRadius: WpRadius.borderSm,
            ),
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail metadata row
// ---------------------------------------------------------------------------

class _DetailMetaRow extends StatelessWidget {
  const _DetailMetaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: textSecondary),
          const SizedBox(width: WpSpacing.sm),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row action button (hover-only, used in entry rows)
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
                    ? (widget.isDark
                        ? WpColorsDark.active
                        : WpColorsLight.active)
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
