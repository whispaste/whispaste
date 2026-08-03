import 'package:flutter/material.dart';

import '../../../core/data/database.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'note_editor_panel.dart';
import 'notes_list_view.dart';

// ---------------------------------------------------------------------------
// Split-view layout — simplified from HistorySplitView (no view modes,
// no multi-select, no date groups): flat note list left, editor right.
// ---------------------------------------------------------------------------

class NotesSplitView extends StatefulWidget {
  const NotesSplitView({
    super.key,
    required this.notes,
    required this.tagsByNoteId,
    required this.isDark,
    required this.isTrashView,
    required this.selectedNote,
    required this.selectedNoteTags,
    required this.editorController,
    required this.editorFocusNode,
    required this.onNoteTap,
    required this.onCloseEditor,
    required this.onFavoriteToggle,
    required this.onMoveToTrash,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  final List<Note> notes;

  /// Note id → linked tags for the list tiles (from allNoteTagsProvider).
  final Map<String, List<Tag>> tagsByNoteId;
  final bool isDark;

  /// Whether the trash filter is active — swaps the per-note actions
  /// (favourite/trash vs. restore/delete-forever) in list tiles and editor.
  final bool isTrashView;
  final Note? selectedNote;

  /// Tags of the note currently open in the editor — resolved by the caller
  /// (noteTagsProvider), empty when no note is selected.
  final List<Tag> selectedNoteTags;

  /// Owned by `_NotesPageState` (NOT by the editor panel) so cursor and IME
  /// state survive rebuilds triggered by the notes stream.
  final TextEditingController editorController;
  final FocusNode editorFocusNode;
  final ValueChanged<Note> onNoteTap;
  final VoidCallback onCloseEditor;
  final ValueChanged<Note> onFavoriteToggle;
  final ValueChanged<Note> onMoveToTrash;
  final ValueChanged<Note> onRestore;
  final ValueChanged<Note> onDeleteForever;

  /// Add/remove a tag on the note currently open in the editor
  /// (tagName / tagId).
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  @override
  State<NotesSplitView> createState() => _NotesSplitViewState();
}

class _NotesSplitViewState extends State<NotesSplitView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _detailWidth;
  Note? _displayedNote;

  double _listWidth = _defaultListWidth;
  bool _isDragging = false;

  // Constants mirrored 1:1 from HistorySplitView so both split views feel
  // identical to resize and collapse.
  static const _defaultListWidth = 340.0;
  static const _minListWidth = 240.0;
  static const _maxListFraction = 0.65;
  static const _dividerHitWidth = 8.0;
  static const _dividerVisualWidth = 1.0;

  /// Minimum pixel width before the editor panel actually renders its content.
  /// Below this threshold, the panel shows nothing to prevent RenderFlex
  /// overflows during the open/close animation.
  static const _minDetailRenderWidth = 280.0;

  @override
  // loam-ignore: code-duplicates – mirrors HistorySplitView by design
  // (Struktur-Vorbild, not a shared abstraction, per the Ticket-02 plan:
  // both split views must feel identical to resize/collapse, and Notizen
  // must not take a feature-to-feature dependency on History).
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: WpMotion.smooth);
    _detailWidth = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    if (widget.selectedNote != null) {
      _displayedNote = widget.selectedNote;
      _anim.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _anim.duration = WpMotion.durationFor(context, WpMotion.smooth);
  }

