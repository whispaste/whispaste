import '../../core/data/content_metadata_providers.dart';
import '../../core/search/search_ranker.dart';

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/sorting/list_sort.dart';
import '../../core/sorting/list_sort_preference.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/snippet_picker/snippet_picker_controller.dart';
import '../../services/snippets/interactive_snippet_composer.dart';
import '../../services/snippets/snippet_file.dart';
import 'snippet_import_actions.dart';
import '../../services/snippets/snippets_exporter.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/config/command_shortcut.dart';
import '../../core/utils/focus_helpers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/wp_collection_list_pane.dart';
import '../../widgets/wp_collection_page.dart';
import '../../widgets/wp_collection_selection.dart';
import '../../widgets/wp_collection_split.dart';
import '../../widgets/wp_list_item_content.dart';
import '../../widgets/wp_list_skeleton.dart';
import '../../widgets/wp_search_field.dart';
import '../../widgets/wp_collection_list_item.dart';
import '../../widgets/wp_context_menu.dart';
import '../../widgets/wp_multi_select_bar.dart';
import '../../widgets/wp_favourite_star.dart';
import '../../widgets/wp_row_action.dart';
import '../../widgets/wp_row_checkbox.dart';
import '../../widgets/dialog.dart';
import '../../widgets/markdown_toolbar.dart';
import '../../widgets/wp_text_editor.dart';
import '../../widgets/list_reveal.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/wp_notice_bar.dart';
import '../../widgets/wp_accent_badge.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_sort_menu_button.dart';
import '../../widgets/wp_text_link.dart';
import '../../core/navigation/page_state.dart';

import 'package:whispaste/core/data/database.dart';

import '../../widgets/wp_copy_feedback.dart';
import '../../widgets/wp_tag_chip.dart';
import '../notes/widgets/note_tag_field.dart';
import '../notes/widgets/notes_bulk_tag_dialog.dart';
import 'snippet_draft.dart';
import 'snippet_filters.dart';
import 'snippet_item.dart';
import 'widgets/snippet_detail_panel.dart';
import 'widgets/snippet_editor.dart';
import 'widgets/snippet_insert_dialog.dart';

export 'snippet_filters.dart';
export 'snippet_item.dart';

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

class SnippetsNotifier extends AsyncNotifier<List<SnippetItem>>
    with ReloadableListNotifier<SnippetItem> {
  @override
  Future<List<SnippetItem>> readAll() async {
    final db = ref.read(historyDatabaseProvider);
    return (await db.readAllSnippetsWithFields()).map(_snippetFromDb).toList();
  }

  @override
  Future<List<SnippetItem>> build() => readAll();

  // Deliberately not further extracted: shares its "generate a uuid,
  // upsert, reload" shape with ReplacementsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  /// Creates a snippet and returns its id, so the page can reveal it.
  Future<String> add(
    String title,
    String body, {
    String kind = 'static',
    List<String> fields = const [],
  }) async {
    final db = ref.read(historyDatabaseProvider);
    final id = generateV4Uuid();
    await db.upsertSnippetWithFields(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      kind: kind,
      fieldNames: fields,
    );
    await reload();
    return id;
  }

  /// Writes the snippets of a file import in one transaction (#665): a write
  /// without id becomes a new snippet, one with id replaces that snippet's
  /// content. Returns the ids written, in order.
  Future<List<String>> importSnippets(List<SnippetImportWrite> writes) async {
    if (writes.isEmpty) return const [];
    final items = [
      for (final w in writes)
        (
          id: w.id ?? generateV4Uuid(),
          title: w.title,
          body: w.body,
          kind: w.kind,
          fields: w.fields,
        ),
    ];
    await ref
        .read(historyDatabaseProvider)
        .importSnippets(items, createdAt: DateTime.now());
    await reload();
    return [for (final i in items) i.id];
  }

  /// Counts one insertion of snippet [id] (copy on the page) and reloads, so
  /// the usage line and the "recently used" order follow at once.
  Future<void> recordUse(String id) async {
    await ref.read(historyDatabaseProvider).recordSnippetUse(id);
    await reload();
  }

  /// Edits a snippet. [createdAt] is the existing creation time; the database
  /// keeps the stored value whatever is passed.
  Future<void> updateSnippet(
    String id, {
    required String title,
    required String body,
    required DateTime createdAt,
    String kind = 'static',
    List<String> fields = const [],
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertSnippetWithFields(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      kind: kind,
      fieldNames: fields,
    );
    await reload();
  }

  /// Moves snippets to the trash. Nothing is lost: [restore] brings them back
  /// exactly as they were, and the retention sweep empties the trash later.
  Future<void> moveToTrash(List<String> ids) async {
    await ref.read(historyDatabaseProvider).trashSnippets(ids);
    await reload();
    ref.invalidate(snippetsTrashProvider);
  }

  /// Takes snippets out of the trash.
  Future<void> restore(List<String> ids) async {
    await ref.read(historyDatabaseProvider).restoreSnippetsFromTrash(ids);
    await reload();
    ref.invalidate(snippetsTrashProvider);
  }

  /// Stars or un-stars a snippet. Not an edit: "changed" keeps its time.
  Future<void> setFavourite(String id, {required bool value}) async {
    await ref
        .read(historyDatabaseProvider)
        .setSnippetFavorite(id, favorite: value);
    await reload();
  }

  /// Stars or un-stars several snippets with one reload.
  Future<void> setFavouriteMany(List<String> ids, {required bool value}) async {
    final db = ref.read(historyDatabaseProvider);
    for (final id in ids) {
      await db.setSnippetFavorite(id, favorite: value);
    }
    await reload();
  }

  /// Adds tag [name] to snippet [id] (#662), creating the tag when it does
  /// not exist yet — the same shared tags as on notes and recordings. A
  /// blank name changes nothing. Not an edit: "changed" keeps its time.
  /// The list follows through [allSnippetTagsProvider], no reload needed.
  Future<void> addTag(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = ref.read(historyDatabaseProvider);
    final tag = await db.createTag(trimmed);
    await db.tagSnippet(id, tag.id);
  }

  /// Takes tag [tagId] off snippet [id]; the tag itself stays.
  Future<void> removeTag(String id, String tagId) =>
      ref.read(historyDatabaseProvider).untagSnippet(id, tagId);

  /// Adds tag [name] to every snippet of [ids]. Returns the tag id and the
  /// snippets that did not carry it before — exactly what the undo
  /// ([removeTagFromMany]) takes away again. `null` for a blank name.
  Future<({String tagId, List<String> added})?> addTagToMany(
    List<String> ids,
    String name,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final db = ref.read(historyDatabaseProvider);
    final tag = await db.createTag(trimmed);
    final carried = await db.readAllSnippetTags();
    final added = <String>[];
    for (final id in ids) {
      if (carried[id]?.any((t) => t.id == tag.id) ?? false) continue;
      await db.tagSnippet(id, tag.id);
      added.add(id);
    }
    return (tagId: tag.id, added: added);
  }

  /// Takes tag [tagId] off every snippet of [ids].
  Future<void> removeTagFromMany(List<String> ids, String tagId) async {
    final db = ref.read(historyDatabaseProvider);
    for (final id in ids) {
      await db.untagSnippet(id, tagId);
    }
  }

  /// Gives snippet [to] every tag of snippet [from] (a duplicate keeps the
  /// original's tags, as a duplicated note does).
  Future<void> copyTags({required String from, required String to}) async {
    final db = ref.read(historyDatabaseProvider);
    for (final tag in await db.tagsForSnippet(from)) {
      await db.tagSnippet(to, tag.id);
    }
  }

  /// Permanently removes the given trashed snippets. Returns how many went.
  Future<int> deleteForever(List<String> ids) async {
    final removed = await ref
        .read(historyDatabaseProvider)
        .permanentlyDeleteTrashedSnippets(ids);
    ref.invalidate(snippetsTrashProvider);
    return removed;
  }

  /// Permanently removes every trashed snippet. Returns how many went.
  Future<int> emptyTrash() async {
    final removed = await ref
        .read(historyDatabaseProvider)
        .emptySnippetsTrash();
    ref.invalidate(snippetsTrashProvider);
    return removed;
  }

  /// Replaces the entire set of snippets with [items] — used by settings
  /// import (portability) so the imported file becomes the exact new
  /// contents rather than being merged with existing entries.
  // Deliberately not further extracted: shares its "clear, loop with an
  // index-ordered id, upsert, reload" shape with
  // ReplacementsNotifier.replaceAll; same closure-indirection trade-off as
  // [add] above, evaluated and rejected for the same reason.
  Future<void> replaceAll(List<SnippetItem> items) async {
    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    // One coordinated transaction: a failing row rolls back the delete too,
    // so the old library survives a broken import (UIA-SNP-01).
    await db.replaceAllSnippets([
      for (var i = 0; i < items.length; i++)
        (
          // Zero-padded, so ids of one import sort in import order too.
          id: '${now.millisecondsSinceEpoch}_${i.toString().padLeft(6, '0')}',
          title: items[i].title,
          body: items[i].body,
          kind: items[i].kind,
          fields: items[i].fields,
        ),
    ], createdAt: now);
    await reload();
  }
}

SnippetItem _snippetFromDb(SnippetWithFields row) => SnippetItem(
  id: row.row.id,
  title: row.row.title,
  body: row.row.body,
  createdAt: row.row.createdAt,
  updatedAt: row.row.updatedAt,
  kind: row.row.kind,
  fields: row.fields,
  isFavorite: row.row.isFavorite,
  useCount: row.row.useCount,
  lastUsedAt: row.row.lastUsedAt,
  sourceNoteId: row.row.sourceNoteId,
);

/// The snippets in the trash, most recently trashed first. Read-only: every
/// change goes through [SnippetsNotifier], which invalidates this provider.
final snippetsTrashProvider = FutureProvider<List<SnippetItem>>((ref) async {
  final db = ref.read(historyDatabaseProvider);
  return (await db.readTrashedSnippetsWithFields())
      .map(_snippetFromDb)
      .toList();
});

/// Opens the Textbaustein chooser over the library and inserts the pick's
/// body verbatim at the caret of [controller] (#664) — the same text the
/// page copies — then counts the use. A dismissed chooser only hands the
/// focus back to the editor.
Future<void> insertSnippetAtCursor({
  required BuildContext context,
  required WidgetRef ref,
  required TextEditingController controller,
  required FocusNode focusNode,
}) async {
  final items = await ref.read(snippetsProvider.future);
  if (!context.mounted) return;
  // Focus comes back from the chooser: the caret stays where it was (cancel)
  // or right after the inserted text, not at the end of the text. Marked
  // before the dialog opens, because the route may hand focus back itself.
  WpTextEditor.keepCaretOnNextFocus(controller);
  final picked = await pickSnippetForInsert(context, items);
  if (picked == null) {
    focusNode.requestFocus();
  } else {
    WpMarkdownFormatting(
      controller: controller,
      focusNode: focusNode,
    ).insertText(picked.body);
    unawaited(ref.read(snippetsProvider.notifier).recordUse(picked.id));
  }
  // The focus change runs in a microtask; after the frame the mark is spent
  // or was never needed.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => WpTextEditor.clearKeepCaret(controller),
  );
}

