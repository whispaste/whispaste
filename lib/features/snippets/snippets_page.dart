import '../../core/search/search_ranker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/snippet_picker/snippet_picker_controller.dart';
import '../../services/snippets/interactive_snippet_composer.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_list_tile_surface.dart';
import '../../widgets/wp_row_action.dart';
import '../../widgets/dialog.dart';
import '../../widgets/find_replace.dart';
import '../../widgets/markdown_toolbar.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_accent_badge.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_segmented_selector.dart';
import '../../widgets/wp_text_field.dart';
import '../../widgets/wp_text_link.dart';
import '../../core/navigation/page_state.dart';
import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// UI-facing snippet — named separately from the drift-generated [Snippet]
/// row class to avoid a name collision.
class SnippetItem {
  const SnippetItem({
    required this.id,
    required this.title,
    required this.body,
    this.kind = 'static',
    this.fields = const [],
  });

  final String id;
  final String title;
  final String body;

  /// `static` (default — [body] is inserted verbatim) or `interactive`
  /// (interactive-snippets PRD — [fields] names the guided recording
  /// sequence's fields in order; [body] holds the user-authored template,
  /// with an `{{fieldName}}` placeholder for each field's dictated text —
  /// see `interactive_snippet_composer.dart`).
  final String kind;

  /// Ordered field names for an `interactive` snippet. Empty for `static`.
  final List<String> fields;

  bool get isInteractive => kind == 'interactive';
}

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

class SnippetsNotifier extends AsyncNotifier<List<SnippetItem>>
    with ReloadableListNotifier<SnippetItem> {
  @override
  Future<List<SnippetItem>> readAll() async {
    final db = ref.read(historyDatabaseProvider);
    return (await db.readAllSnippetsWithFields()).map(_fromDb).toList();
  }

  @override
  Future<List<SnippetItem>> build() => readAll();

  // Deliberately not further extracted: shares its "generate a uuid,
  // upsert, reload" shape with ReplacementsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  Future<void> add(
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
  }

  Future<void> updateSnippet(
    String id, {
    required String title,
    required String body,
    String kind = 'static',
    List<String> fields = const [],
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertSnippetWithFields(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      kind: kind,
      fieldNames: fields,
    );
    await reload();
  }

  Future<void> remove(String id) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteSnippet(id);
    await reload();
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
    // One transaction: a failing row rolls back the delete too, so the old
    // library survives a broken import (UIA-SNP-01).
    await db.transaction(() async {
      await db.deleteAllSnippets();
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        await db.upsertSnippetWithFields(
          id: '${now.millisecondsSinceEpoch}_$i',
          title: item.title,
          body: item.body,
          createdAt: now,
          kind: item.kind,
          fieldNames: item.fields,
        );
      }
    });
    await reload();
  }

  static SnippetItem _fromDb(SnippetWithFields row) => SnippetItem(
    id: row.row.id,
    title: row.row.title,
    body: row.row.body,
    kind: row.row.kind,
    fields: row.fields,
  );
}

