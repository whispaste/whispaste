import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_list_tile_surface.dart';
import '../../../widgets/wp_row_action.dart';
import '../data/note_title.dart';

// ---------------------------------------------------------------------------
// Note list tile — simplified sibling of HistoryEntryRow: derived title,
// content preview, relative date, plus per-note actions (favourite star and
// the quick-note mark in the active view, restore/delete-forever in the trash
// view).
// ---------------------------------------------------------------------------

class NotesListTile extends StatefulWidget {
  const NotesListTile({
    super.key,
    required this.note,
    required this.tags,
    required this.isTrashView,
    required this.isSelected,
    required this.isFocused,
    required this.onTap,
    required this.onCopy,
    required this.onDuplicate,
    required this.onFavoriteToggle,
    required this.onQuickNoteSet,
    required this.onQuickNoteClear,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final Note note;

  /// Tags linked to this note, alphabetically sorted (from
  /// allNoteTagsProvider). Purely informative in the tile — no tap handler.
  final List<Tag> tags;

  /// Trash view swaps the leading favourite star for trailing
  /// restore/delete-forever actions.
  final bool isTrashView;
  final bool isSelected;

  /// Whether this tile is the list's virtual keyboard cursor (arrow-key
  /// navigation in NotesPage) — highlighted like a hover.
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback? onDuplicate;
  final VoidCallback onFavoriteToggle;

  /// Makes this note the quick note. Offered only while it is *not* already
  /// the quick note — re-marking a default value is a no-op, so the control
  /// simply isn't there (see the build method's comment).
  final VoidCallback onQuickNoteSet;

  /// Drops the quick-note mark entirely, leaving no note marked. A separate,
  /// separately named control in a separate place from [onQuickNoteSet].
  final VoidCallback onQuickNoteClear;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  State<NotesListTile> createState() => _NotesListTileState();
}

class _NotesListTileState extends State<NotesListTile> {
  bool _isHovered = false;

  // Memoized once per `note` change (initState + didUpdateWidget) — hover
  // toggles this tile's own setState on every mouse enter/exit, and
  // re-deriving title/preview from a potentially long content string on each
  // of those would be wasted work (same pattern as _HistoryEntryRowState).
  late String? _title = _titleOf(widget.note);
  late String _preview = _derivePreview(widget.note.content);

  /// The title may wrap to two lines, so it keeps far more of the first line
  /// than the editor's 80-character display cap does. Only the display is
  /// capped here; the stored content is never touched.
  static const _titleMaxLength = 240;

  /// The explicit title when the note has one (WP-31a), otherwise the first
  /// content line.
  static String? _titleOf(Note note) {
    final explicit = note.title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return deriveNoteTitle(note.content, maxLength: _titleMaxLength);
  }

  /// Cap for how much content the preview derivation scans — the preview
  /// shows at most two ellipsized lines, so scanning a multi-kilobyte note
  /// in full would be pure overhead.
  static const _previewScanLimit = 500;

  /// Everything after the first non-blank (title) line, blank lines dropped,
  /// joined into a single run for the two-line ellipsized preview.
  static String _derivePreview(String content) {
    final scanned = content.length > _previewScanLimit
        ? content.substring(0, _previewScanLimit)
        : content;
    var titleSeen = false;
    final rest = <String>[];
    for (final line in scanned.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!titleSeen) {
        titleSeen = true;
        continue;
      }
      rest.add(trimmed);
    }
    return rest.join(' ');
  }

  @override
  void didUpdateWidget(NotesListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note != widget.note) {
      _title = _titleOf(widget.note);
      _preview = _derivePreview(widget.note.content);
    }
  }