final snippetsProvider =
    AsyncNotifierProvider<SnippetsNotifier, List<SnippetItem>>(
      SnippetsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Page id of the snippets notice (see [WpPageNoticeSlot]).
const _noticePage = WpNoticePage.snippets;

/// Snippets page — named, multi-line text blocks kept in a separate settings
/// area from Replacements (dictation-automations ticket 05).
class SnippetsPage extends ConsumerStatefulWidget {
  const SnippetsPage({super.key});

  @override
  ConsumerState<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends ConsumerState<SnippetsPage>
    with WpListRevealMixin<SnippetsPage> {
  /// Kept for [_saveSnippet]: the editor also stores from its dispose(),
  /// when neither `ref` nor an ancestor lookup is allowed any more.
  late ProviderContainer _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  /// Active list, favourites only, or the trash (#662). Page-local on
  /// purpose: leaving the page lands on the active list again.
  SnippetsView _view = SnippetsView.active;

  bool get _trashView => _view == SnippetsView.trash;

  /// The tags the list is narrowed to: a snippet must carry all of them.
  /// Not remembered, like the notes' tag filter: a filter that outlives the
  /// session hides snippets the user forgot about.
  Set<String> _tagFilter = const {};

  void _showView(SnippetsView view) {
    if (_view == view) return;
    final enteringOrLeavingTrash =
        view == SnippetsView.trash || _view == SnippetsView.trash;
    setState(() {
      _view = view;
      // Favourites are a narrower look at the same list: the open snippet
      // and a running selection stay. The trash is another storage.
      if (enteringOrLeavingTrash) {
        _openId = null;
        _newSessionId = null;
        _leaveSelection();
      }
    });
  }

  void _showTrash(bool value) =>
      _showView(value ? SnippetsView.trash : SnippetsView.active);

  void _toggleTagFilter(String tagId) => setState(() {
    final next = {..._tagFilter};
    if (!next.remove(tagId)) next.add(tagId);
    _tagFilter = next;
  });

  /// Clears favourites-only and every tag, back to the whole active list.
  void _resetFilters() => setState(() {
    _tagFilter = const {};
    if (_view == SnippetsView.favourites) _view = SnippetsView.active;
  });

  /// Id of the snippet shown in the detail beside the list, or null.
  String? _openId;

  /// Id of the snippet created by the editor that is still open: it keeps
  /// the new-snippet editor's identity, so the first autosave does not
  /// remount the pane under the user's caret (#1498).
  String? _newSessionId;

  /// Counts the new-snippet editors opened on this page. Part of the new
  /// editor's identity, so "+" always mounts a fresh, empty editor: before
  /// (#1680), "+" right after creating a snippet kept the editor of the
  /// created one (same identity), which still showed its text and kept
  /// saving into it.
  int _newEditorSession = 0;

  /// The detail's identity: a just-created snippet stays the new editor.
  String _detailId(SnippetItem s) => snippetDetailIdentity(
    s.id,
    newSessionId: _newSessionId,
    newEditorSession: _newEditorSession,
  );

  /// Pre-fill of a new snippet picked from an example chip, or null.
  SnippetDraft? _newTemplate;

  void _open(SnippetItem s) => setState(() {
    if (_openId != s.id) _newSessionId = null;
    _openId = s.id;
  });

  void _closeDetail() => setState(() {
    _openId = null;
    _newSessionId = null;
    _newTemplate = null;
  });

  /// Selection mode on or off from the toolbar's select toggle.
  void _toggleSelecting() => setState(() {
    if (_selecting) {
      _leaveSelection();
    } else {
      _selecting = true;
    }
  });

  // ── Selection ─────────────────────────────────────────────────────────

  /// Selection mode: the rows show a checkbox and one bar offers the actions
  /// for all marked snippets. Only in the active list, never in the trash.
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Ids the list shows right now (set while building). A selection that a
  /// search has hidden is kept but never acted on.
  List<SnippetItem> _visible = const [];

  void _leaveSelection() {
    _selecting = false;
    _selected.clear();
    _rangeAnchorId = null;
  }

  /// The row a Shift+click range starts from (the last row marked by hand).
  String? _rangeAnchorId;

  void _toggleSelect(SnippetItem s) {
    // The unsaved new-snippet row is no snippet yet: nothing to select.
    if (s.id == kNewSnippetDraftKey) return;
    setState(() {
      _selecting = true;
      if (!_selected.remove(s.id)) _selected.add(s.id);
      _rangeAnchorId = s.id;
    });
  }

  /// Shift+click (#1858): marks every visible row between the range anchor
  /// and [s], as in the recordings and notes lists.
  void _selectRange(SnippetItem s) {
    final ids = [for (final v in _visible) v.id];
    final to = ids.indexOf(s.id);
    if (to < 0) return;
    var from = _rangeAnchorId == null ? -1 : ids.indexOf(_rangeAnchorId!);
    if (from < 0) from = to;
    final start = from < to ? from : to;
    final end = from < to ? to : from;
    setState(() {
      _selecting = true;
      _selected.addAll(ids.sublist(start, end + 1));
      _rangeAnchorId ??= s.id;
    });
  }

  /// Ctrl/Cmd+A (#1858): marks every snippet the list shows (the current
  /// search included) and opens the selection mode. Not in the trash.
  void _selectAllVisible() {
    if (_trashView || _visible.isEmpty) return;
    setState(() {
      _selecting = true;
      _selected.addAll(_visible.map((s) => s.id));
    });
  }

  List<SnippetItem> get _chosen => [
    for (final s in _visible)
      if (_selected.contains(s.id)) s,
  ];

  /// Esc leaves the selection first, then closes the detail (the editor
  /// answers Esc itself while it has focus).
  bool _onEscape() {
    if (_selecting) {
      setState(_leaveSelection);
      return true;
    }
    if (_openId != null) {
      _closeDetail();
      return true;
    }
    return false;
  }

  void _toggleSelectAll() {
    setState(() {
      if (_chosen.length >= _visible.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_visible.map((s) => s.id));
      }
    });
  }

  Widget? _selectionBar(BuildContext context, List<SnippetItem> visible) {
    _visible = [
      for (final s in visible)
        if (s.id != kNewSnippetDraftKey) s,
    ];
    if (!_selecting || _trashView) return null;
    final l10n = L10n.of(context);
    final chosen = _chosen;
    final has = chosen.isNotEmpty;
    final allStarred = has && chosen.every((s) => s.isFavorite);
    return WpMultiSelectBar(
      idPrefix: 'snippets-multiselect',
      selectedCount: chosen.length,
      totalCount: _visible.length,
      isTrashView: false,
      isArchiveView: false,
      onSelectAll: _toggleSelectAll,
      onCancelSelection: () => setState(_leaveSelection),
      onDelete: _trashSelected,
      onExport: _exportSelected,
      onTag: _tagSelected,
      onFavourite: () => _starSelected(!allStarred),
      favouriteLabel: allStarred
          ? l10n.snippetsBulkUnstar
          : l10n.snippetsBulkStar,
      favouriteIcon: allStarred ? LucideIcons.starOff : LucideIcons.star,
    );
  }

  Future<void> _trashSelected() async {
    final ids = [for (final s in _chosen) s.id];
    if (ids.isEmpty) return;
    final notifier = ref.read(snippetsProvider.notifier);
    final l10n = L10n.of(context);
    try {
      await notifier.moveToTrash(ids);
    } catch (_) {
      _writeFailed('delete-failed', l10n.snippetsDeleteFailed);
      return;
    }
    if (!mounted) return;
    setState(_leaveSelection);
    showWpNotice(
      context,
      WpNotice(
        id: 'snippets-trashed',
        kind: WpNoticeKind.undo,
        message: l10n.snippetsBulkMovedToTrash(ids.length),
        actionLabel: l10n.snippetsUndo,
        actionTestId: 'snippets-undo',
        onAction: () async {
          try {
            await notifier.restore(ids);
          } catch (_) {
            _writeFailed('restore-failed', l10n.snippetsRestoreFailed);
          }
        },
      ),
    );
  }

  Future<void> _starSelected(bool value) async {
    final ids = [for (final s in _chosen) s.id];
    if (ids.isEmpty) return;
    final l10n = L10n.of(context);
    try {
      await ref
          .read(snippetsProvider.notifier)
          .setFavouriteMany(ids, value: value);
    } catch (_) {
      _writeFailed('bulk-failed', l10n.snippetsBulkFailed);
      return;
    }
    if (!mounted) return;
    setState(_leaveSelection);
    _confirm(
      'bulk-starred',
      value
          ? l10n.snippetsBulkStarred(ids.length)
          : l10n.snippetsBulkUnstarred(ids.length),
    );
  }

  /// Asks for a tag and adds it to every marked snippet, as on Notizen.
  /// Undo takes it only from the snippets that did not carry it before.
  Future<void> _tagSelected() async {
    final ids = [for (final s in _chosen) s.id];
    if (ids.isEmpty) return;
    final l10n = L10n.of(context);
    final name = await showNotesBulkTagDialog(
      context,
      count: ids.length,
      title: l10n.snippetsBulkTagTitle(ids.length),
      idPrefix: 'snippets-bulk-tag',
    );
    if (name == null || !mounted) return;
    final notifier = ref.read(snippetsProvider.notifier);
    final ({String tagId, List<String> added})? result;
    try {
      result = await notifier.addTagToMany(ids, name);
    } catch (_) {
      _writeFailed('bulk-failed', l10n.snippetsBulkFailed);
      return;
    }
    if (result == null || !mounted) return;
    setState(_leaveSelection);
    showWpNotice(
      context,
      WpNotice(
        id: 'snippets-tagged',
        kind: WpNoticeKind.undo,
        message: l10n.snippetsBulkTagged(ids.length, name.trim().toLowerCase()),
        actionLabel: l10n.snippetsUndo,
        actionTestId: 'snippets-undo',
        onAction: () async {
          try {
            await notifier.removeTagFromMany(result!.added, result.tagId);
          } catch (_) {
            _writeFailed('bulk-failed', l10n.snippetsBulkFailed);
          }
        },
      ),
    );
  }

  static SnippetExportRow _exportRow(SnippetItem s) => (
    id: s.id,
    title: s.title,
    body: s.body,
    kind: s.kind,
    fields: s.fields,
    changedAt: s.updatedAt ?? s.createdAt,
  );

  Future<void> _exportSelected() async {
    final rows = [for (final s in _chosen) _exportRow(s)];
    final done = await const SnippetsExporter().exportSnippets(context, rows);
    if (done && mounted) setState(_leaveSelection);
  }

  /// Exports one snippet from its context menu (#665), without entering the
  /// selection mode.
  Future<void> _exportOne(SnippetItem s) async {
    await const SnippetsExporter().exportSnippets(context, [_exportRow(s)]);
  }

  /// A file dropped on the page imports like the toolbar button (#665).
  /// The first Markdown or JSON file of the drop counts; the trash view
  /// takes no imports.
  void _onDropDone(DropDoneDetails details, {required bool inTrash}) {
    if (inTrash) return;
    for (final item in details.files) {
      if (isSnippetImportFileName(item.name)) {
        unawaited(importSnippetsFile(context, ref, file: item));
        return;
      }
    }
    if (details.files.isNotEmpty) {
      showWpPageNotice(
        context,
        page: _noticePage,
        notice: WpPageNotice(
          id: 'snippets-import-refused',
          message: L10n.of(context).snippetsImportRefusedFormat,
          nextStep: L10n.of(context).snippetsImportNextPickFile,
        ),
      );
    }
  }

  /// A tap on a row: with Ctrl/Cmd held, or while selecting, it marks the row;
  /// otherwise it shows the snippet in the detail beside the list.
  void _onRowTap(SnippetItem s) {
    final keys = HardwareKeyboard.instance;
    if (s.id != kNewSnippetDraftKey &&
        !_trashView &&
        keys.isShiftPressed &&
        (_selecting || _rangeAnchorId != null)) {
      _selectRange(s);
    } else if (s.id != kNewSnippetDraftKey &&
        (_selecting || keys.isControlPressed || keys.isMetaPressed)) {
      _toggleSelect(s);
    } else {
      _open(s);
    }
  }

  Future<void> _chooseSort(ListSort sort) => saveListSort(
    context,
    save: () => ref.read(snippetsSortProvider.notifier).choose(sort),
    orderLabel: (l10n) => _sortOrderLabel(l10n, sort),
  );

  String _sortOrderLabel(L10n l10n, ListSort sort) => wpSortOrderLabel(
    l10n,
    fieldLabel: _fieldLabel(l10n, sort.field),
    isDate:
        sort.field == ListSortField.added ||
        sort.field == ListSortField.changed ||
        sort.field == ListSortField.used,
    reversed: sort.reversed,
  );

  String _fieldLabel(L10n l10n, ListSortField field) => switch (field) {
    ListSortField.added => l10n.listSortFieldAdded,
    ListSortField.changed => l10n.listSortFieldChanged,
    ListSortField.used => l10n.listSortFieldUsed,
    // Not offered by this list; the title is the list's own name for it.
    ListSortField.title ||
    ListSortField.trigger ||
    ListSortField.result ||
    ListSortField.order => l10n.listSortFieldTitle,
  };

  /// Search, keyboard cursor and bare keys of the list (#1498): the same
  /// controller as on Recordings and Notes, so the keys behave alike.
  final _selection = WpCollectionSelection<SnippetItem>(debugLabel: 'snippets');

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    // A search hit that navigated here (#628) is already set when the page
    // mounts, so `ref.listen` in build() would never see it change.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenTarget());
  }

  /// Consumes a pending jump to one snippet ([snippetsOpenTargetProvider])
  /// and shows it beside the active list, with the list search cleared so
  /// its row is visible.
  void _applyOpenTarget() {
    if (!mounted) return;
    final id = ref.read(snippetsOpenTargetProvider);
    if (id == null) return;
    ref.read(snippetsOpenTargetProvider.notifier).set(null);
    _selection.clearSearch();
    setState(() {
      // Filters cleared too, so the snippet's row is visible.
      _view = SnippetsView.active;
      _tagFilter = const {};
      _leaveSelection();
      if (_openId != id) _newSessionId = null;
      _openId = id;
    });
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection
      ..removeListener(_onSelectionChanged)
      ..dispose();
    super.dispose();
  }

  /// Title, tags (#662) and text, the notes' order of relevance.
  static List<SearchField> Function(SnippetItem) _searchFields(
    Map<String, List<Tag>> tagsBySnippetId,
  ) =>
      (s) => [
        SearchField(s.title, SearchWeight.title),
        if (tagsBySnippetId[s.id] case final tags? when tags.isNotEmpty)
          SearchField(tags.map((t) => t.name).join(' '), SearchWeight.tag),
        SearchField(s.body, SearchWeight.body),
      ];

  /// A snippet row is 87 dp, not the single-line default (its body preview
  /// takes two lines) — measured, see `WpListSkeleton.rowHeight`.
  static const double _skeletonRowHeight = 87;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Narrowed to the one field this page renders: `settingsProvider` emits
    // on every settings write anywhere in the app, and watching the whole
    // value here rebuilt this entire page (list included) for changes that
    // have nothing to do with the picker trigger.
    final trigger =
        ref.watch(
          settingsProvider.select(
            (s) => s.value?.behavior.snippetPickerTrigger,
          ),
        ) ??
        '';
    // `?? true` while the list is still loading — the "trigger does nothing
    // yet" warning must not flash before the first read lands.
    final hasSnippets = ref.watch(snippetsProvider).value?.isNotEmpty ?? true;
    final sortAsync = ref.watch(snippetsSortProvider);
    final sort = sortAsync.value ?? kSnippetsDefaultSort;
    // Loading until the saved sort is read, so the default never flashes.
    final trashAsync = ref.watch(snippetsTrashProvider);
    final trashCount = trashAsync.value?.length ?? 0;
    final trashDays =
        ref.watch(settingsProvider).value?.history.historyAutoTrashDays ??
        AppSettings.defaults.history.historyAutoTrashDays;
    final inTrash = _trashView;
    // Only which snippets have a draft (and the new draft's title for its
    // row) rebuilds the page, not every keystroke in the editor.
    final draftKeys = ref.watch(
      snippetDraftsProvider.select(
        (m) => (
          keys: (m.keys.toList()..sort()).join('\n'),
          newTitle: m[kNewSnippetDraftKey]?.title,
        ),
      ),
    );
    final draftIds = draftKeys.keys.isEmpty
        ? const <String>{}
        : draftKeys.keys.split('\n').toSet();
    // An unsaved new snippet shows as the list's first row while it is open
    // or has a draft, so a closed editor never hides typed text.
    final showNewDraft =
        !inTrash &&
        (_openId == kNewSnippetDraftKey ||
            draftIds.contains(kNewSnippetDraftKey));
    final tagsBySnippetId =
        ref.watch(allSnippetTagsProvider).value ?? const <String, List<Tag>>{};
    final activeItems = ref.watch(snippetsProvider).value ?? const [];
    // Only tags an active snippet carries are offered; a chosen tag that
    // none carries any more stops filtering.
    final tagsInUse = snippetTagsInUse(activeItems, tagsBySnippetId);
    final tagFilter = _tagFilter.intersection({
      for (final t in tagsInUse) t.id,
    });
    final favouritesOnly = _view == SnippetsView.favourites;
    final filtering = !inTrash && (favouritesOnly || tagFilter.isNotEmpty);
    final asyncAll = inTrash
        ? trashAsync
        : sortAsync.isLoading && !sortAsync.hasValue
        ? const AsyncValue<List<SnippetItem>>.loading()
        : ref
              .watch(snippetsProvider)
              .whenData(
                (items) => [
                  if (showNewDraft) _newDraftItem(l10n),
                  ...favouritesFirst(
                    filterSnippets(
                      sortListItems(items, sort),
                      favouritesOnly: favouritesOnly,
                      tagIds: tagFilter,
                      tagsBySnippetId: tagsBySnippetId,
                    ),
                  ),
                ],
              );

    final all = asyncAll.value ?? const <SnippetItem>[];
    final visible = asyncAll.hasValue
        ? _selection.filter(all, _searchFields(tagsBySnippetId))
        : const <SnippetItem>[];
    final cursorItem = _selection.cursorItem(visible);
    SnippetItem? open;
    for (final s in all) {
      if (s.id == _openId) {
        open = s;
        break;
      }
    }
    final selectionBar = asyncAll.hasValue
        ? _selectionBar(context, visible)
        : null;

    // A search hit may arrive while the page is already open.
    ref.listen<String?>(snippetsOpenTargetProvider, (_, id) {
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenTarget());
      }
    });
    // Dropping a Markdown or JSON file imports it (#665).
    return DropTarget(
      onDragDone: (details) => _onDropDone(details, inTrash: inTrash),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          commandActivator(LogicalKeyboardKey.keyN): _startNew,
          commandActivator(LogicalKeyboardKey.keyA): () {
            // In the search or the editor, Ctrl/Cmd+A selects the text.
            if (isTextFieldFocused()) return;
            _selectAllVisible();
          },
        },
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: (_, event) => _selection.handleKey(
            event,
            visible: visible,
            // Enter shows the snippet beside the list, in the trash too
            // (restore sits on the detail's header and on the row).
            onActivate: (s) =>
                _selecting && !inTrash ? _toggleSelect(s) : _open(s),
            onDelete: (s) => _deleteFromList(s, inTrash: inTrash),
            onToggleSelect: inTrash ? null : _toggleSelect,
            onEscape: _onEscape,
          ),
          child: WpCollectionPage(
            screenId: 'snippets',
            searchFocusNode: _selection.searchFocusNode,
            selectionBar: selectionBar,
            notices: const [WpPageNoticeSlot(page: _noticePage)],
            toolbar: _toolbar(
              l10n,
              inTrash: inTrash,
              hasSnippets: hasSnippets,
              trashCount: trashCount,
              sort: sort,
              tagsInUse: tagsInUse,
              tagFilter: tagFilter,
            ),
            body: WpCollectionSplit<SnippetItem>(
              selectedItem: open,
              idOf: _detailId,
              detailBuilder: (context, s) => _detail(
                s,
                inTrash: inTrash,
                tags: tagsBySnippetId[_storedIdOf(s)] ?? const [],
              ),
              listBuilder: (context, _) => WpCollectionListPane<SnippetItem>(
                storageKey: 'snippets-list',
                copyTargetPrefix: 'snippet',
                focusNode: _selection.listFocusNode,
                focusedId: cursorItem?.id,
                revealId: revealedId,
                rows: [for (final s in visible) WpCollectionItemRow(s.id, s)],
                itemBuilder: (context, s) => _row(
                  l10n,
                  s,
                  isCursor: s.id == cursorItem?.id,
                  inTrash: inTrash,
                  draftIds: draftIds,
                  tags: tagsBySnippetId[s.id] ?? const [],
                ),
                placeholder: _placeholder(
                  l10n,
                  asyncAll,
                  visible: visible,
                  inTrash: inTrash,
                  trashDays: trashDays,
                  trigger: trigger,
                  filtering: filtering,
                  hasSnippets: activeItems.isNotEmpty,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What stands in for the rows: loading, error, empty, no matches; null
  /// while there are rows to show.
  Widget? _placeholder(
    L10n l10n,
    AsyncValue<List<SnippetItem>> asyncAll, {
    required List<SnippetItem> visible,
    required bool inTrash,
    required int trashDays,
    required String trigger,
    required bool filtering,
    required bool hasSnippets,
  }) {
    return asyncAll.when<Widget?>(
      loading: () => const WpListSkeleton(
        rowHeight: _skeletonRowHeight,
        padding: EdgeInsets.symmetric(vertical: WpSpacing.xs),
      ),
      error: (_, _) => WpEmptyState(
        icon: LucideIcons.triangleAlert,
        title: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        actionTestId: 'list-retry',
        onAction: () => ref.invalidate(snippetsProvider),
      ),
      data: (all) {
        // Favourites-only or a tag filter left nothing over (#662): say so
        // and offer the way back, never the "no snippets yet" page.
        if (all.isEmpty && filtering && hasSnippets) {
          return WpEmptyState(
            key: const ValueKey('snippets-filter-empty'),
            icon: _view == SnippetsView.favourites
                ? LucideIcons.star
                : LucideIcons.tag,
            title: l10n.snippetsFilterEmptyTitle,
            hint: l10n.snippetsFilterEmptyHint,
            actionLabel: l10n.snippetsFilterReset,
            actionTestId: 'snippets-filter-reset',
            onAction: _resetFilters,
          );
        }
        if (all.isEmpty) {
          // Like Recordings and Notes, the page explains itself here and
          // nowhere above the rows: once snippets exist, the list starts
          // right under the search (#1498).
          return WpEmptyState(
            icon: LucideIcons.notebookText,
            motif: inTrash ? null : WpEmptyMotif.snippets,
            title: inTrash ? l10n.snippetsTrashEmpty : l10n.snippetsEmpty,
            hint: inTrash
                ? l10n.snippetsTrashEmptyHint(trashDays)
                : l10n.snippetsEmptyHint,
            actionLabel: l10n.snippetsAdd,
            actionTestId: 'list-empty-add',
            onAction: _startNew,
            // Teaches by example: each chip only pre-fills the editor,
            // nothing is stored until Save, and the list never shows
            // placeholder rows. The picker link follows, because a trigger
            // word without snippets does nothing yet.
            footer: inTrash
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SnippetExampleChips(onPick: _startNew),
                      const SizedBox(height: WpSpacing.lg),
                      _SnippetPickerSettingsLink(
                        showEmptyListHint: trigger.trim().isNotEmpty,
                      ),
                    ],
                  ),
          );
        }
        if (visible.isEmpty) {
          return WpEmptyState.searchNoMatches(
            query: _selection.query,
            testId: 'snippets-search-clear',
            onClear: _selection.clearSearch,
          );
        }
        return null;
      },
    );
  }

  /// Toolbar places (page family). One row (#1201): the two views live in
  /// the filter popover, the trash shows as a removable mark; "Empty trash"
  /// is the trash's view-bound action, select and sort are the tools.
  Widget _toolbar(
    L10n l10n, {
    required bool inTrash,
    required bool hasSnippets,
    required int trashCount,
    required ListSort sort,
    required List<Tag> tagsInUse,
    required Set<String> tagFilter,
  }) {
    final sortOptions = _sortOptions(l10n);
    final favouritesOnly = _view == SnippetsView.favourites;
    return WpCollectionToolbar(
      screenId: 'snippets',
      search: WpSearchField(
        testId: 'snippets-search',
        clearOnEscape: true,
        controller: _selection.searchController,
        focusNode: _selection.searchFocusNode,
        hintText: l10n.snippetsSearch,
        variant: WpSearchFieldVariant.outlined,
        onChanged: _selection.setQuery,
        semanticsLabel: l10n.snippetsSearchFieldLabel,
      ),
      primaryAction: Semantics(
        identifier: 'snippets-add',
        child: WpIconButton(
          icon: LucideIcons.plus,
          tooltip: l10n.snippetsAdd,
          onPressed: _startNew,
        ),
      ),
      filterSections: [
        WpFilterSection(
          id: 'view',
          label: l10n.collectionFilterShow,
          children: [
            WpFilterChip(
              testId: 'snippets-filter-active',
              label: l10n.navSnippets,
              icon: LucideIcons.notebookText,
              isActive: _view == SnippetsView.active,
              onTap: () => _showView(SnippetsView.active),
            ),
            WpFilterChip(
              testId: 'snippets-filter-favourites',
              label: l10n.snippetsFilterFavourites,
              icon: LucideIcons.star,
              isActive: favouritesOnly,
              onTap: () => _showView(SnippetsView.favourites),
            ),
            WpFilterChip(
              testId: 'snippets-filter-trash',
              label: l10n.snippetsTrash,
              icon: LucideIcons.trash2,
              isActive: inTrash,
              count: trashCount > 0 ? trashCount : null,
              onTap: () => _showTrash(true),
            ),
          ],
        ),
        // The same tag filter as on Notizen (#662): a snippet must carry
        // every chosen tag. The trash has no tags to filter by.
        if (!inTrash && tagsInUse.isNotEmpty)
          WpFilterSection(
            id: 'tags',
            label: l10n.notesTagFilterLabel,
            children: [
              for (final tag in tagsInUse)
                WpFilterChip(
                  testId: 'snippets-tag-filter-${tag.id}',
                  label: tag.name,
                  icon: LucideIcons.tag,
                  isActive: tagFilter.contains(tag.id),
                  onTap: () => _toggleTagFilter(tag.id),
                ),
            ],
          ),
      ],
      activeFilters: [
        if (inTrash)
          WpActiveFilter(
            id: 'view',
            label: l10n.snippetsTrash,
            onRemove: () => _showTrash(false),
          ),
        if (favouritesOnly)
          WpActiveFilter(
            id: 'view',
            label: l10n.snippetsFilterFavourites,
            onRemove: () => _showView(SnippetsView.active),
          ),
        if (!inTrash)
          for (final tag in tagsInUse)
            if (tagFilter.contains(tag.id))
              WpActiveFilter(
                id: 'tag-${tag.id}',
                label: '#${tag.name}',
                onRemove: () => _toggleTagFilter(tag.id),
              ),
      ],
      status: [
        if (inTrash && trashCount > 0)
          WpButton(
            testId: 'snippets-empty-trash',
            label: l10n.snippetsEmptyTrash,
            icon: LucideIcons.trash2,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.danger,
            size: WpButtonSize.dense,
            onPressed: _confirmEmptyTrash,
          ),
      ],
      tools: [
        if (!inTrash && hasSnippets)
          // Every toolbar control is the bordered icon button (#1498);
          // `selected` makes it the toggle and announces its state.
          WpIconButton(
            testId: 'snippets-select-toggle',
            icon: _selecting ? LucideIcons.checkCheck : LucideIcons.listChecks,
            tooltip: l10n.snippetsSelectMode,
            selected: _selecting,
            onPressed: _toggleSelecting,
          ),
        if (!inTrash)
          WpSortMenuButton<ListSortField>(
            testId: 'snippets-sort',
            tooltip: l10n.listSortMenuTooltip(_sortOrderLabel(l10n, sort)),
            current: sort.field,
            options: sortOptions,
            onChanged: (field) => _chooseSort(ListSort(field)),
            reversed: sort.reversed,
            reverseLabel: l10n.listSortReverse,
            onReversedChanged: (reversed) =>
                _chooseSort(ListSort(sort.field, reversed: reversed)),
          ),
        if (!inTrash)
          WpIconButton(
            testId: 'snippets-import',
            icon: LucideIcons.fileUp,
            tooltip: l10n.snippetsImportAction,
            onPressed: () => importSnippetsFile(context, ref),
          ),
      ],
      // On a narrow row the tools fold into one button on the same row.
      toolsOverflow: inTrash
          ? null
          : Builder(
              builder: (buttonContext) => WpIconButton(
                testId: 'snippets-tools-more',
                icon: LucideIcons.ellipsis,
                tooltip: l10n.dockOverflow,
                onPressed: () => showWpListMenu(buttonContext, [
                  if (hasSnippets)
                    WpListMenuAction(
                      itemKey: const ValueKey('snippets-select-mode'),
                      label: l10n.snippetsSelectMode,
                      icon: LucideIcons.listChecks,
                      checked: _selecting,
                      onSelected: _toggleSelecting,
                    ),
                  for (final option in sortOptions)
                    WpListMenuAction(
                      itemKey: ValueKey('snippets-sort-${option.id}'),
                      label: option.label,
                      icon: option.icon,
                      checked: option.value == sort.field,
                      onSelected: () => _chooseSort(ListSort(option.value)),
                    ),
                  WpListMenuAction(
                    itemKey: const ValueKey('snippets-import-menu'),
                    label: l10n.snippetsImportAction,
                    icon: LucideIcons.fileUp,
                    onSelected: () => importSnippetsFile(context, ref),
                  ),
                ]),
              ),
            ),
    );
  }

  static List<WpSortOption<ListSortField>> _sortOptions(L10n l10n) => [
    WpSortOption(
      value: ListSortField.title,
      id: 'title',
      label: l10n.listSortFieldTitle,
      icon: LucideIcons.type,
    ),
    WpSortOption(
      value: ListSortField.added,
      id: 'added',
      label: l10n.listSortFieldAdded,
      icon: LucideIcons.calendarPlus,
    ),
    WpSortOption(
      value: ListSortField.changed,
      id: 'changed',
      label: l10n.listSortFieldChanged,
      icon: LucideIcons.pencilLine,
    ),
    WpSortOption(
      value: ListSortField.used,
      id: 'used',
      label: l10n.listSortFieldUsed,
      icon: LucideIcons.history,
    ),
  ];

  void _deleteFromList(SnippetItem s, {required bool inTrash}) {
    if (inTrash) {
      _confirmDeleteForever(s);
    } else if (s.id == kNewSnippetDraftKey) {
      _confirmDiscardNewDraft();
    } else if (_selecting && _selected.contains(s.id)) {
      _trashSelected();
    } else {
      _moveToTrashWithUndo(s);
    }
  }

  Widget _row(
    L10n l10n,
    SnippetItem s, {
    required bool isCursor,
    required bool inTrash,
    required Set<String> draftIds,
    List<Tag> tags = const [],
  }) {
    if (inTrash) {
      return _SnippetRow(
        key: ValueKey('snippets-trash-row-${s.id}'),
        snippet: s,
        tags: tags,
        isCursor: isCursor,
        isOpen: s.id == _openId,
        onTap: () => _open(s),
        actions: (visible) => WpListItemActions.trash(
          visible: visible,
          restore: WpRowAction(
            key: ValueKey('snippets-restore-${s.id}'),
            testId: 'snippets-restore-${s.id}',
            icon: LucideIcons.undo2,
            tooltip: l10n.snippetsRestore,
            onTap: () => _restoreFromTrash(s),
            dense: true,
          ),
          delete: WpRowAction(
            key: ValueKey('snippets-delete-forever-${s.id}'),
            testId: 'snippets-delete-forever-${s.id}',
            icon: LucideIcons.trash2,
            tooltip: l10n.snippetsDeleteForever,
            onTap: () => _confirmDeleteForever(s),
            isDestructive: true,
            dense: true,
          ),
        ),
      );
    }
    if (s.id == kNewSnippetDraftKey) {
      return _SnippetRow(
        key: const ValueKey('snippets-draft-row'),
        snippet: s,
        isCursor: isCursor,
        isOpen: s.id == _openId,
        badges: [
          WpAccentBadge(
            label: l10n.snippetsDraftBadge,
            tone: WpAccentBadgeTone.highlight,
          ),
        ],
        onTap: () => _open(s),
        // The unsaved new snippet: nothing to copy or star yet, only the
        // Delete slot, which discards the draft.
        actions: (visible) => WpListItemActions(
          visible: visible,
          delete: WpRowAction(
            key: const ValueKey('snippets-draft-discard'),
            testId: 'snippets-draft-discard',
            icon: LucideIcons.trash2,
            tooltip: l10n.unsavedInputDiscard,
            onTap: _confirmDiscardNewDraft,
            isDestructive: true,
            dense: true,
          ),
        ),
      );
    }
    final id = s.id;
    final isSelected = _selected.contains(id);
    // Delete/Backspace on a focused row, the delete action and the menu all
    // move the row (or the checked set it belongs to) to the trash, with an
    // undo notice, the same promise as Notizen.
    void delete() =>
        _selecting && isSelected ? _trashSelected() : _moveToTrashWithUndo(s);
    return _SnippetRow(
      key: ValueKey('snippets-row-$id'),
      snippet: s,
      tags: tags,
      isCursor: isCursor,
      isHighlighted: id == highlightedId,
      isOpen: id == _openId,
      isSelected: isSelected,
      leading: _selecting
          ? WpRowCheckbox(
              key: ValueKey('snippets-select-$id'),
              value: isSelected,
              semanticsLabel: l10n.snippetsSelectRow(s.title),
              onChanged: () => _onRowTap(s),
            )
          : null,
      badges: [
        if (s.isInteractive)
          WpAccentBadge(label: l10n.snippetsInteractiveBadge),
        if (draftIds.contains(id))
          WpAccentBadge(
            key: ValueKey('snippets-draft-badge-$id'),
            label: l10n.snippetsDraftBadge,
            tone: WpAccentBadgeTone.highlight,
          ),
      ],
      showFavourite: true,
      showUsage: true,
      onTap: () => _onRowTap(s),
      onDeleteKey: delete,
      onDuplicate: () => _duplicateSnippet(s),
      // The row's actions plus Duplicate, which has no button of its own
      // (one action set per row: Copy, Star, Delete; #1498).
      contextMenu: () => [
        if (!s.isInteractive)
          WpContextMenuEntry(
            icon: LucideIcons.copy,
            label: l10n.historyCopyText,
            onSelected: () => _copySnippet(s),
          ),
        WpContextMenuEntry(
          key: ValueKey('snippets-duplicate-$id'),
          icon: LucideIcons.files,
          label: l10n.actionDuplicate,
          onSelected: () => _duplicateSnippet(s),
        ),
        WpContextMenuEntry(
          icon: LucideIcons.star,
          label: WpFavouriteStar.labelFor(l10n, isFavourite: s.isFavorite),
          onSelected: () => _toggleFavourite(s),
        ),
        if (s.id != kNewSnippetDraftKey)
          WpContextMenuEntry(
            key: ValueKey('snippets-export-$id'),
            icon: LucideIcons.fileDown,
            label: l10n.actionExport,
            onSelected: () => _exportOne(s),
          ),
        WpContextMenuEntry(
          icon: LucideIcons.trash2,
          label: l10n.actionDelete,
          onSelected: delete,
          destructive: true,
        ),
      ],
      actions: (visible) => WpListItemActions(
        visible: visible,
        // A copy has nothing to copy for an interactive snippet: its body
        // is a template, the composed text only exists after recording.
        copy: s.isInteractive
            ? null
            : WpRowAction(
                key: ValueKey('snippets-copy-$id'),
                testId: 'snippets-copy-$id',
                icon: LucideIcons.copy,
                tooltip: l10n.historyCopyText,
                onTap: () => _copySnippet(s),
                dense: true,
              ),
        star: WpFavouriteStar(
          key: ValueKey('snippets-favourite-$id'),
          testId: 'snippets-favourite-$id',
          isFavourite: s.isFavorite,
          onToggle: () => _toggleFavourite(s),
        ),
        delete: WpRowAction(
          key: ValueKey('snippets-delete-$id'),
          testId: 'snippets-delete-$id',
          icon: LucideIcons.trash2,
          tooltip: l10n.actionDelete,
          onTap: delete,
          isDestructive: true,
          dense: true,
        ),
      ),
    );
  }

  // ── Editor (in the detail, no dialog — #864) ─────────────────────────

  /// Stores the editor's valid state (#1498: autosave, Ctrl/Cmd+S, close).
  /// Returns the snippet's id, or null when the write fails, so the editor
  /// keeps the typed text and says so (UIA-SNP-02). A new snippet is created
  /// once; while its editor stays open it keeps the new editor's identity.
  /// The draft is cleared only when it is exactly the stored state.
  Future<String?> _saveSnippet(
    SnippetItem? existing,
    SnippetDraft draft,
  ) async {
    final container = _container;
    final notifier = container.read(snippetsProvider.notifier);
    final drafts = container.read(snippetDraftsProvider.notifier);
    try {
      final String id;
      if (existing != null) {
        id = existing.id;
        // A save without a change is no edit: "changed" keeps its old time.
        if (!_isUnchanged(existing, draft)) {
          await notifier.updateSnippet(
            existing.id,
            title: draft.title,
            body: draft.body,
            createdAt: existing.createdAt,
            kind: draft.kind,
            fields: draft.fields,
          );
        }
      } else {
        id = await notifier.add(
          draft.title,
          draft.body,
          kind: draft.kind,
          fields: draft.fields,
        );
        if (container
                .read(snippetDraftsProvider)[kNewSnippetDraftKey]
                ?.stored ==
            draft) {
          drafts.clear(kNewSnippetDraftKey);
        }
        if (mounted) {
          setState(() {
            _newTemplate = null;
            // The editor stays where the user writes; it now edits the
            // created snippet.
            if (_openId == kNewSnippetDraftKey) {
              _openId = id;
              _newSessionId = id;
            }
          });
          reveal(id);
        }
        container
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'snippets', action: 'create');
      }
      if (container.read(snippetDraftsProvider)[id]?.stored == draft) {
        drafts.clear(id);
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  /// The row standing for the unsaved new snippet: the draft as typed, or
  /// the picked example before the first keystroke.
  SnippetItem _newDraftItem(L10n l10n) {
    final draft =
        ref.read(snippetDraftsProvider)[kNewSnippetDraftKey] ??
        _newTemplate ??
        const SnippetDraft();
    final title = draft.title.trim();
    return SnippetItem(
      id: kNewSnippetDraftKey,
      title: title.isEmpty ? l10n.snippetsNewSnippet : title,
      body: draft.body,
      createdAt: DateTime.now(),
      kind: draft.kind,
      fields: draft.fields,
    );
  }

  static bool _isUnchanged(SnippetItem existing, SnippetDraft draft) =>
      existing.title == draft.title &&
      existing.body == draft.body &&
      existing.kind == draft.kind &&
      listEquals(existing.fields, draft.fields);

  /// Opens the editor for a new snippet, optionally pre-filled by an example
  /// chip. An unsaved new draft wins over the template: it is restored, never
  /// overwritten.
  void _startNew([SnippetDraft? template]) {
    setState(() {
      if (_view == SnippetsView.trash) _view = SnippetsView.active;
      _leaveSelection();
      _newTemplate = template;
      _newSessionId = null;
      _openId = kNewSnippetDraftKey;
      _newEditorSession++;
    });
  }

  /// The new-snippet row's delete action: the draft goes after a
  /// confirmation, the same question the editor's discard button asks.
  Future<void> _confirmDiscardNewDraft() async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.unsavedInputTitle,
      message: l10n.unsavedInputMessage,
      confirmLabel: l10n.unsavedInputDiscard,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    ref.read(snippetDraftsProvider.notifier).clear(kNewSnippetDraftKey);
    if (_openId == kNewSnippetDraftKey) _closeDetail();
  }

  /// The stored snippet behind a detail: the created one while the new
  /// editor stays open, null for a never stored new snippet.
  String? _storedIdOf(SnippetItem s) =>
      s.id == kNewSnippetDraftKey ? _newSessionId : s.id;

  Future<void> _addTag(String id, String name) async {
    final message = L10n.of(context).snippetsTagFailed;
    try {
      await ref.read(snippetsProvider.notifier).addTag(id, name);
    } catch (_) {
      _writeFailed('tag-failed', message);
    }
  }

  Future<void> _removeTag(String id, String tagId) async {
    final message = L10n.of(context).snippetsTagFailed;
    try {
      await ref.read(snippetsProvider.notifier).removeTag(id, tagId);
    } catch (_) {
      _writeFailed('tag-failed', message);
    }
  }

  /// The tag field of the editor (#662): the notes' field with the same
  /// suggestions of the shared tags. A new snippet gets it after its first
  /// save, when there is a snippet to tag. Read-only in the trash.
  Widget? _tagField(
    L10n l10n,
    SnippetItem s,
    List<Tag> tags, {
    bool readOnly = false,
  }) {
    final id = _storedIdOf(s);
    if (id == null) return null;
    return Semantics(
      container: true,
      identifier: 'snippets-editor-tags',
      child: NoteTagField(
        // Keyed per snippet: a half-typed tag must not ride along to the
        // next snippet, where Enter would file it.
        key: ValueKey('snippets-editor-tags-$id'),
        tags: tags,
        onAdd: (name) => unawaited(_addTag(id, name)),
        onRemove: (tagId) => unawaited(_removeTag(id, tagId)),
        hintText: l10n.notesAddTag,
        searchHintText: l10n.notesTagPlaceholder,
        readOnly: readOnly,
      ),
    );
  }

  Widget _detail(
    SnippetItem s, {
    required bool inTrash,
    List<Tag> tags = const [],
  }) {
    final l10n = L10n.of(context);
    if (inTrash) {
      return SnippetDetailPanel(
        key: ValueKey('snippets-detail-${s.id}'),
        snippet: s,
        onClose: _closeDetail,
        onRestore: () {
          _closeDetail();
          _restoreFromTrash(s);
        },
        onDeleteForever: () => _confirmDeleteForever(s),
        tags: tags.isEmpty ? null : _tagField(l10n, s, tags, readOnly: true),
      );
    }
    // No read view, no edit mode (#1498): the snippet opens in its editor,
    // written in directly, like a note.
    final isNew = s.id == kNewSnippetDraftKey;
    return SnippetEditor(
      key: ValueKey('snippets-editor-${_detailId(s)}'),
      onInsertSnippet: (controller, focusNode) => unawaited(
        insertSnippetAtCursor(
          context: context,
          ref: ref,
          controller: controller,
          focusNode: focusNode,
        ),
      ),
      existing: isNew ? null : s,
      template: isNew ? _newTemplate : null,
      tags: _tagField(l10n, s, tags),
      onSave: (draft) {
        // The created snippet once the first save of a new one is through.
        SnippetItem? current;
        if (!isNew) current = s;
        final createdId = _newSessionId;
        if (isNew && createdId != null) {
          current = ref
              .read(snippetsProvider)
              .value
              ?.where((i) => i.id == createdId)
              .firstOrNull;
        }
        return _saveSnippet(current, draft);
      },
      onClose: _closeDetail,
      onCopy: (text) => _copySnippet(s, text: text),
      onToggleFavourite: () => _toggleFavourite(s),
      onDuplicate: () => _duplicateSnippet(s),
      onDelete: () {
        _closeDetail();
        _moveToTrashWithUndo(s);
      },
    );
  }

  // ── Copy action ──────────────────────────────────────────────────────

  void _copySnippet(SnippetItem snippet, {String? text}) {
    unawaited(ref.read(snippetsProvider.notifier).recordUse(snippet.id));
    unawaited(
      copyWithFeedback(
        context,
        text: text ?? snippet.body,
        target: 'snippet-${snippet.id}',
        category: 'snippets',
      ),
    );
  }

  Future<void> _duplicateSnippet(SnippetItem item) async {
    final id = await ref
        .read(snippetsProvider.notifier)
        .add(
          '${item.title} ${L10n.of(context).snippetCopySuffix}',
          item.body,
          kind: item.kind,
          fields: item.fields,
        );
    await ref.read(snippetsProvider.notifier).copyTags(from: item.id, to: id);
    if (!mounted) return;
    // Confirms at the original row and marks the copy in place; no scroll,
    // so the list stays where the pointer is.
    confirmAtTrigger(context, target: 'snippet-${item.id}');
    highlight(id);
  }

  // ── Trash ─────────────────────────────────────────────────────────────

  void _writeFailed(String id, String message) {
    if (!mounted) return;
    showWpPageNotice(
      context,
      page: _noticePage,
      notice: WpPageNotice(id: id, message: message),
    );
  }

  /// A done action without a way back: it shows in the notice bar at the
  /// bottom and closes itself, so the list keeps its place (#1903).
  void _confirm(String id, String message) {
    if (!mounted) return;
    showWpConfirmation(context, id: 'snippets-$id', message: message);
  }

  Future<void> _toggleFavourite(SnippetItem s) async {
    final l10n = L10n.of(context);
    try {
      await ref
          .read(snippetsProvider.notifier)
          .setFavourite(s.id, value: !s.isFavorite);
    } catch (_) {
      _writeFailed('favourite-failed', l10n.snippetsFavouriteFailed);
    }
  }

  /// Moves to the trash at once and offers undo, like the notes and history
  /// lists: a misclick costs nothing, and a confirmation dialog would not help
  /// someone who confirms by reflex. The trash is the second net: the snippet
  /// stays recoverable after the undo is gone and after a restart.
  Future<void> _moveToTrashWithUndo(SnippetItem s) async {
    final notifier = ref.read(snippetsProvider.notifier);
    final l10n = L10n.of(context);
    try {
      await notifier.moveToTrash([s.id]);
    } catch (_) {
      _writeFailed('delete-failed', l10n.snippetsDeleteFailed);
      return;
    }
    if (!mounted) return;
    showWpNotice(
      context,
      WpNotice(
        id: 'snippets-trashed',
        kind: WpNoticeKind.undo,
        message: l10n.snippetsMovedToTrash(s.title),
        actionLabel: l10n.snippetsUndo,
        actionTestId: 'snippets-undo',
        onAction: () async {
          try {
            await notifier.restore([s.id]);
          } catch (_) {
            // Without this the failure would be an unhandled async error and
            // the user would believe the snippet came back.
            _writeFailed('restore-failed', l10n.snippetsRestoreFailed);
          }
        },
      ),
    );
  }

  Future<void> _restoreFromTrash(SnippetItem s) async {
    final l10n = L10n.of(context);
    try {
      await ref.read(snippetsProvider.notifier).restore([s.id]);
    } catch (_) {
      _writeFailed('restore-failed', l10n.snippetsRestoreFailed);
      return;
    }
    if (!mounted) return;
    _confirm('restored', l10n.snippetsRestored(s.title));
  }

  Future<void> _confirmDeleteForever(SnippetItem s) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.snippetsDeleteForeverConfirm,
      message: l10n.snippetsDeleteForeverMessage(s.title),
      confirmLabel: l10n.snippetsDeleteForever,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(snippetsProvider.notifier).deleteForever([s.id]);
    } catch (_) {
      _writeFailed('delete-failed', l10n.snippetsDeleteFailed);
    }
  }

  Future<void> _confirmEmptyTrash() async {
    final l10n = L10n.of(context);
    // The count of what the purge will take, not of what a search leaves
    // visible.
    final pending = ref.read(snippetsTrashProvider).value?.length ?? 0;
    if (pending == 0) return;
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.snippetsEmptyTrashConfirm,
      message: l10n.snippetsEmptyTrashMessage(pending),
      confirmLabel: l10n.snippetsEmptyTrash,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(snippetsProvider.notifier).emptyTrash();
    } catch (_) {
      _writeFailed('delete-failed', l10n.snippetsDeleteFailed);
    }
  }
}

