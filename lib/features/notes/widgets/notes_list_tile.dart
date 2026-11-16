import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/data/content_metadata_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_collection_list_item.dart';
import '../../../widgets/wp_context_menu.dart';
import '../../../widgets/wp_list_item_content.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_row_action.dart';
import '../../../widgets/wp_row_checkbox.dart';
import '../data/note_search_snippet.dart';
import '../data/note_title.dart';

// ---------------------------------------------------------------------------
// Note list tile — the shared WpListItemContent row (#1498): derived title,
// content preview, relative date, plus the shared action cluster (Copy,
// Star, Delete in the active view; Copy, Restore, Delete forever in the
// trash view) and the permanent quick-note mark. Duplicate and setting the
// quick-note mark live in the context menu and the screen-reader actions.
// ---------------------------------------------------------------------------

class NotesListTile extends ConsumerStatefulWidget {
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
    this.onMoveToTrash,
    this.searchQuery = '',
    this.selecting = false,
  });

  final Note note;

  /// The active search term (blank outside a search). While set, the preview
  /// shows the excerpt around the first match in the text with the match
  /// marked (#872), instead of the note's opening lines.
  final String searchQuery;

  /// Tags linked to this note, alphabetically sorted (from
  /// allNoteTagsProvider). Purely informative in the tile — no tap handler.
  final List<Tag> tags;

  /// Trash view swaps Star and Delete for Restore and Delete forever.
  final bool isTrashView;
  final bool isSelected;

  /// Whether this tile is the list's virtual keyboard cursor (arrow-key
  /// navigation in NotesPage) — highlighted like a hover.
  final bool isFocused;

  /// Multi-select is on (#655): a leading checkbox mirrors [isSelected],
  /// which then means "checked" rather than "open in the editor".
  final bool selecting;
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

  /// Moves the note to the trash: the row's visible Delete action in the
  /// active view (`notes-delete-<id>`). Optional so lightweight hosts (tests,
  /// pickers) can omit it; the row then shows Copy alone.
  final VoidCallback? onMoveToTrash;

  @override
  ConsumerState<NotesListTile> createState() => _NotesListTileState();
}

class _NotesListTileState extends ConsumerState<NotesListTile> {
  // Memoized once per `note` change (initState + didUpdateWidget) — hover
  // rebuilds the row on every mouse enter/exit, and re-deriving title/preview from a potentially long content string on each
  // of those would be wasted work (same pattern as _HistoryEntryRowState).
  late String? _title = _titleOf(widget.note);
  late String _preview = _derivePreview(widget.note.content);
  late NoteSearchSnippet? _snippet = _snippetOf(
    widget.note,
    widget.searchQuery,
  );

  /// The excerpt around the first match below the shown title: when the
  /// title is the first content line, a match there is already visible in
  /// the title, so the excerpt looks for the next one after it.
  static NoteSearchSnippet? _snippetOf(Note note, String query) {
    if (query.trim().isEmpty) return null;
    final explicit = note.title?.trim();
    var from = 0;
    if (explicit == null || explicit.isEmpty) {
      final firstText = note.content.indexOf(RegExp(r'\S'));
      if (firstText >= 0) {
        final lineEnd = note.content.indexOf('\n', firstText);
        from = lineEnd < 0 ? note.content.length : lineEnd;
      }
    }
    return noteSearchSnippet(note.content, query, searchFrom: from);
  }

  /// The title shows one ellipsized line; the cap only bounds how much of
  /// the first line is derived. Only the display is capped here; the stored
  /// content is never touched.
  static const _titleMaxLength = 240;