  @override
  // loam-ignore: code-duplicates – mirrors HistorySplitView by design, see
  // initState above.
  void didUpdateWidget(covariant NotesSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedNote != null && oldWidget.selectedNote == null) {
      // Opening editor panel
      _displayedNote = widget.selectedNote;
      _anim.forward();
    } else if (widget.selectedNote == null && oldWidget.selectedNote != null) {
      // Closing editor panel
      _anim.reverse().then((_) {
        if (mounted) setState(() => _displayedNote = null);
      });
    } else if (widget.selectedNote != null) {
      // Switching to a different note (or same note updated by the stream)
      _displayedNote = widget.selectedNote;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _buildListBody({String? selectedId}) {
    return NotesListView(
      notes: widget.notes,
      tagsByNoteId: widget.tagsByNoteId,
      isDark: widget.isDark,
      isTrashView: widget.isTrashView,
      selectedId: selectedId,
      onNoteTap: widget.onNoteTap,
      onFavoriteToggle: widget.onFavoriteToggle,
      onRestore: widget.onRestore,
      onDeleteForever: widget.onDeleteForever,
    );
  }

  Widget _buildEditorPanel(Note note) {
    return NoteEditorPanel(
      key: ValueKey(note.id),
      note: note,
      tags: widget.selectedNoteTags,
      isDark: widget.isDark,
      controller: widget.editorController,
      focusNode: widget.editorFocusNode,
      onClose: widget.onCloseEditor,
      onToggleFavorite: () => widget.onFavoriteToggle(note),
      onMoveToTrash: () => widget.onMoveToTrash(note),
      onRestore: () => widget.onRestore(note),
      onDeleteForever: () => widget.onDeleteForever(note),
      onAddTag: widget.onAddTag,
      onRemoveTag: widget.onRemoveTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDetail = widget.selectedNote != null || _displayedNote != null;

    if (!showDetail) {
      return _buildListBody();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final isCompact = totalWidth < WpLayout.breakpointMobile;

        // ── Compact: full-screen editor overlay ──
        if (isCompact) {
          final note = widget.selectedNote ?? _displayedNote;
          if (note != null && widget.selectedNote != null) {
            return _buildEditorPanel(note);
          }
          return _buildListBody(
            selectedId: (widget.selectedNote ?? _displayedNote)?.id,
          );
        }

        // ── Desktop: side-by-side list + editor ──
        // When the editor is open, cap the list column so the editor gets at
        // least _minDetailRenderWidth. If there's not enough total space for
        // both panels, fall back to a full-screen editor.
        final roomForDetail = totalWidth - _minListWidth - _dividerHitWidth;
        if (roomForDetail < _minDetailRenderWidth &&
            widget.selectedNote != null) {
          return _buildEditorPanel(widget.selectedNote ?? _displayedNote!);
        }

        final maxListW = totalWidth * _maxListFraction;
        // Ensure the list column never eats so much that the editor can't
        // render.
        final maxListForDetail =
            totalWidth - _dividerHitWidth - _minDetailRenderWidth;
        return AnimatedBuilder(
          animation: _detailWidth,
          builder: (context, _) {
            final detailFraction = _detailWidth.value;
            final effectiveList = _listWidth.clamp(
              _minListWidth,
              detailFraction > 0.05
                  ? maxListForDetail.clamp(_minListWidth, maxListW)
                  : maxListW,
            );
            final detailW =
                (totalWidth - effectiveList - _dividerHitWidth) *
                detailFraction;
            final listW = totalWidth - detailW - _dividerHitWidth;

            return Row(
              children: [
                SizedBox(
                  width: listW.clamp(effectiveList, totalWidth),
                  child: _buildListBody(
                    selectedId: (widget.selectedNote ?? _displayedNote)?.id,
                  ),
                ),
                // Draggable divider
                _SplitViewDivider(
                  isDark: widget.isDark,
                  isDragging: _isDragging,
                  hitWidth: _dividerHitWidth,
                  visualWidth: _dividerVisualWidth,
                  dragMax: detailFraction > 0.05
                      ? maxListForDetail.clamp(_minListWidth, maxListW)
                      : maxListW,
                  minListWidth: _minListWidth,
                  currentListWidth: _listWidth,
                  onDragStart: () => setState(() => _isDragging = true),
                  onDragUpdate: (newWidth) =>
                      setState(() => _listWidth = newWidth),
                  onDragEnd: () => setState(() => _isDragging = false),
                ),
                SizedBox(
                  width: detailW.clamp(0.0, totalWidth - _minListWidth),
                  child:
                      detailFraction > 0.05 && detailW >= _minDetailRenderWidth
                      ? ClipRect(
                          child: Opacity(
                            opacity: detailFraction.clamp(0.0, 1.0),
                            child: _buildEditorPanel(
                              widget.selectedNote ?? _displayedNote!,
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

// ---------------------------------------------------------------------------
// Draggable column divider — mirrored from HistorySplitView's divider so
// both split views share the exact same resize affordance.
// ---------------------------------------------------------------------------

class _SplitViewDivider extends StatelessWidget {
  const _SplitViewDivider({
    required this.isDark,
    required this.isDragging,
    required this.hitWidth,
    required this.visualWidth,
    required this.dragMax,
    required this.minListWidth,
    required this.currentListWidth,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool isDark;
  final bool isDragging;
  final double hitWidth;
  final double visualWidth;
  final double dragMax;
  final double minListWidth;
  final double currentListWidth;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  // loam-ignore: code-duplicates – mirrors history_split_view.dart's
  // _SplitViewDivider by design, see NotesSplitView.initState above.
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: (details) {
          final newWidth = (currentListWidth + details.delta.dx).clamp(
            minListWidth,
            dragMax,
          );
          onDragUpdate(newWidth);
        },
        onHorizontalDragEnd: (_) => onDragEnd(),
        child: Container(
          width: hitWidth,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: WpMotion.durationFor(
                context,
                const Duration(milliseconds: 150),
              ),
              width: isDragging ? 3.0 : visualWidth,
              decoration: BoxDecoration(
                color: isDragging
                    ? (isDark
                          ? WpColorsDark.accent.withValues(alpha: 0.5)
                          : WpColorsLight.accent.withValues(alpha: 0.5))
                    : (isDark
                          ? WpColorsDark.borderSubtle
                          : WpColorsLight.borderSubtle),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