// ---------------------------------------------------------------------------
// Settings link for the picker (UX-030)
// ---------------------------------------------------------------------------

/// The link in the empty list's footer that leads to the Settings row for the
/// spoken trigger word and the picker hotkey.
///
/// Both are global settings that change rarely, so they live in General ›
/// Tastenkürzel. The page names them only while the list is empty, like every
/// collection page keeps its explanation in the empty state (#1498); with
/// snippets, the list starts right under the search bar. Where the platform has no native picker, the page says
/// so and offers no link: there is nothing to set.
class _SnippetPickerSettingsLink extends ConsumerWidget {
  const _SnippetPickerSettingsLink({required this.showEmptyListHint});

  /// True when a trigger word is set: shown only on the empty list, where the
  /// trigger does nothing yet, which this page must say out loud.
  final bool showEmptyListHint;

  /// Text measure of the empty state's hint, so both read as one block.
  static const double _measure = 300;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final available = ref.watch(snippetPickerAvailabilityProvider);

    // Sits in the centred empty state, under the example chips: centred
    // text in the hint's measure.
    final style = TextStyle(
      color: WpColors.textMuted,
      fontSize: WpTypography.small,
      height: 1.4,
    );
    return SizedBox(
      width: _measure,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showEmptyListHint)
            Padding(
              padding: const EdgeInsets.only(bottom: WpSpacing.xs),
              child: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: WpSpacing.xs,
                        ),
                        child: Icon(
                          LucideIcons.triangleAlert,
                          size: WpIconSize.xs,
                          color: WpColors.warning,
                        ),
                      ),
                    ),
                    TextSpan(text: l10n.snippetsPickerTriggerEmptyListHint),
                  ],
                ),
                textAlign: TextAlign.center,
                style: style.copyWith(color: WpColors.warning),
              ),
            ),
          if (available)
            WpTextLink(
              label: l10n.snippetsPickerSettingsLink,
              kind: WpLinkKind.page,
              testID: 'snippets-picker-settings-link',
              onPressed: () => _openPickerSettings(ref),
            )
          else
            // Deliberately no link: there is nothing to set. Same sentence as
            // in Settings.
            Text(
              l10n.snippetsPickerUnavailable,
              key: const Key('snippetsPickerUnavailable'),
              textAlign: TextAlign.center,
              style: style,
            ),
        ],
      ),
    );
  }

  /// Opens Settings at the trigger-word row, the same way other pages hand a
  /// row over.
  void _openPickerSettings(WidgetRef ref) {
    ref
        .read(settingsScrollTargetProvider.notifier)
        .set('general-snippet-picker-trigger');
    ref.read(activePageProvider.notifier).setPage('settings');
  }
}