  /// Locale the two [DateFormat]s below were built for — empty until the
  /// first [didChangeDependencies] call, which always runs before the first
  /// [build] (see `_CollapsibleSectionState` in `section.dart` for the same
  /// context-dependent-caching pattern).
  String _dateFormatLocale = '';
  late DateFormat _monthDayFormat;
  late DateFormat _yearMonthDayFormat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `build()` re-runs on every hover toggle (see MouseRegion below), far
    // more often than the locale ever changes — constructing a fresh
    // DateFormat inside `_relativeDateLabel` on each of those calls was pure
    // per-frame allocation for a value only `didChangeDependencies` needs to
    // recompute.
    final locale = Localizations.localeOf(context).toString();
    if (locale != _dateFormatLocale) {
      _dateFormatLocale = locale;
      _monthDayFormat = DateFormat.MMMd(locale);
      _yearMonthDayFormat = DateFormat.yMMMd(locale);
    }
  }

  /// Label for [Note.updatedAt]: today shows the time (HH:MM); any other day
  /// shows the day in front of it, "Yesterday" or a short localized date (year
  /// only when it differs), e.g. "Yesterday · 14:20".
  String _relativeDateLabel(BuildContext context) {
    final t = widget.note.updatedAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    // Formats HH:MM locally on purpose: the history feature's
    // formatHistoryTime would make notes depend on history, which CONTEXT.md
    // §5.5 forbids. Keep both in step if the time format changes.
    final time =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    if (day == today) return time;
    final String date;
    if (day == today.subtract(const Duration(days: 1))) {
      date = L10n.of(context).historyYesterday;
    } else {
      date = t.year == now.year
          ? _monthDayFormat.format(t)
          : _yearMonthDayFormat.format(t);
    }
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final textPrimary = WpColors.textPrimary;
    final textSecondary = WpColors.textSecondary;
    final textMuted = WpColors.textMuted;

    final title = _title ?? l10n.notesUntitled;
    // Metadata drops from muted to secondary on any tinted row state: muted
    // text falls below 4.5:1 on the hover/selection washes (see DESIGN.md
    // contrast rules).
    final isTinted = _isHovered || widget.isSelected || widget.isFocused;

    return Semantics(
      // Deliberately no `label:`. It used to be `title` — the very string
      // this tile also renders as Text below — and a Semantics label is
      // *prepended* to its subtree's text rather than substituted for it, so
      // every row announced its title twice ("Mein Titel, Mein Titel, 14:20,
      // …"). The house alternative (MergeSemantics around a label-less
      // Semantics) is ruled out here: the favourite star is a permanently
      // mounted second tap target inside this subtree (and the quick-note
      // mark a third one on the marked note), and merging would swallow
      // them. Dropping the redundant label lets the rendered title name the
      // row and leaves each action its own operable node.
      //
      // No `hint:` either, unlike the Snippets/Replacements rows, which use
      // one to announce that activating them opens an edit dialog: a note
      // row opens nothing, it selects — and `selected:` below already says
      // so. That is the one justified difference between the three lists'
      // row announcements.
      button: true,
      selected: widget.isSelected,
      // The list owns keyboard focus as a single node and tracks the
      // "current" tile by id (see NotesPage's arrow-key navigation) —
      // exposing that here lets a screen reader announce which tile is
      // virtually focused instead of only showing a visual highlight.
      focused: widget.isFocused,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: WpListTileSurface(
            variant: WpListTileVariant.panel,
            isHovered: _isHovered,
            isFocused: widget.isFocused,
            isSelected: widget.isSelected,
            // The favourite star, the quick-note mark and the row actions form
            // the trailing group. They sit in the surface's actions slot, so the
            // body holds only the text and its metadata, and the 48 px touch
            // boxes set the row's minimum height instead of adding to its
            // padding (see WpListTileSurface's actions notes).
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isTrashView) ...[
                  // Deliberately exempt from the hover/focus reveal that
                  // trailing row actions follow (see WpRowAction's library
                  // comment): a note's favourite state has no other carrier in
                  // this list, so the star stays put and is always tappable.
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                  WpRowAction(
                    key: ValueKey('notes-favorite-${widget.note.id}'),
                    faIcon: widget.note.pinned
                        ? FontAwesomeIcons.solidStar
                        : FontAwesomeIcons.star,
                    activeColor: widget.note.pinned
                        ? WpSharedColors.pinnedAccent
                        : null,
                    tooltip: widget.note.pinned
                        ? l10n.notesUnfavorite
                        : l10n.notesFavorite,
                    onTap: widget.onFavoriteToggle,
                    dense: true,
                  ),
                  const SizedBox(width: WpSpacing.xxs),
                  if (widget.note.isQuickNote) ...[
                    // The quick-note mark, and the only way to drop it. Colour
                    // and glyph differ from the star on purpose: amber solid
                    // star vs. the interaction accent on a bolt, the hotkey
                    // symbol. Permanent, like the star, because it is this row's
                    // only carrier of the state. Setting the mark lives in the
                    // row actions below, only on notes that do not hold it.
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                    WpRowAction(
                      key: ValueKey('notes-quick-note-clear-${widget.note.id}'),
                      faIcon: FontAwesomeIcons.bolt,
                      activeColor: WpColors.accent,
                      tooltip: l10n.notesQuickNoteClear,
                      onTap: widget.onQuickNoteClear,
                      dense: true,
                    ),
                    const SizedBox(width: WpSpacing.xxs),
                  ],
                ],
                WpRowActions(
                  visible: _isHovered || widget.isFocused,
                  dense: true,
                  children: [
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                    WpRowAction(
                      key: ValueKey('notes-copy-${widget.note.id}'),
                      icon: LucideIcons.copy,
                      tooltip: l10n.notesCopy,
                      onTap: widget.onCopy,
                      dense: true,
                    ),
                    if (widget.onDuplicate case final onDuplicate?)
                      WpRowAction(
                        key: ValueKey('notes-duplicate-${widget.note.id}'),
                        icon: LucideIcons.files,
                        tooltip: l10n.actionDuplicate,
                        onTap: onDuplicate,
                        dense: true,
                      ),
                    if (!widget.isTrashView)
                      if (!widget.note.isQuickNote)
                        // Setting the mark is an ordinary trailing row action,
                        // revealed on hover/focus like every other one, and
                        // absent from the note that already holds the mark, so
                        // "marking it again" is structurally impossible instead
                        // of being a behavioural special case.
                        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                        WpRowAction(
                          key: ValueKey(
                            'notes-quick-note-set-${widget.note.id}',
                          ),
                          icon: LucideIcons.zap,
                          tooltip: l10n.notesQuickNoteSet,
                          onTap: widget.onQuickNoteSet,
                          dense: true,
                        ),
                    if (widget.isTrashView) ...[
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                      WpRowAction(
                        key: ValueKey('notes-restore-${widget.note.id}'),
                        // Same restore glyph as the editor toolbar and
                        // history's per-item restore action.
                        icon: LucideIcons.undo2,
                        tooltip: l10n.notesRestore,
                        onTap: widget.onRestore,
                        dense: true,
                      ),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                      WpRowAction(
                        key: ValueKey('notes-delete-forever-${widget.note.id}'),
                        icon: LucideIcons.trash2,
                        tooltip: l10n.notesDeleteForever,
                        onTap: widget.onDeleteForever,
                        isDestructive: true,
                        dense: true,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title, up to two lines
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: WpTypography.subheading,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                // Content preview, hidden when the note is title-only
                if (_preview.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WpTypography.body,
                      color: textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                // Update time as metadata, with the date for notes not from today
                const SizedBox(height: WpSpacing.xxs),
                Text(
                  _relativeDateLabel(context),
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: isTinted ? textSecondary : textMuted,
                  ),
                ),
                // Compact tag pills, informative only (no tap; tag filtering
                // may come in a later ticket)
                if (widget.tags.isNotEmpty) ...[
                  const SizedBox(height: WpSpacing.xxs),
                  _NoteTagChips(tags: widget.tags),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact, non-interactive tag pills — structural sibling of history's
// _EntryTagChips/_EntryTagChip: max. 3 visible chips + "+N" overflow count.
// ---------------------------------------------------------------------------

class _NoteTagChips extends StatelessWidget {
  const _NoteTagChips({required this.tags});

  final List<Tag> tags;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    final textMuted = WpColors.textMuted;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final tag in tags.take(3))
          _NoteTagChip(name: tag.name, accent: accent),
        if (tags.length > 3)
          Text(
            '+${tags.length - 3}',
            style: TextStyle(fontSize: WpTypography.micro, color: textMuted),
          ),
      ],
    );
  }
}

class _NoteTagChip extends StatelessWidget {
  const _NoteTagChip({required this.name, required this.accent});

  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Vertical 1 stays off-scale on purpose: the mini tag hugs its micro
      // text; xxs would double the chip height (same as history's mini tag).
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: WpColors.accentMiniTagFill,
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        '#$name',
        style: TextStyle(
          fontSize: WpTypography.micro,
          color: accent.withValues(alpha: 0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