  /// The explicit title when the note has one (ticket), otherwise the first
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
    // The keyboard cursor landing here (arrows, J/K, ↓/↑ from the search
    // field) scrolls the row into view, at whichever edge it left.
    if (widget.isFocused && !oldWidget.isFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });
    }
    if (oldWidget.note != widget.note) {
      _title = _titleOf(widget.note);
      _preview = _derivePreview(widget.note.content);
    }
    if (oldWidget.note != widget.note ||
        oldWidget.searchQuery != widget.searchQuery) {
      _snippet = _snippetOf(widget.note, widget.searchQuery);
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
    // formatHistoryTime would make notes depend on history, which internal-notes
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

  /// Right-click menu: the row's visible actions plus the two without a
  /// button of their own, Duplicate and setting the quick-note mark (one
  /// action set per row: Copy, Star, Delete; #1498). The menu items carry
  /// the former button keys, so flows still address them by id.
  List<WpContextMenuEntry> _contextMenu() {
    final l10n = L10n.of(context);
    final note = widget.note;
    final id = note.id;
    return [
      WpContextMenuEntry(
        icon: LucideIcons.copy,
        label: l10n.historyCopyText,
        onSelected: widget.onCopy,
      ),
      if (widget.onDuplicate case final onDuplicate?)
        WpContextMenuEntry(
          key: ValueKey('notes-duplicate-$id'),
          icon: LucideIcons.files,
          label: l10n.actionDuplicate,
          onSelected: onDuplicate,
        ),
      if (widget.isTrashView) ...[
        WpContextMenuEntry(
          icon: LucideIcons.undo2,
          label: l10n.notesRestore,
          onSelected: widget.onRestore,
        ),
        WpContextMenuEntry(
          icon: LucideIcons.trash2,
          label: l10n.notesDeleteForever,
          onSelected: widget.onDeleteForever,
          destructive: true,
        ),
      ] else ...[
        WpContextMenuEntry(
          icon: LucideIcons.star,
          label: WpFavouriteStar.labelFor(l10n, isFavourite: note.pinned),
          onSelected: widget.onFavoriteToggle,
        ),
        if (note.isQuickNote)
          WpContextMenuEntry(
            icon: LucideIcons.zapOff,
            label: l10n.notesQuickNoteClear,
            onSelected: widget.onQuickNoteClear,
          )
        else
          WpContextMenuEntry(
            key: ValueKey('notes-quick-note-set-$id'),
            icon: LucideIcons.zap,
            label: l10n.notesQuickNoteSet,
            onSelected: widget.onQuickNoteSet,
          ),
        if (widget.onMoveToTrash case final onMoveToTrash?)
          WpContextMenuEntry(
            icon: LucideIcons.trash2,
            label: l10n.notesMoveToTrash,
            onSelected: onMoveToTrash,
            destructive: true,
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      contentMetadataProvider((kind: ContentKind.note, id: widget.note.id)),
    );
    final l10n = L10n.of(context);
    final id = widget.note.id;
    final title = _title ?? l10n.notesUntitled;

    // The actions without a button: reachable from the context menu and,
    // because a screen reader cannot open a right-click menu, as custom
    // semantics actions on the row.
    final semanticsActions = <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(label: l10n.actionDuplicate): ?widget.onDuplicate,
      if (!widget.isTrashView && !widget.note.isQuickNote)
        CustomSemanticsAction(label: l10n.notesQuickNoteSet):
            widget.onQuickNoteSet,
    };

    // Deliberately no semantics label: the rendered title names the row (a
    // label would be prepended to it and announce the title twice), and
    // merging is ruled out because the actions and the quick-note mark are
    // tap targets of their own. No hint either: a note row opens nothing, it
    // selects, and `selected` already says so. `focused` exposes the list's
    // virtual keyboard cursor to screen readers.
    return WpCollectionListItem(
      contentKey: ValueKey('notes-row-content-$id'),
      semanticsIdentifier: 'notes-row-$id',
      semanticsFocused: widget.isFocused,
      customSemanticsActions: semanticsActions,
      typeIcon: LucideIcons.stickyNote,
      // Multi-select (#655): the same checkbox in the same slot as on the
      // recording rows; isSelected then means "checked".
      leading: widget.selecting
          ? WpRowCheckbox(
              key: ValueKey('notes-check-$id'),
              value: widget.isSelected,
              onChanged: widget.onTap,
              semanticsLabel: title,
            )
          : null,
      title: WpCollectionListItemTitle(
        title,
        key: ValueKey('notes-row-title-$id'),
      ),
      isFavourite: !widget.isTrashView && widget.note.pinned,
      favouriteMarkKey: ValueKey('notes-favourite-mark-$id'),
      favouriteMarkLabel: l10n.listItemFavouriteMark,
      marks: [
        if (!widget.isTrashView && widget.note.isQuickNote)
          // The quick-note mark, permanent and tappable because it is this
          // row's only carrier of the state (see WpRowAction's library
          // comment). Colour and glyph differ from the star on purpose: the
          // interaction accent on a bolt, the hotkey symbol. Setting the mark
          // lives in the context menu and the screen-reader actions, only on
          // notes that do not hold it, so "marking it again" is structurally
          // impossible.
          WpRowAction(
            key: ValueKey('notes-quick-note-clear-$id'),
            testId: 'notes-quick-note-clear-$id',
            faIcon: FontAwesomeIcons.bolt,
            activeColor: WpColors.accent,
            tooltip: l10n.notesQuickNoteClear,
            onTap: widget.onQuickNoteClear,
            dense: true,
          ),
      ],
      actions: (visible) => _buildActions(l10n, visible),
      preview: _buildPreview(title),
      previewSemanticsLabel: _spokenPreview(title),
      meta: (color) => WpListItemMeta(
        key: ValueKey('notes-row-meta-$id'),
        color: color,
        spans: [TextSpan(text: _relativeDateLabel(context))],
      ),
      // Compact tag pills, informative only (no tap).
      footer: widget.tags.isEmpty ? null : _NoteTagChips(tags: widget.tags),
      isFocused: widget.isFocused,
      isSelected: widget.isSelected,
      onTap: widget.onTap,
      contextMenu: _contextMenu,
    );
  }

  /// The screen-reader form of [_buildPreview]: the search excerpt as is, or
  /// a short excerpt of the body (#1498).
  String? _spokenPreview(String title) {
    if (_snippet case final s?) {
      return '${s.leadingCut ? '… ' : ''}${s.before}${s.match}'
          '${s.after}${s.trailingCut ? ' …' : ''}';
    }
    return WpListItemContent.spokenPreview(title, _preview);
  }

  /// Search excerpt or content preview, or null when there is nothing the
  /// title does not already say.
  Widget? _buildPreview(String title) {
    // Search: the excerpt around the first match, marked
    if (_snippet case final snippet?) {
      return _NoteSearchSnippetText(
        key: ValueKey('notes-search-snippet-${widget.note.id}'),
        snippet: snippet,
      );
    }
    // Content preview, hidden when the note is title-only or the body only
    // repeats the title
    if (!WpListItemContent.previewDiffers(title, _preview)) return null;
    return WpCollectionListItemPreview(
      _preview,
      key: ValueKey('notes-row-preview-${widget.note.id}'),
    );
  }

  /// The shared cluster at the end of the title line (#1498). Active view:
  /// Copy, Star, Delete (Delete moves the note to the trash, hence its
  /// label). Trash view: Copy, Restore, Delete forever.
  Widget _buildActions(L10n l10n, bool visible) {
    final id = widget.note.id;
    final copy = WpRowAction(
      key: ValueKey('notes-copy-$id'),
      testId: 'notes-copy-$id',
      icon: LucideIcons.copy,
      // One name for the row's Copy in all three lists (#1498).
      tooltip: l10n.historyCopyText,
      onTap: widget.onCopy,
      dense: true,
    );
    if (widget.isTrashView) {
      return WpListItemActions.trash(
        visible: visible,
        copy: copy,
        restore: WpRowAction(
          key: ValueKey('notes-restore-$id'),
          testId: 'notes-restore-$id',
          // Same restore glyph as the editor toolbar and history's per-item
          // restore action.
          icon: LucideIcons.undo2,
          tooltip: l10n.notesRestore,
          onTap: widget.onRestore,
          dense: true,
        ),
        delete: WpRowAction(
          key: ValueKey('notes-delete-forever-$id'),
          testId: 'notes-delete-forever-$id',
          icon: LucideIcons.trash2,
          tooltip: l10n.notesDeleteForever,
          onTap: widget.onDeleteForever,
          isDestructive: true,
          dense: true,
        ),
      );
    }
    final onMoveToTrash = widget.onMoveToTrash;
    return WpListItemActions(
      visible: visible,
      copy: copy,
      star: WpFavouriteStar(
        key: ValueKey('notes-favorite-$id'),
        testId: 'notes-favorite-$id',
        isFavourite: widget.note.pinned,
        onToggle: widget.onFavoriteToggle,
      ),
      // The one label that differs from the other lists on purpose: a note
      // is not deleted here but moved to the trash.
      delete: onMoveToTrash == null
          ? null
          : WpRowAction(
              key: ValueKey('notes-delete-$id'),
              testId: 'notes-delete-$id',
              icon: LucideIcons.trash2,
              tooltip: l10n.notesMoveToTrash,
              onTap: onMoveToTrash,
              isDestructive: true,
              dense: true,
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
            style: TextStyle(fontSize: WpTypography.caption, color: textMuted),
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
          fontSize: WpTypography.caption,
          color: accent.withValues(alpha: 0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Two-line excerpt of a search hit (#872). The match carries the amber
/// marker tokens (soft fill, amber text, semibold) so it stands out without
/// any added characters; screen readers read the plain excerpt.
class _NoteSearchSnippetText extends StatelessWidget {
  const _NoteSearchSnippetText({super.key, required this.snippet});

  final NoteSearchSnippet snippet;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${snippet.leadingCut ? '… ' : ''}${snippet.before}'),
          TextSpan(
            text: snippet.match,
            style: TextStyle(
              color: WpColors.highlightText,
              backgroundColor: WpColors.highlightSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: '${snippet.after}${snippet.trailingCut ? ' …' : ''}'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: WpCollectionListItem.previewStyle(),
    );
  }
}