final snippetsProvider =
    AsyncNotifierProvider<SnippetsNotifier, List<SnippetItem>>(
      SnippetsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Snippets page — named, multi-line text blocks kept in a separate settings
/// area from Replacements (dictation-automations ticket 05).
class SnippetsPage extends ConsumerStatefulWidget {
  const SnippetsPage({super.key});

  @override
  ConsumerState<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends ConsumerState<SnippetsPage> {
  @override
  // Deliberately not further extracted: WpSearchableListPage call-site
  // parameter skeleton is feature-specific (l10n keys, icon, callbacks), only
  // the parameter *names* repeat across features using it. A further-generic
  // factory (e.g. keyed by notifier + string-map) was evaluated and rejected
  // as the exact "Data Clumps"-in-reverse trade the WpSearchableListPage
  // extraction already made — this is its irreducible residue, not
  // unextracted duplication.
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

    return WpSearchableListPage<SnippetItem>(
      identifierPrefix: 'snippets',
      header: _SnippetPickerSettingsLink(
        showEmptyListHint: trigger.trim().isNotEmpty && !hasSnippets,
      ),
      asyncAll: ref.watch(snippetsProvider),
      // ⚡ Bolt: Use precompiled case-insensitive RegExp to match fields instead
      // of allocating lowercased strings repeatedly in tight loops.
      searchFields: (s) => [
        SearchField(s.title, SearchWeight.title),
        SearchField(s.body, SearchWeight.body),
      ],
      searchHint: l10n.snippetsSearch,
      searchFieldLabel: l10n.snippetsSearchFieldLabel,
      addLabel: l10n.snippetsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(snippetsProvider),
      emptyIcon: LucideIcons.notebookText,
      emptyTitle: l10n.snippetsEmpty,
      emptyHint: l10n.snippetsEmptyHint,
      // Same string as the empty state's hint — the page keeps explaining
      // itself once the first snippet exists (ticket 03, point 4).
      subtitle: l10n.snippetsEmptyHint,
      // A snippet row is 87 dp, not the single-line default (its body
      // preview takes two lines) — measured, see the constant's docs.
      skeletonRowHeight: 87,
      emptyActionLabel: l10n.snippetsAdd,
      noMatchesTitle: l10n.snippetsNoMatches,
      noMatchesHint: l10n.snippetsNoMatchesHint,
      onItemActivate: (s) => _showAddEditDialog(existing: s),
      onItemDelete: _confirmDelete,
      itemBuilder: (context, s, isCursor) {
        // loam-ignore: a11y-interactive-semantics – semantics provided in _SnippetTileState.build
        return _SnippetTile(
          key: ValueKey('snippets-row-${s.id}'),
          snippet: s,
          isCursor: isCursor,
          onTap: () => _showAddEditDialog(existing: s),
          onDelete: () => _confirmDelete(s),
          onCopy: () => _copySnippet(s),
          onDuplicate: () => _duplicateSnippet(s),
        );
      },
    );
  }

  // ── Add / Edit dialog ────────────────────────────────────────────────

  // Deliberately not further extracted into an onCreate/onUpdate-callback
  // helper: tried it, the result was longer than the original and replaced
  // the direct `final (title, body) = result;` destructuring with closure
  // indirection — net readability loss, so this stays as-is (unlike the
  // dialog scaffold, which extracted cleanly into WpSearchableListPage).
  Future<void> _showAddEditDialog({SnippetItem? existing}) async {
    await showWpFormDialog<void>(
      context: context,
      builder: (_, a) => _SnippetDialog(
        animation: a,
        existing: existing,
        onSave: (draft) => _saveSnippet(existing, draft),
      ),
    );
  }

  /// Writes the dialog's draft. Returns `false` when the write fails, so the
  /// dialog stays open with the typed input and the user is told (UIA-SNP-02).
  Future<bool> _saveSnippet(SnippetItem? existing, _SnippetDraft draft) async {
    final (title, body, kind, fields) = draft;
    final notifier = ref.read(snippetsProvider.notifier);
    try {
      if (existing != null) {
        await notifier.updateSnippet(
          existing.id,
          title: title,
          body: body,
          kind: kind,
          fields: fields,
        );
      } else {
        await notifier.add(title, body, kind: kind, fields: fields);
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'snippets', action: 'create');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Copy action ──────────────────────────────────────────────────────

  void _copySnippet(SnippetItem snippet) {
    copyToClipboardWithToast(
      context: context,
      ref: ref,
      text: snippet.body,
      category: 'snippets',
    );
  }

  Future<void> _duplicateSnippet(SnippetItem item) async {
    await ref
        .read(snippetsProvider.notifier)
        .add(
          '${item.title} ${L10n.of(context).snippetCopySuffix}',
          item.body,
          kind: item.kind,
          fields: item.fields,
        );
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(SnippetItem s) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.snippetsDeleteTitle,
      message: l10n.snippetsDeleteMessage(s.title),
      confirmLabel: l10n.actionDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (confirmed) ref.read(snippetsProvider.notifier).remove(s.id);
  }
}

// ---------------------------------------------------------------------------
// Settings link for the picker (UX-030)
// ---------------------------------------------------------------------------

/// One line above the list that leads to the Settings row for the spoken
/// trigger word and the picker hotkey.
///
/// Both are global settings that change rarely, so they live in General ›
/// Tastenkürzel. This page keeps only the affordance, so the list starts right
/// under the search bar. Where the platform has no native picker, the page says
/// so and offers no link: there is nothing to set.
class _SnippetPickerSettingsLink extends ConsumerWidget {
  const _SnippetPickerSettingsLink({required this.showEmptyListHint});

  /// True when a trigger word is set but the snippet list is empty: the trigger
  /// does nothing yet, which this page must say out loud.
  final bool showEmptyListHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final available = ref.watch(snippetPickerAvailabilityProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.xs,
        WpSpacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showEmptyListHint)
            Padding(
              padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    size: WpIconSize.xs,
                    color: WpColors.warning,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.snippetsPickerTriggerEmptyListHint,
                      style: TextStyle(
                        color: WpColors.warning,
                        fontSize: WpTypography.small,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (available)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WpTextLink(
                label: l10n.snippetsPickerSettingsLink,
                icon: LucideIcons.settings,
                testID: 'snippets-picker-settings-link',
                onPressed: () => _openPickerSettings(ref),
              ),
            )
          else
            // Deliberately no link: there is nothing to set. Same sentence as
            // in Settings.
            Padding(
              key: const Key('snippetsPickerUnavailable'),
              padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
              child: Text(
                l10n.snippetsPickerUnavailable,
                style: TextStyle(
                  color: WpColors.textMuted,
                  fontSize: WpTypography.small,
                  height: 1.4,
                ),
              ),
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
// Add / Edit dialog
// ---------------------------------------------------------------------------

/// What the add/edit dialog hands to the page: title, body, kind and the
/// interactive field names.
typedef _SnippetDraft = (String, String, String, List<String>);

class _SnippetDialog extends StatefulWidget {
  const _SnippetDialog({
    required this.animation,
    required this.onSave,
    this.existing,
  });

  final Animation<double> animation;
  final SnippetItem? existing;

  /// Returns whether the draft was stored; the dialog closes only then.
  final Future<bool> Function(_SnippetDraft draft) onSave;

  @override
  State<_SnippetDialog> createState() => _SnippetDialogState();
}

class _SnippetDialogState extends State<_SnippetDialog> {
  bool _saving = false;
  late final TextEditingController _titleCtrl;
  late final WpFindHighlightController _bodyCtrl;
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'snippetBody');

  late String _kind;
  late List<TextEditingController> _fieldCtrls;

  bool get _isInteractive => _kind == 'interactive';

  /// Minimum fields for an interactive snippet — 1, not 0: a guided
  /// recording sequence with zero fields would have nothing left to
  /// dictate into, but a single field is a legitimate shape (a single
  /// prompt wrapped in a fixed template), not just a static snippet with
  /// extra steps.
  static const _minFields = 1;

  bool get _fieldsValid =>
      _fieldCtrls.length >= _minFields &&
      _fieldCtrls.every((c) => c.text.trim().isNotEmpty);

  /// Every named field must appear as a `{{fieldName}}` placeholder
  /// somewhere in the template ([_bodyCtrl]) — otherwise its dictated text
  /// would have nowhere to go once composed.
  bool get _templateReferencesAllFields => _fieldCtrls.every((c) {
    final name = c.text.trim();
    return name.isEmpty ||
        _bodyCtrl.text.contains(interactiveSnippetPlaceholder(name));
  });

  late final String _openedDraft;

  String get _draftText => [
    _titleCtrl.text,
    _bodyCtrl.text,
    for (final c in _fieldCtrls) c.text,
  ].join('\u0000');

  /// Typed text that a dismiss would throw away (UIA-CMP-03).
  bool get _hasUnsavedInput => _draftText != _openedDraft;

  /// Two fields with the same name would both receive the same spoken text,
  /// so the second one is refused rather than silently overwritten (UIA-SNP-05).
  bool get _fieldNamesUnique =>
      _fieldCtrls.map((c) => c.text.trim()).toSet().length ==
      _fieldCtrls.length;

  bool get _isValid =>
      _titleCtrl.text.trim().isNotEmpty &&
      (_isInteractive
          ? (_fieldsValid && _fieldNamesUnique && _templateReferencesAllFields)
          : _bodyCtrl.text.trim().isNotEmpty);

  /// Why a disabled Save is disabled, as text next to the button (UIA-SNP-04).
  /// Only the title and body reasons are named here; the field and template
  /// problems already have their own inline warnings.
  String? _saveBlockedReason(L10n l10n) {
    if (_titleCtrl.text.trim().isEmpty) return l10n.snippetsSaveMissingTitle;
    if (!_isInteractive && _bodyCtrl.text.trim().isEmpty) {
      return l10n.snippetsSaveMissingBody;
    }
    return null;
  }

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    // Highlight-capable so the editor toolbar's find bar can tint its hits —
    // the same controller History's transcript and the Notes editor use.
    _bodyCtrl = WpFindHighlightController(text: widget.existing?.body ?? '');
    // The Save button's enabled state hangs off both fields, and a
    // replace-all from the toolbar changes the body without going through
    // `onChanged`.
    _bodyCtrl.addListener(_onBodyChanged);

    _kind = widget.existing?.kind ?? 'static';
    final existingFields = widget.existing?.fields ?? const [];
    _fieldCtrls = [
      for (final name in existingFields) _newFieldController(name),
      // A fresh interactive snippet starts with the two required empty
      // fields already visible instead of an editor the user must first
      // populate from zero.
      if (existingFields.length < _minFields)
        for (var i = existingFields.length; i < _minFields; i++)
          _newFieldController(),
    ];
    _openedDraft = _draftText;
  }

  TextEditingController _newFieldController([String text = '']) {
    final controller = TextEditingController(text: text);
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    return controller;
  }

  @override
  void dispose() {
    _bodyCtrl.removeListener(_onBodyChanged);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    for (final c in _fieldCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onBodyChanged() {
    if (mounted) setState(() {});
  }

  void _addField() {
    setState(() => _fieldCtrls.add(_newFieldController()));
  }

  void _removeField(int index) {
    setState(() {
      _fieldCtrls.removeAt(index).dispose();
    });
  }

  void _moveField(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _fieldCtrls.length) return;
    setState(() {
      final field = _fieldCtrls.removeAt(index);
      _fieldCtrls.insert(target, field);
    });
  }

  Future<void> _submit() async {
    if (!_isValid || _saving) return;
    _saving = true;
    final saved = await widget.onSave((
      _titleCtrl.text.trim(),
      _bodyCtrl.text.trim(),
      _kind,
      _isInteractive
          ? [for (final c in _fieldCtrls) c.text.trim()]
          : const <String>[],
    ));
    _saving = false;
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      WpToast.show(
        context,
        message: L10n.of(context).errorGeneric,
        type: WpToastType.error,
      );
    }
  }

  /// Inserts `{{fieldName}}` into the template at the current cursor
  /// position (or selection, which it replaces), falling back to the end of
  /// the text when there is no active selection yet.
  void _insertFieldPlaceholder(String fieldName) {
    final placeholder = interactiveSnippetPlaceholder(fieldName);
    final text = _bodyCtrl.text;
    var start = _bodyCtrl.selection.start;
    var end = _bodyCtrl.selection.end;
    if (start < 0 || end < 0 || start > text.length || end > text.length) {
      start = text.length;
      end = text.length;
    }
    _bodyCtrl.text = text.replaceRange(start, end, placeholder);
    _bodyCtrl.selection = TextSelection.collapsed(
      offset: start + placeholder.length,
    );
  }

  /// Named-field editor for an `interactive` snippet — add/rename/reorder/
  /// remove, at least [_minFields] fields (PRD User Stories 3/4). Reordering
  /// is up/down buttons rather than drag-and-drop: this dialog's fields live
  /// inside a plain scroll view (see the body editor's own comment above),
  /// not a scrollable-aware `ReorderableListView`.
  List<Widget> _buildFieldEditor(L10n l10n, ThemeData theme) {
    return [
      Text(l10n.snippetsFieldsLabel, style: theme.textTheme.titleSmall),
      const SizedBox(height: WpSpacing.xxs),
      Text(
        l10n.snippetsFieldsHint,
        style: TextStyle(
          color: WpColors.textMuted,
          fontSize: WpTypography.caption,
        ),
      ),
      const SizedBox(height: WpSpacing.xs),
      for (var i = 0; i < _fieldCtrls.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: WpSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: WpTextField(
                  key: ValueKey('snippets-field-name-$i'),
                  controller: _fieldCtrls[i],
                  variant: WpTextFieldVariant.form,
                  hintText: l10n.snippetsFieldNameHint(i + 1),
                ),
              ),
              // loam-ignore: a11y-interactive-semantics – icon-only IconButton carries its own semantics
              IconButton(
                key: const ValueKey('snippets-field-insert'),
                icon: const Icon(LucideIcons.plus, size: WpIconSize.xs),
                tooltip: l10n.snippetsFieldInsertIntoTemplate,
                onPressed: _fieldCtrls[i].text.trim().isEmpty
                    ? null
                    : () => _insertFieldPlaceholder(_fieldCtrls[i].text.trim()),
              ),
              // loam-ignore: a11y-interactive-semantics – icon-only IconButton carries its own semantics
              IconButton(
                key: ValueKey('snippets-field-move-up-$i'),
                icon: const Icon(LucideIcons.chevronUp, size: WpIconSize.xs),
                tooltip: l10n.snippetsFieldMoveUp,
                onPressed: i > 0 ? () => _moveField(i, -1) : null,
              ),
              // loam-ignore: a11y-interactive-semantics – icon-only IconButton carries its own semantics
              IconButton(
                key: ValueKey('snippets-field-move-down-$i'),
                icon: const Icon(LucideIcons.chevronDown, size: WpIconSize.xs),
                tooltip: l10n.snippetsFieldMoveDown,
                onPressed: i < _fieldCtrls.length - 1
                    ? () => _moveField(i, 1)
                    : null,
              ),
              // loam-ignore: a11y-interactive-semantics – icon-only IconButton carries its own semantics
              IconButton(
                key: ValueKey('snippets-field-remove-$i'),
                icon: const Icon(LucideIcons.x, size: WpIconSize.xs),
                tooltip: l10n.snippetsFieldRemove,
                onPressed: _fieldCtrls.length > _minFields
                    ? () => _removeField(i)
                    : null,
              ),
            ],
          ),
        ),
      // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
      WpButton(
        key: const ValueKey('snippets-field-add'),
        label: l10n.snippetsFieldAdd,
        variant: WpButtonVariant.ghost,
        size: WpButtonSize.dense,
        onPressed: _addField,
      ),
      if (!_fieldsValid) ...[
        const SizedBox(height: WpSpacing.xxs),
        Text(
          l10n.snippetsFieldsMinWarning(_minFields),
          style: TextStyle(
            color: WpColors.warning,
            fontSize: WpTypography.caption,
          ),
        ),
      ],
      if (!_fieldNamesUnique) ...[
        const SizedBox(height: WpSpacing.xxs),
        Text(
          l10n.snippetsFieldsDuplicateWarning,
          style: TextStyle(
            color: WpColors.warning,
            fontSize: WpTypography.caption,
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return WpUnsavedInputGuard(
      dirty: _hasUnsavedInput,
      child: WpFormDialogShell(
        animation: widget.animation,
        // A snippet body is a *document* — a prompt template runs to paragraphs,
        // and at the standard 420 dp card with a six-line box it read as a slot
        // to paste into rather than a place to write. Widened via the named
        // [WpDialogSize] axis rather than a one-off width, and still a dialog
        // rather than a full-screen sheet: the snippet list behind it is the
        // context you are editing against, and every other create/edit surface
        // in the app (replacements, tags) is a dialog too.
        size: WpDialogSize.wide,
        title: _isEditing ? l10n.snippetsEditSnippet : l10n.snippetsNewSnippet,
        subtitle: l10n.snippetsDialogHint,
        fields: [
          // Title
          Text(l10n.snippetsTitleLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: WpSpacing.xxs),
          WpTextField(
            key: const ValueKey('snippets-title-field'),
            controller: _titleCtrl,
            variant: WpTextFieldVariant.form,
            autofocus: true,
            hintText: l10n.snippetsTitleHint,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: WpSpacing.md),

          // Kind: Static / Interactive (interactive-snippets PRD)
          Text(l10n.snippetsKindLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: WpSpacing.xxs),
          WpSegmentedChoice<String>(
            key: const ValueKey('snippets-kind-choice'),
            options: [
              WpSegmentOption(value: 'static', label: l10n.snippetsKindStatic),
              WpSegmentOption(
                value: 'interactive',
                label: l10n.snippetsKindInteractive,
              ),
            ],
            selected: _kind,
            onChanged: (value) => setState(() => _kind = value),
          ),
          const SizedBox(height: WpSpacing.md),

          if (_isInteractive) ...[
            ..._buildFieldEditor(l10n, theme),
            const SizedBox(height: WpSpacing.md),
            Text(l10n.snippetsTemplateLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: WpSpacing.xxs),
            Text(
              l10n.snippetsTemplateHint,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
            const SizedBox(height: WpSpacing.xs),
            // Same toolbar-plus-shortcuts editor as the static body below: a
            // template is still a document the user writes prose into, just
            // one that also happens to carry `{{field}}` placeholders —
            // formatting and find/replace should not disappear because of that.
            WpMarkdownToolbar(
              key: const ValueKey('snippets-body-toolbar'),
              controller: _bodyCtrl,
              focusNode: _bodyFocus,
            ),
            const SizedBox(height: WpSpacing.xs),
            CallbackShortcuts(
              bindings: WpMarkdownFormatting(
                controller: _bodyCtrl,
                focusNode: _bodyFocus,
              ).shortcutBindings(),
              child: WpTextField(
                key: const ValueKey('snippets-body-field'),
                controller: _bodyCtrl,
                focusNode: _bodyFocus,
                variant: WpTextFieldVariant.form,
                hintText: l10n.snippetsTemplateFieldHint,
                minLines: 10,
                maxLines: 18,
              ),
            ),
            if (!_templateReferencesAllFields) ...[
              const SizedBox(height: WpSpacing.xxs),
              Text(
                l10n.snippetsTemplateMissingFieldsWarning,
                style: TextStyle(
                  color: WpColors.warning,
                  fontSize: WpTypography.caption,
                ),
              ),
            ],
          ] else ...[
            // Body (multi-line) — same toolbar the History transcript editor
            // and the Notes editor carry, so bold/italic/lists and
            // find-and-replace work identically wherever text is written in
            // this app.
            Text(l10n.snippetsBodyLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: WpSpacing.xxs),
            WpMarkdownToolbar(
              key: const ValueKey('snippets-body-toolbar-plain'),
              controller: _bodyCtrl,
              focusNode: _bodyFocus,
            ),
            const SizedBox(height: WpSpacing.xs),
            // No Expanded/Flexible here on purpose: WpFormDialogShell puts its
            // fields inside a SingleChildScrollView, so an unbounded height
            // would be a layout exception. The line count does the growing
            // instead, and the card's own viewport clamp keeps it on screen.
            CallbackShortcuts(
              bindings: WpMarkdownFormatting(
                controller: _bodyCtrl,
                focusNode: _bodyFocus,
              ).shortcutBindings(),
              child: WpTextField(
                key: const ValueKey('snippets-body-field'),
                controller: _bodyCtrl,
                focusNode: _bodyFocus,
                variant: WpTextFieldVariant.form,
                hintText: l10n.snippetsBodyHint,
                minLines: 10,
                maxLines: 18,
              ),
            ),
          ],
          // Why Save is disabled, as text in the body (UIA-SNP-04). Moved out of
          // the footer: the footer holds buttons only.
          if (_saveBlockedReason(l10n) case final reason?) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(
              reason,
              key: const ValueKey('snippets-save-blocked-reason'),
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
          ],
        ],
        actions: [
          WpDialogAction(
            label: l10n.actionCancel,
            testId: 'snippets-cancel',
            role: WpDialogActionRole.cancel,
          ),
          WpDialogAction(
            label: _isEditing ? l10n.actionSave : l10n.snippetsAdd,
            testId: 'snippets-save',
            role: WpDialogActionRole.primary,
            enabled: _isValid,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snippet tile
// ---------------------------------------------------------------------------

/// Collapses runs of whitespace in a snippet body preview — hoisted so the
/// pattern compiles once instead of on every `_SnippetTileState._bodyPreview`
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

class _SnippetTile extends StatefulWidget {
  const _SnippetTile({
    super.key,
    required this.snippet,
    required this.isCursor,
    required this.onTap,
    required this.onDelete,
    required this.onCopy,
    required this.onDuplicate,
  });

  final SnippetItem snippet;

  /// This row is where the list's arrow cursor currently stands
  /// (`WpSearchableListPage`). Deliberately funnelled into the *same* two
  /// outlets as real focus — [WpListTileSurface.isFocused] and the row's
  /// `Semantics(selected:)` — rather than getting a treatment of its own: the
  /// tile envelope is where a row's states are decided, and a second one
  /// would put two answers on screen for one question.
  final bool isCursor;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onDuplicate;

  @override
  State<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends State<_SnippetTile> {
  bool _isHovered = false;
  bool _isFocused = false;

  /// The row is "active" for pointer and for keyboard alike — the
  /// delete action is revealed by either, so a keyboard user can reach
  /// it at all (an unmounted button cannot be focused). The arrow cursor
  /// counts as keyboard: `WpSearchableListPage` binds Delete/Backspace on the
  /// cursor row, so the icon and the key appear together or not at all.
  bool get _isActive => _isHovered || _isFocused || widget.isCursor;

  /// Preview of the body — newlines and runs of whitespace collapse to
  /// single spaces so the two rendered lines are filled by content rather
  /// than by the author's line breaks: a snippet whose body starts with a
  /// short salutation would otherwise spend its whole preview on it.
  /// The Text renders `maxLines: 2` (same as the replacements row).
  ///
  /// Memoized once per `widget.snippet` change (initState + didUpdateWidget),
  /// not recomputed on every build — hover/focus toggles rebuild this row via
  /// its own `setState` without a new snippet, and re-running the trim +
  /// regex collapse on each of those was repeated work for an unchanged
  /// result. Same shape as the memoized fields in `HistoryEntryRow`
  /// (`history_list_tile.dart`).
  late String _bodyPreview = _computeBodyPreview(widget.snippet);

  static String _computeBodyPreview(SnippetItem snippet) {
    if (snippet.isInteractive) return snippet.fields.join(' · ');
    return snippet.body.trim().replaceAll(_whitespaceRun, ' ');
  }

  @override
  void didUpdateWidget(_SnippetTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snippet != widget.snippet) {
      _bodyPreview = _computeBodyPreview(widget.snippet);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Delete/Backspace remove the row that holds keyboard focus — the same
      // two keys Notizen has always bound on its list, closing the last gap
      // that made "manage a list without the mouse" a per-screen skill.
      //
      // The consequence deliberately differs from Notizen's: there the key
      // moves a note to the trash and offers an undo toast, here it opens the
      // delete confirmation. That is not an inconsistency but the same
      // safety promise served by the only means each screen has — snippets
      // have no trash to fall back on, so the confirmation is the undo.
      //
      // Scoped to this row on purpose: the bindings only fire while focus
      // sits inside it, so the page's search field (a sibling, not a
      // descendant) keeps Backspace for editing text.
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.delete): widget.onDelete,
        const SingleActivator(LogicalKeyboardKey.backspace): widget.onDelete,
      },
      child: _buildRow(context),
    );
  }

  Widget _buildRow(BuildContext context) {
    return Semantics(
      button: true,
      // Affordance as `hint:`, identity from the rendered text. The label
      // used to read "<Snippet bearbeiten>: <Titel>" around a subtree that
      // renders that same title as Text, and a Semantics label is prepended
      // to its subtree's text rather than substituted for it — so the title
      // was announced twice. Keeping the identity in the rendered text also
      // puts it first, which is what a screen-reader user scanning a list
      // needs to hear before the affordance. `hint:` is precisely the slot
      // for "what happens when you activate this".
      //
      // The house alternative (MergeSemantics around a label-less Semantics)
      // is ruled out: the delete action mounts as a second interactive node
      // inside this subtree the moment the row is hovered or focused, and
      // merging would swallow it. Same treatment in _ReplacementTile.
      hint: L10n.of(context).snippetsEditSnippet,
      // The arrow cursor's row reports as selected, exactly as a history row
      // does: the list's real focus sits on one page-level node, so without
      // this flag a screen reader announces nothing at all while the user
      // arrows down the list. Not `focused:` — the row genuinely does not
      // hold focus, and `FocusableActionDetector` below publishes that flag
      // itself for the Tab case.
      selected: widget.isCursor,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) {
          if (_isFocused == value) return;
          setState(() => _isFocused = value);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: WpListTileSurface(
              variant: WpListTileVariant.card,
              isHovered: _isHovered,
              isFocused: _isFocused || widget.isCursor,
              actions: WpRowActions(
                visible: _isActive,
                children: [
                  // A copy has nothing to copy for an interactive snippet —
                  // its body is a template, not final text; the composed
                  // result only exists after the guided recording.
                  if (!widget.snippet.isInteractive)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                    WpRowAction(
                      key: ValueKey('snippets-copy-${widget.snippet.id}'),
                      icon: LucideIcons.copy,
                      tooltip: L10n.of(context).actionCopy,
                      onTap: widget.onCopy,
                    ),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                  WpRowAction(
                    key: ValueKey('snippets-duplicate-${widget.snippet.id}'),
                    icon: LucideIcons.files,
                    tooltip: L10n.of(context).actionDuplicate,
                    onTap: widget.onDuplicate,
                  ),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                  WpRowAction(
                    key: ValueKey('snippets-delete-${widget.snippet.id}'),
                    icon: LucideIcons.trash2,
                    tooltip: L10n.of(context).actionDelete,
                    onTap: widget.onDelete,
                    isDestructive: true,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.snippet.isInteractive
                        ? LucideIcons.listChecks
                        : LucideIcons.notebookText,
                    size: WpIconSize.sm,
                    color: WpColors.accent,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.snippet.title,
                                style: TextStyle(
                                  color: WpColors.textPrimary,
                                  fontSize: WpTypography.body,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.snippet.isInteractive) ...[
                              const SizedBox(width: WpSpacing.xxs),
                              WpAccentBadge(
                                label: L10n.of(
                                  context,
                                ).snippetsInteractiveBadge,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: WpSpacing.xxs),
                        Text(
                          snippetPreviewForDisplay(_bodyPreview),
                          style: TextStyle(
                            color: WpColors.textMuted,
                            fontSize: WpTypography.small,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