// ---------------------------------------------------------------------------
// Empty-state examples
// ---------------------------------------------------------------------------

/// Example chips in the empty snippet list plus the sentence on when a
/// snippet fits better than a replacement. A chip opens the editor for a new
/// snippet pre-filled with its example; nothing is stored until the user saves.
class _SnippetExampleChips extends StatelessWidget {
  const _SnippetExampleChips({required this.onPick});

  final ValueChanged<SnippetDraft> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final first = l10n.snippetsExampleInteractiveField1;
    final second = l10n.snippetsExampleInteractiveField2;
    final examples = <(String, String, SnippetDraft)>[
      (
        'signature',
        l10n.snippetsExampleSignatureTitle,
        SnippetDraft(
          title: l10n.snippetsExampleSignatureTitle,
          body: l10n.snippetsExampleSignatureBody,
        ),
      ),
      (
        'reply',
        l10n.snippetsExampleReplyTitle,
        SnippetDraft(
          title: l10n.snippetsExampleReplyTitle,
          body: l10n.snippetsExampleReplyBody,
        ),
      ),
      (
        'interactive',
        l10n.snippetsExampleInteractiveTitle,
        SnippetDraft(
          title: l10n.snippetsExampleInteractiveTitle,
          // Placeholders built from the field names, so a translation can
          // never leave a field without its `{{name}}` in the template.
          body: l10n.snippetsExampleInteractiveBody(
            interactiveSnippetPlaceholder(first),
            interactiveSnippetPlaceholder(second),
          ),
          kind: 'interactive',
          fields: [first, second],
        ),
      ),
    ];
    final muted = TextStyle(
      fontSize: WpTypography.small,
      color: WpColors.textMuted,
      height: 1.4,
    );
    return Semantics(
      identifier: 'snippets-examples',
      container: true,
      child: SizedBox(
        key: const ValueKey('snippets-examples'),
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.snippetsExamplesLabel, style: muted),
            const SizedBox(height: WpSpacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: WpSpacing.sm,
              runSpacing: WpSpacing.xs,
              children: [
                for (final (id, label, draft) in examples)
                  WpFilterChip(
                    testId: 'snippets-example-$id',
                    label: label,
                    isActive: false,
                    onTap: () => onPick(draft),
                  ),
              ],
            ),
            const SizedBox(height: WpSpacing.md),
            Text(
              l10n.snippetsEmptyWhenSnippet,
              key: const ValueKey('snippets-empty-when'),
              style: muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snippet tile
// ---------------------------------------------------------------------------

/// Collapses runs of whitespace in a snippet body preview — hoisted so the
/// pattern compiles once instead of on every `_bodyPreviewOf`
/// recompute, the same house idiom as `search_query_parser.dart`'s
/// module-level patterns.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// The body preview as it is painted (UX-036).
///
/// Wrapped in a first-strong isolate (FSI): the body takes its direction from
/// its own first strong letter, so a Latin body inside a right-to-left UI
/// (Hebrew) keeps its trailing punctuation at its own end, and a Hebrew body
/// stays right-to-left. No direction is guessed here.
String snippetPreviewForDisplay(String body) => '\u2068$body\u2069';

/// The body preview of a snippet row: an interactive snippet lists its
/// fields, a plain one its body with newlines and runs of whitespace collapsed
/// to single spaces, so the two preview lines show content rather than the
/// author's line breaks.
String _bodyPreviewOf(SnippetItem snippet) {
  if (snippet.isInteractive) return snippet.fields.join(' · ');
  return snippet.body.trim().replaceAll(_whitespaceRun, ' ');
}

/// One snippet row on the shared [WpCollectionListItem] (#1498): the active
/// list, the trash and the unsaved new snippet differ only in the slots they
/// fill. Watches the snippet's metadata so the row rebuilds when it changes.
class _SnippetRow extends ConsumerWidget {
  const _SnippetRow({
    super.key,
    required this.snippet,
    required this.isCursor,
    required this.isOpen,
    required this.onTap,
    required this.actions,
    this.isHighlighted = false,
    this.leading,
    this.badges = const [],
    this.showFavourite = false,
    this.showUsage = false,
    this.contextMenu,
    this.onDeleteKey,
    this.onDuplicate,
    this.isSelected = false,
    this.tags = const [],
  });

  final SnippetItem snippet;

  /// The snippet's tags by name (#662): informative pills in the footer, as
  /// on a note row; filtering goes through the toolbar's tag filter.
  final List<Tag> tags;

  /// The list's arrow cursor stands on this row. Reported to screen readers
  /// as selected, the same as a history row: the list's real focus sits on
  /// one page-level node, so without it nothing is announced while arrowing.
  final bool isCursor;

  /// The snippet was just created: drawn with the focus treatment a moment.
  final bool isHighlighted;
  final bool isOpen;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget Function(bool visible) actions;
  final Widget? leading;
  final List<Widget> badges;
  final bool showFavourite;
  final bool showUsage;
  final List<WpContextMenuEntry> Function()? contextMenu;
  final VoidCallback? onDeleteKey;

  /// Duplicate has no button: a screen reader reaches it as a custom action.
  final VoidCallback? onDuplicate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      contentMetadataProvider((kind: ContentKind.snippet, id: snippet.id)),
    );
    final l10n = L10n.of(context);
    final id = snippet.id;
    final preview = _bodyPreviewOf(snippet);
    final lastUsedAt = snippet.lastUsedAt;
    final duplicate = onDuplicate;
    return WpCollectionListItem(
      contentKey: ValueKey('snippets-item-content-$id'),
      semanticsIdentifier: 'snippets-item-$id',
      typeIcon: snippet.isInteractive
          ? LucideIcons.listChecks
          : LucideIcons.notebookText,
      leading: leading,
      title: WpCollectionListItemTitle(
        key: ValueKey('snippets-item-title-$id'),
        snippet.title,
      ),
      badges: badges,
      isFavourite: showFavourite && snippet.isFavorite,
      favouriteMarkKey: ValueKey('snippets-favourite-mark-$id'),
      favouriteMarkLabel: l10n.listItemFavouriteMark,
      actions: actions,
      preview: WpListItemContent.previewDiffers(snippet.title, preview)
          ? WpCollectionListItemPreview(snippetPreviewForDisplay(preview))
          : null,
      previewSemanticsLabel: WpListItemContent.spokenPreview(
        snippet.title,
        preview,
      ),
      meta: !showUsage || lastUsedAt == null
          ? null
          : (color) => WpListItemMeta(
              key: ValueKey('snippets-usage-$id'),
              color: color,
              spans: [
                TextSpan(
                  text: l10n.snippetsUsageLine(
                    snippet.useCount,
                    DateFormat.yMd(
                      Localizations.localeOf(context).toString(),
                    ).format(lastUsedAt),
                  ),
                ),
              ],
            ),
      footer: tags.isEmpty
          ? null
          : WpTagChipRow(
              key: ValueKey('snippets-tags-$id'),
              names: [for (final t in tags) t.name],
            ),
      isFocused: isCursor,
      isHighlighted: isHighlighted,
      isSelected: isSelected || isOpen,
      isOpen: isOpen,
      contextMenu: contextMenu,
      focusable: true,
      onDeleteKey: onDeleteKey,
      onTap: onTap,
      // Affordance as hint, identity from the rendered title, so the title
      // is announced once and first.
      semanticsHint: l10n.actionOpen,
      semanticsSelected: isCursor,
      customSemanticsActions: duplicate == null
          ? null
          : {CustomSemanticsAction(label: l10n.actionDuplicate): duplicate},
    );
  }
}
