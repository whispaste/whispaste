import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import 'history_card_view.dart';
import 'history_compact_view.dart';
import 'history_detail_panel.dart';
import 'history_helpers.dart';
import 'history_list_view.dart';

// ---------------------------------------------------------------------------
// Master-detail layout
// ---------------------------------------------------------------------------

class HistoryMasterDetail extends StatefulWidget {
  const HistoryMasterDetail({
    super.key,
    required this.groups,
    required this.isDark,
    required this.viewMode,
    required this.selectedEntry,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.onCloseDetail,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    required this.isArchiveView,
    this.onDuplicate,
    this.onCopyMarkdown,
    this.focusedId,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final HistoryViewMode viewMode;
  final HistoryEntry? selectedEntry;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry> onArchive;
  final ValueChanged<HistoryEntry> onRestore;
  final VoidCallback onCloseDetail;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final bool isArchiveView;
  final ValueChanged<HistoryEntry>? onDuplicate;
  final ValueChanged<HistoryEntry>? onCopyMarkdown;
  final String? focusedId;

  @override
  State<HistoryMasterDetail> createState() => _HistoryMasterDetailState();
}

class _HistoryMasterDetailState extends State<HistoryMasterDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _detailWidth;
  HistoryEntry? _displayedEntry;

  double _masterWidth = _defaultMasterWidth;
  bool _isDragging = false;

  static const _defaultMasterWidth = 340.0;
  static const _minMasterWidth = 240.0;
  static const _maxMasterFraction = 0.65;
  static const _dividerHitWidth = 8.0;
  static const _dividerVisualWidth = 1.0;

  /// Minimum pixel width before the detail panel actually renders its content.
  /// Below this threshold, the panel shows nothing to prevent RenderFlex
  /// overflows during the open/close animation.
  static const _minDetailRenderWidth = 280.0;

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
  void didUpdateWidget(covariant HistoryMasterDetail oldWidget) {
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
    final Widget body;
    switch (widget.viewMode) {
      case HistoryViewMode.list:
        body = HistoryEntryList(
          key: const ValueKey('view-list'),
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          focusedId: widget.focusedId,
          onEntryTap: widget.onEntryTap,
          onCopy: widget.onCopy,
          onPin: widget.onPin,
          onDelete: widget.onDelete,
          multiSelectMode: widget.multiSelectMode,
          selectedIds: widget.selectedIds,
          isTrashView: widget.isTrashView,
        );
      case HistoryViewMode.cards:
        body = HistoryCardView(
          key: const ValueKey('view-cards'),
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          focusedId: widget.focusedId,
          onEntryTap: widget.onEntryTap,
          onCopy: widget.onCopy,
          onPin: widget.onPin,
          onDelete: widget.onDelete,
          multiSelectMode: widget.multiSelectMode,
          selectedIds: widget.selectedIds,
        );
      case HistoryViewMode.compact:
        body = HistoryCompactView(
          key: const ValueKey('view-compact'),
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          focusedId: widget.focusedId,
          onEntryTap: widget.onEntryTap,
          multiSelectMode: widget.multiSelectMode,
          selectedIds: widget.selectedIds,
        );
    }
    return AnimatedSwitcher(
      duration: WpMotion.normal,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: body,
    );
  }

  Widget _buildDetailPanel(HistoryEntry entry) {
    return HistoryDetailPanel(
      key: ValueKey(entry.id),
      entry: entry,
      isDark: widget.isDark,
      isTrashView: widget.isTrashView,
      isArchiveView: widget.isArchiveView,
      onClose: widget.onCloseDetail,
      onCopy: () => widget.onCopy(entry),
      onPin: () => widget.onPin(entry),
      onDelete: () => widget.onDelete(entry),
      onArchive: () => widget.onArchive(entry),
      onRestore: () => widget.onRestore(entry),
      onDuplicate:
          widget.onDuplicate == null ? null : () => widget.onDuplicate!(entry),
      onCopyMarkdown: widget.onCopyMarkdown == null
          ? null
          : () => widget.onCopyMarkdown!(entry),
    );
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
        final isCompact = totalWidth < WpLayout.breakpointMobile;

        // ── Compact / mobile: full-screen detail overlay ──
        if (isCompact) {
          final entry = widget.selectedEntry ?? _displayedEntry;
          if (entry != null && widget.selectedEntry != null) {
            return _buildDetailPanel(entry);
          }
          return _buildMasterBody(
            selectedId: (widget.selectedEntry ?? _displayedEntry)?.id,
          );
        }

        // ── Desktop: side-by-side master + detail ──
        // When detail is open, cap master so the detail gets at least
        // _minDetailRenderWidth. If there's not enough total space for
        // both panels, fall back to compact/fullscreen detail.
        final roomForDetail =
            totalWidth - _minMasterWidth - _dividerHitWidth;
        if (roomForDetail < _minDetailRenderWidth &&
            widget.selectedEntry != null) {
          // Not enough room for split — show full-screen detail.
          return _buildDetailPanel(
            widget.selectedEntry ?? _displayedEntry!,
          );
        }

        final maxMasterW = totalWidth * _maxMasterFraction;
        // Ensure master never eats so much that detail can't render.
        final maxMasterForDetail =
            totalWidth - _dividerHitWidth - _minDetailRenderWidth;
        return AnimatedBuilder(
          animation: _detailWidth,
          builder: (context, _) {
            final detailFraction = _detailWidth.value;
            final effectiveMaster = _masterWidth.clamp(
              _minMasterWidth,
              detailFraction > 0.05
                  ? maxMasterForDetail.clamp(_minMasterWidth, maxMasterW)
                  : maxMasterW,
            );
            final detailW =
                (totalWidth - effectiveMaster - _dividerHitWidth) *
                    detailFraction;
            final masterW = totalWidth - detailW - _dividerHitWidth;

            return Row(
              children: [
                SizedBox(
                  width: masterW.clamp(effectiveMaster, totalWidth),
                  child: _buildMasterBody(
                    selectedId: (widget.selectedEntry ?? _displayedEntry)?.id,
                  ),
                ),
                // Draggable divider
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) =>
                        setState(() => _isDragging = true),
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        final dragMax = detailFraction > 0.05
                            ? maxMasterForDetail.clamp(
                                _minMasterWidth, maxMasterW)
                            : maxMasterW;
                        _masterWidth = (_masterWidth + details.delta.dx)
                            .clamp(_minMasterWidth, dragMax);
                      });
                    },
                    onHorizontalDragEnd: (_) =>
                        setState(() => _isDragging = false),
                    child: Container(
                      width: _dividerHitWidth,
                      color: Colors.transparent,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: _isDragging ? 3.0 : _dividerVisualWidth,
                          decoration: BoxDecoration(
                            color: _isDragging
                                ? (widget.isDark
                                    ? WpColorsDark.accent.withValues(alpha: 0.5)
                                    : WpColorsLight.accent.withValues(alpha: 0.5))
                                : (widget.isDark
                                    ? WpColorsDark.borderSubtle
                                    : WpColorsLight.borderSubtle),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: detailW.clamp(0.0, totalWidth - _minMasterWidth),
                  child: detailFraction > 0.05 &&
                          detailW >= _minDetailRenderWidth
                      ? ClipRect(
                          child: Opacity(
                          opacity: detailFraction.clamp(0.0, 1.0),
                          child: AnimatedSwitcher(
                            duration: WpMotion.fast,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: _buildDetailPanel(
                              widget.selectedEntry ?? _displayedEntry!,
                            ),
                          ),
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
