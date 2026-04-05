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

/// View mode for the history page.
enum _ViewMode { list, cards, compact }

/// Formats timestamp as HH:MM.
String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Formats recording duration as human-readable string.
String _formatDuration(double durationSec) {
  final secs = durationSec.round();
  if (secs < 60) return '${secs}s';
  final mins = secs ~/ 60;
  final rem = secs % 60;
  return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
}

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
  _ViewMode _viewMode = _ViewMode.list;

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
      case HistoryFilter.pinned:
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
            viewMode: _viewMode,
            onViewModeChanged: (m) => setState(() => _viewMode = m),
          ),
          // Master-detail content
          Expanded(
            child: hasResults
                ? _MasterDetail(
                    groups: groups,
                    isDark: isDark,
                    viewMode: _viewMode,
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
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final TextEditingController controller;
  final HistoryFilter activeFilter;
  final bool isDark;
  final ValueChanged<HistoryFilter> onFilterChanged;
  final VoidCallback onSearchChanged;
  final int resultCount;
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;

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
          // Filter chips + result count + view mode toggle
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
                        label: 'Pinned',
                        icon: LucideIcons.pin,
                        isActive: activeFilter == HistoryFilter.pinned,
                        onTap: () => onFilterChanged(HistoryFilter.pinned),
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
              const SizedBox(width: WpSpacing.sm),
              // View mode toggle
              _ViewModeToggle(
                viewMode: viewMode,
                isDark: isDark,
                onChanged: onViewModeChanged,
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

class _MasterDetail extends StatefulWidget {
  const _MasterDetail({
    required this.groups,
    required this.isDark,
    required this.viewMode,
    required this.selectedEntry,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onCloseDetail,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final _ViewMode viewMode;
  final HistoryEntry? selectedEntry;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final VoidCallback onCloseDetail;

  @override
  State<_MasterDetail> createState() => _MasterDetailState();
}

class _MasterDetailState extends State<_MasterDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _detailWidth;
  HistoryEntry? _displayedEntry;

  static const _masterWidth = 340.0;
  static const _dividerWidth = 1.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _detailWidth = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    if (widget.selectedEntry != null) {
      _displayedEntry = widget.selectedEntry;
      _anim.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _MasterDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedEntry != null && oldWidget.selectedEntry == null) {
      // Opening detail panel
      _displayedEntry = widget.selectedEntry;
      _anim.forward();
    } else if (widget.selectedEntry == null && oldWidget.selectedEntry != null) {
      // Closing detail panel
      _anim.reverse().then((_) {
        if (mounted) setState(() => _displayedEntry = null);
      });
    } else if (widget.selectedEntry != null) {
      // Switching to different entry
      _displayedEntry = widget.selectedEntry;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _buildMasterBody({String? selectedId}) {
    switch (widget.viewMode) {
      case _ViewMode.list:
        return _EntryList(
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          onEntryTap: widget.onEntryTap,
          onCopy: widget.onCopy,
          onPin: widget.onPin,
          onDelete: widget.onDelete,
        );
      case _ViewMode.cards:
        return _CardView(
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          onEntryTap: widget.onEntryTap,
          onCopy: widget.onCopy,
          onPin: widget.onPin,
          onDelete: widget.onDelete,
        );
      case _ViewMode.compact:
        return _CompactView(
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          onEntryTap: widget.onEntryTap,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDetail =
        widget.selectedEntry != null || _displayedEntry != null;

    if (!showDetail) {
      return _buildMasterBody();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _detailWidth,
          builder: (context, _) {
            final detailFraction = _detailWidth.value;
            final detailW =
                (totalWidth - _masterWidth - _dividerWidth) * detailFraction;
            final masterW = totalWidth - detailW - _dividerWidth;

            return Row(
              children: [
                SizedBox(
                  width: masterW.clamp(_masterWidth, totalWidth),
                  child: _buildMasterBody(
                    selectedId: (widget.selectedEntry ?? _displayedEntry)?.id,
                  ),
                ),
                Container(
                  width: _dividerWidth,
                  color: widget.isDark
                      ? WpColorsDark.borderSubtle
                      : WpColorsLight.borderSubtle,
                ),
                SizedBox(
                  width: detailW.clamp(0.0, totalWidth - _masterWidth),
                  child: detailFraction > 0.05
                      ? Opacity(
                          opacity: detailFraction.clamp(0.0, 1.0),
                          child: _DetailPanel(
                            entry:
                                widget.selectedEntry ?? _displayedEntry!,
                            isDark: widget.isDark,
                            onClose: widget.onCloseDetail,
                            onCopy: () => widget.onCopy(
                                widget.selectedEntry ?? _displayedEntry!),
                            onPin: () => widget.onPin(
                                widget.selectedEntry ?? _displayedEntry!),
                            onDelete: () => widget.onDelete(
                                widget.selectedEntry ?? _displayedEntry!),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        );
      },
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
            vertical: WpSpacing.md,
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
                size: 42,
              ),
              const SizedBox(width: WpSpacing.sm),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Title + time/actions (fixed height — no jiggle)
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
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        // Fixed-height container: cross-fade time ↔ actions
                        SizedBox(
                          height: 28,
                          child: Stack(
                            alignment: Alignment.centerRight,
                            children: [
                              // Time label (fades out on hover)
                              AnimatedOpacity(
                                duration: _isHovered
                                    ? WpMotion.fast
                                    : WpMotion.hoverOut,
                                opacity: _isHovered ? 0.0 : 1.0,
                                child: Text(
                                  _timeLabel,
                                  style: TextStyle(
                                      fontSize: 11, color: textMuted),
                                ),
                              ),
                              // Action buttons (fade in on hover)
                              IgnorePointer(
                                ignoring: !_isHovered,
                                child: AnimatedOpacity(
                                  duration: _isHovered
                                      ? WpMotion.fast
                                      : WpMotion.hoverOut,
                                  opacity: _isHovered ? 1.0 : 0.0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
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
                                        tooltip: widget.entry.pinned
                                            ? 'Unpin'
                                            : 'Pin to top',
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
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Row 2: Content preview — two lines for more context
                    Text(
                      widget.entry.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
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
    this.size = 36,
  });

  final Color color;
  final IconData icon;
  final bool isPinned;
  final bool isDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = (size * 0.44).roundToDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Avatar circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: iconSize,
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

// ---------------------------------------------------------------------------
// View mode toggle — segmented icon button group
// ---------------------------------------------------------------------------

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.viewMode,
    required this.isDark,
    required this.onChanged,
  });

  final _ViewMode viewMode;
  final bool isDark;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: LucideIcons.list,
            isActive: viewMode == _ViewMode.list,
            isDark: isDark,
            onTap: () => onChanged(_ViewMode.list),
          ),
          _ViewModeButton(
            icon: LucideIcons.layoutGrid,
            isActive: viewMode == _ViewMode.cards,
            isDark: isDark,
            onTap: () => onChanged(_ViewMode.cards),
          ),
          _ViewModeButton(
            icon: LucideIcons.rows3,
            isActive: viewMode == _ViewMode.compact,
            isDark: isDark,
            onTap: () => onChanged(_ViewMode.compact),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
        : (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted);
    final bg = isActive
        ? (isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle)
        : Colors.transparent;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(WpSpacing.xxs),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderSm,
          ),
          child: Icon(icon, size: WpIconSize.sm, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card view — responsive grid of entry cards
// ---------------------------------------------------------------------------

class _CardView extends StatelessWidget {
  const _CardView({
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
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 280.0;
        const gap = WpSpacing.md;
        const sidePad = WpSpacing.md;
        final availableWidth = constraints.maxWidth - sidePad * 2;
        final columns =
            (availableWidth / minCardWidth).floor().clamp(1, 4);
        final cardWidth =
            (availableWidth - gap * (columns - 1)) / columns;

        return ListView(
          padding: const EdgeInsets.only(
            top: WpSpacing.xs,
            bottom: WpSpacing.xxl,
          ),
          children: [
            for (final group in groups) ...[
              _DateHeader(label: group.label, isDark: isDark),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: sidePad),
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final entry in group.entries)
                      SizedBox(
                        width: cardWidth,
                        child: _EntryCard(
                          entry: entry,
                          isDark: isDark,
                          isSelected: entry.id == selectedId,
                          onTap: () => onEntryTap(entry),
                          onCopy: () => onCopy(entry),
                          onPin: () => onPin(entry),
                          onDelete: () => onDelete(entry),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Entry card — used in card grid view
// ---------------------------------------------------------------------------

class _EntryCard extends StatefulWidget {
  const _EntryCard({
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
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final avatarCol = _avatarColor(widget.entry, isDark);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surfaceElevated = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderColor = widget.isSelected
        ? accent.withValues(alpha: 0.5)
        : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          height: 180,
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: surfaceElevated,
            borderRadius: WpRadius.borderMd,
            border: Border.all(color: borderColor),
            boxShadow: _isHovered ? WpShadows.subtle : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: avatar + title + hover actions
              Row(
                children: [
                  _EntryAvatar(
                    color: avatarCol,
                    icon: _avatarIcon(widget.entry),
                    isPinned: widget.entry.pinned,
                    isDark: isDark,
                    size: 32,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.entry.title.isNotEmpty
                          ? widget.entry.title
                          : 'Untitled recording',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  // Hover action buttons
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
                      tooltip: widget.entry.pinned ? 'Unpin' : 'Pin',
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
                  ],
                ],
              ),
              const SizedBox(height: WpSpacing.xs),
              // Content preview (3-4 lines)
              Expanded(
                child: Text(
                  widget.entry.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              // Bottom metadata
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 10, color: textMuted),
                  const SizedBox(width: 3),
                  Text(
                    _formatDuration(widget.entry.durationSec),
                    style: TextStyle(fontSize: 10, color: textMuted),
                  ),
                  if (widget.entry.language.isNotEmpty) ...[
                    const SizedBox(width: WpSpacing.xs),
                    Text(
                      '·',
                      style: TextStyle(fontSize: 10, color: textMuted),
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
                  const Spacer(),
                  if (!widget.entry.isLocal)
                    Icon(LucideIcons.cloud, size: 10, color: textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact view — dense power-user list
// ---------------------------------------------------------------------------

class _CompactView extends StatelessWidget {
  const _CompactView({
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final group in groups) {
      items.add(_CompactDateHeader(label: group.label, isDark: isDark));
      for (final entry in group.entries) {
        items.add(
          _CompactRow(
            entry: entry,
            isDark: isDark,
            isSelected: entry.id == selectedId,
            onTap: () => onEntryTap(entry),
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
// Compact date header — minimal text-only header
// ---------------------------------------------------------------------------

class _CompactDateHeader extends StatelessWidget {
  const _CompactDateHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.xxs,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact row — single-line dense entry
// ---------------------------------------------------------------------------

class _CompactRow extends StatefulWidget {
  const _CompactRow({
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_CompactRow> createState() => _CompactRowState();
}

class _CompactRowState extends State<_CompactRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = Colors.transparent;
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
          margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              // Pin indicator
              if (widget.entry.pinned)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              // Title
              Expanded(
                child: Text(
                  widget.entry.title.isNotEmpty
                      ? widget.entry.title
                      : 'Untitled recording',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              // Duration
              Text(
                _formatDuration(widget.entry.durationSec),
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
              // Language
              if (widget.entry.language.isNotEmpty) ...[
                const SizedBox(width: WpSpacing.sm),
                Text(
                  widget.entry.language.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(width: WpSpacing.sm),
              // Time
              Text(
                _formatTime(widget.entry.timestamp),
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
