import 'dart:async';

import '../../../core/data/content_metadata_providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/text/text_undo.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/snippets/interactive_snippet_composer.dart';
import '../../../services/snippets/system_variables.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/find_replace.dart';
import '../../../widgets/wp_editor_pane.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_segmented_selector.dart';
import '../../../widgets/wp_save_status.dart';
import '../../../widgets/wp_text_editor.dart';
import '../../../widgets/wp_head_actions.dart';
import '../../../widgets/wp_text_field.dart';
import '../../notes/data/note_title.dart';
import '../snippet_draft.dart';
import '../../links/entry_link_picker.dart' show pickEntryLinkText;
import '../../links/entry_links_section.dart';
import '../../../core/text/entry_link.dart' show EntryLinkKind;
import '../snippet_item.dart';

/// The one way to see, create and edit a snippet: the right-hand side of the
/// Snippets split view (#864), with the Notes editor's model (#1498): the
/// user writes straight into the pane, there is no edit mode and no Save or
/// Discard button.
///
/// Saving is a debounced autosave ([autosaveDelay]) plus Ctrl/Cmd+S for "now".
/// Only a valid state is ever stored (title set; a static snippet has text,
/// an interactive one fields that are named, unique and all in the
/// template), so the picker and every trigger only ever expand a saved,
/// complete snippet. An invalid state is not stored; a hint in the pane's
/// notices slot says why, and the typed text stays in
/// [snippetDraftsProvider], so closing, Esc, another snippet or leaving the
/// page lose nothing.
class SnippetEditor extends ConsumerStatefulWidget {
  const SnippetEditor({
    super.key,
    required this.onSave,
    required this.onClose,
    this.existing,
    this.template,
    this.onCopy,
    this.onToggleFavourite,
    this.onDuplicate,
    this.onDelete,
    this.onInsertSnippet,
    this.tags,
  });

  /// Pause after the last change before the editor stores it.
  static const autosaveDelay = Duration(milliseconds: 800);

  /// The snippet being edited; null for a new one. The page passes the
  /// stored snippet once the new one has been created, without rebuilding
  /// the editor.
  final SnippetItem? existing;

  /// Pre-filled content for a new snippet (an empty-state example). Ignored
  /// when [existing] is set; only stored once the user changes it.
  final SnippetDraft? template;

  /// Stores the valid, trimmed state ([SnippetDraft.stored]); returns the
  /// snippet's id, or null when the write failed.
  final Future<String?> Function(SnippetDraft stored) onSave;

  /// Leaves the editor. A pending valid state is saved first, an invalid one
  /// stays as the draft.
  final VoidCallback onClose;

  /// Copies the text as shown (static snippets only).
  final ValueChanged<String>? onCopy;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onDuplicate;

  /// Moves the stored snippet to the trash. A new, never stored snippet
  /// has its own discard in the same place.
  final VoidCallback? onDelete;

  /// Opens the Textbaustein chooser for the body field (#664). Passed in by
  /// the page, which owns the library, so the editor needs no import of it.
  final void Function(TextEditingController controller, FocusNode focusNode)?
  onInsertSnippet;

  /// The tag field (#662), the notes' one, built by the page that owns the
  /// tags. It shares the body's tool row where the width allows, as in the
  /// note editor. Null while a new snippet is not stored yet.
  final Widget? tags;

  @override
  ConsumerState<SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends ConsumerState<SnippetEditor> {
  /// Why the last save failed; shown above the editor.
  String? _saveFailed;
  bool _saving = false;

  /// A change arrived while a save was on its way: save again after it.
  bool _saveAgain = false;

  /// The last save attempt met an invalid state: show why (#1498).
  bool _showInvalid = false;

  /// What the editor's status line says about saving (#1498): the same
  /// states as Recordings and Notes, plus "not saved" for an invalid state.
  final ValueNotifier<WpSaveStatus> _saveStatus = ValueNotifier(
    WpSaveStatus.idle,
  );

  /// The editor was discarded or its snippet trashed: nothing to save.
  bool _abandoned = false;
  Timer? _autosave;

  late final TextEditingController _titleCtrl;
  late final WpFindHighlightController _bodyCtrl;
  late final TextUndoController _bodyUndo;
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'snippetBody');
  final FocusNode _titleFocus = FocusNode(debugLabel: 'snippetTitle');

  /// A pointer is down on the body: the focus it brings keeps the caret
  /// where the click put it. Focus by keyboard (Tab) lands at the text end.
  bool _pointerOnBody = false;

  late String _kind;
  late List<TextEditingController> _fieldCtrls;

  /// What "unchanged" means: the stored snippet, or empty for a new one.
  late final SnippetDraft _baseline;

  /// The stored state ([SnippetDraft.stored]); null while the snippet does
  /// not exist yet.
  SnippetDraft? _saved;

  /// The id once the snippet exists (set by the first save of a new one).
  String? _id;

  String get _draftKey => _id ?? kNewSnippetDraftKey;

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

  /// Why the current state is not stored (UIA-SNP-04). The field and
  /// template problems also have their own inline warnings at the list.
  String? _invalidReason(L10n l10n) {
    if (_titleCtrl.text.trim().isEmpty) return l10n.snippetsSaveMissingTitle;
    if (!_isInteractive && _bodyCtrl.text.trim().isEmpty) {
      return l10n.snippetsSaveMissingBody;
    }
    if (_isInteractive && !_isValid) return l10n.snippetsSaveMissingFields;
    return null;
  }

  SnippetDraft get _current => SnippetDraft(
    title: _titleCtrl.text,
    body: _bodyCtrl.text,
    kind: _kind,
    fields: [for (final c in _fieldCtrls) c.text],
  );

  /// The current state differs from what is stored (or, never stored, from
  /// the untouched start).
  bool get _pending {
    final saved = _saved;
    return saved == null ? _current != _baseline : _current.stored != saved;
  }

  /// A fresh interactive snippet starts with the required empty fields
  /// already visible instead of an editor the user must first populate.
  static List<String> _padded(List<String> fields) => [
    ...fields,
    for (var i = fields.length; i < _minFields; i++) '',
  ];

  static SnippetDraft _draftOf(SnippetItem item) => SnippetDraft(
    title: item.title,
    body: item.body,
    kind: item.kind,
    fields: item.fields,
  );

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _id = existing?.id;
    // A new snippet starts in its title. `autofocus` alone does not move the
    // focus away from the New button that is still holding it (#1845).
    if (existing == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
    _saved = existing == null ? null : _draftOf(existing).stored;
    if (existing?.sourceNoteId case final noteId?) {
      unawaited(_loadSourceNoteTitle(noteId));
    }
    // A new snippet's baseline is empty: a picked example is content the
    // user chose, so it counts as a change and saves like typed text.
    final source = existing != null ? _draftOf(existing) : const SnippetDraft();
    _baseline = SnippetDraft(
      title: source.title,
      body: source.body,
      kind: source.kind,
      fields: _padded(source.fields),
    );
    final stored = ref.read(snippetDraftsProvider)[_draftKey];
    final restored =
        stored != null &&
        (_saved == null ? stored != _baseline : stored.stored != _saved);
    final template = existing == null ? widget.template : null;
    final start = restored
        ? stored
        : template == null
        ? _baseline
        : SnippetDraft(
            title: template.title,
            body: template.body,
            kind: template.kind,
            fields: _padded(template.fields),
          );

    _titleCtrl = TextEditingController(text: start.title);
    _titleCtrl.addListener(_onChanged);
    // Highlight-capable so the editor toolbar's find bar can tint its hits —
    // the same controller History's transcript and the Notes editor use. A
    // replace-all from the toolbar changes the body without `onChanged`,
    // hence the listener.
    _bodyCtrl = WpFindHighlightController(text: start.body);
    _bodyCtrl.addListener(_onChanged);
    _bodyFocus.addListener(_onBodyFocus);
    // Undo for typing, toolbar, replace and placeholders alike (#651).
    _bodyUndo = TextUndoController(_bodyCtrl);
    _kind = start.kind;
    _fieldCtrls = [
      for (final name in _padded(start.fields)) _newFieldController(name),
    ];
    if (restored || template != null) {
      // A draft left from earlier or a picked example: a valid one is stored
      // after the usual pause, an invalid one says right away why it is not.
      _showInvalid = !_isValid;
      _saveStatus.value = _showInvalid
          ? WpSaveStatus.invalid
          : WpSaveStatus.saving;
      _scheduleSave();
    }
  }

  @override
  void didUpdateWidget(covariant SnippetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page hands over the created snippet: from now on it is an edit.
    final existing = widget.existing;
    if (existing != null && _id == null) {
      _id = existing.id;
      _saved ??= _draftOf(existing).stored;
    }
  }

  void _insertSnippet() => widget.onInsertSnippet?.call(_bodyCtrl, _bodyFocus);

  /// Title of the note this snippet was saved from (#664), shown above the
  /// text as the back-reference; stays null when the note is gone.
  String? _sourceNoteTitle;

  Future<void> _loadSourceNoteTitle(String noteId) async {
    final note = await ref.read(historyDatabaseProvider).getNote(noteId);
    if (!mounted || note == null) return;
    // The name the notes list shows: an untitled note goes by its first
    // line there, so the back-reference must too.
    final title = note.title?.trim() ?? '';
    setState(
      () => _sourceNoteTitle = title.isNotEmpty
          ? title
          : deriveNoteTitle(note.content) ?? L10n.of(context).notesUntitled,
    );
  }

  TextEditingController _newFieldController([String text = '']) =>
      TextEditingController(text: text)..addListener(_onChanged);

  @override
  void dispose() {
    _titleFocus.dispose();
    _autosave?.cancel();
    // Leaving with a valid change not stored yet (the page switched to
    // another snippet within the pause): store it now. No `ref` here, the
    // page's callback does the write.
    if (!_abandoned && !_saving && _pending && _isValid) {
      unawaited(widget.onSave(_current.stored));
    }
    _titleCtrl.dispose();
    _bodyUndo.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    for (final c in _fieldCtrls) {
      c.dispose();
    }
    _saveStatus.dispose();
    super.dispose();
  }

  /// Rebuilds, mirrors the content into the draft store (so nothing typed
  /// depends on this widget staying alive) and restarts the autosave pause.
  void _onChanged() {
    if (!mounted || _abandoned) return;
    setState(() {
      if (_isValid) _showInvalid = false;
    });
    _mirrorDraft();
    _saveStatus.value = !_pending
        ? (_saved == null ? WpSaveStatus.idle : WpSaveStatus.saved)
        : _showInvalid
        ? WpSaveStatus.invalid
        : WpSaveStatus.saving;
    _scheduleSave();
  }

  /// Keyboard focus continues writing at the end instead of inside the
  /// text; a click keeps the caret at the clicked spot (#1498).
  void _onBodyFocus() {
    if (!_bodyFocus.hasFocus || _pointerOnBody) return;
    _bodyCtrl.selection = TextSelection.collapsed(
      offset: _bodyCtrl.text.length,
    );
  }

  void _releasePointer() => WidgetsBinding.instance.addPostFrameCallback((_) {
    _pointerOnBody = false;
  });

  void _mirrorDraft() {
    final drafts = ref.read(snippetDraftsProvider.notifier);
    if (_pending) {
      drafts.save(_draftKey, _current);
    } else {
      drafts.clear(_draftKey);
    }
  }

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(SnippetEditor.autosaveDelay, () => unawaited(_save()));
  }

  /// Stores the current state when it changed and is valid; an invalid one
  /// only raises the hint. Ctrl/Cmd+S, the pause and closing all land here.
  Future<void> _save() async {
    _autosave?.cancel();
    _autosave = null;
    if (!mounted || _abandoned) return;
    if (!_pending) {
      // Ctrl/Cmd+S on a stored state: confirm it.
      if (_saved != null && !_saving) _saveStatus.value = WpSaveStatus.saved;
      return;
    }
    if (!_isValid) {
      if (!_showInvalid) setState(() => _showInvalid = true);
      _saveStatus.value = WpSaveStatus.invalid;
      return;
    }
    _saveStatus.value = WpSaveStatus.saving;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    final draft = _current.stored;
    final id = await widget.onSave(draft);
    _saving = false;
    if (!mounted) return;
    if (id == null) {
      setState(() => _saveFailed = L10n.of(context).errorGeneric);
      _saveStatus.value = WpSaveStatus.failed;
      return;
    }
    final wasNew = _id == null;
    setState(() {
      _saveFailed = null;
      _saved = draft;
      _id = id;
    });
    if (wasNew) {
      ref.read(snippetDraftsProvider.notifier).clear(kNewSnippetDraftKey);
    }
    _mirrorDraft();
    _saveStatus.value = _pending ? WpSaveStatus.saving : WpSaveStatus.saved;
    if (_saveAgain) {
      _saveAgain = false;
      if (_pending) _scheduleSave();
    }
  }

  void _close() {
    unawaited(_save());
    widget.onClose();
  }

  /// Back to the stored state: the way out of an invalid edit.
  void _revert() {
    final saved = _saved;
    if (saved == null) return;
    _autosave?.cancel();
    for (final c in _fieldCtrls) {
      c.dispose();
    }
    _kind = saved.kind;
    _fieldCtrls = [
      for (final name in _padded(saved.fields)) _newFieldController(name),
    ];
    _titleCtrl.text = saved.title;
    TextUndoController.command(_bodyCtrl, () => _bodyCtrl.text = saved.body);
    _autosave?.cancel();
    setState(() => _showInvalid = false);
    _saveStatus.value = WpSaveStatus.saved;
    ref.read(snippetDraftsProvider.notifier).clear(_draftKey);
  }

  void _setKind(String kind) {
    _kind = kind;
    _onChanged();
  }

  void _addField() {
    _fieldCtrls.add(_newFieldController());
    _onChanged();
  }

  void _removeField(int index) {
    _fieldCtrls.removeAt(index).dispose();
    _onChanged();
  }

  void _moveField(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _fieldCtrls.length) return;
    final field = _fieldCtrls.removeAt(index);
    _fieldCtrls.insert(target, field);
    _onChanged();
  }

  /// The head's trash action. A stored snippet goes to the trash (with
  /// undo, from the page); a new one, never stored, is thrown away after a
  /// confirmation, so it is never one stray click.
  Future<void> _delete() async {
    if (_id != null) {
      _abandoned = true;
      _autosave?.cancel();
      ref.read(snippetDraftsProvider.notifier).clear(_draftKey);
      widget.onDelete?.call();
      return;
    }
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
    _abandoned = true;
    _autosave?.cancel();
    ref.read(snippetDraftsProvider.notifier).clear(kNewSnippetDraftKey);
    widget.onClose();
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
    TextUndoController.command(
      _bodyCtrl,
      () => _bodyCtrl.text = text.replaceRange(start, end, placeholder),
    );
    _bodyCtrl.selection = TextSelection.collapsed(
      offset: start + placeholder.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    if (id != null) {
      ref.watch(contentMetadataProvider((kind: ContentKind.snippet, id: id)));
    }
    final l10n = L10n.of(context);
    return Semantics(
      identifier: 'snippets-editor',
      container: true,
      explicitChildNodes: true,
      // The page ignores keys while a text field has focus, so the editor
      // answers Esc and Ctrl/Cmd+S itself. Esc saves a valid change first
      // and keeps an invalid one as the draft.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          // The same platform-aware save key the editor block binds.
          WpTextEditor.saveActivator: () => unawaited(_save()),
        },
        // The shared editor pane (#1498). Only the interactive form (field
        // list plus template) scrolls. A static snippet is one document: its
        // editor fills the rest of the pane like the note's, so the status
        // line sits at the bottom edge instead of below the fold.
        child: WpEditorPane(
          head: _header(l10n),
          notices: [
            ?_invalidNotice(l10n),
            // Back after a jump, links to and from this snippet (#660).
            if (id != null)
              EntryLinksSection(
                key: ValueKey('snippets-editor-links-$id'),
                entry: (kind: ContentKind.snippet, id: id),
                testId: 'snippets-editor',
              ),
          ],
          bodyMode: _isInteractive
              ? WpEditorPaneBody.scroll
              : WpEditorPaneBody.fill,
          meta: _meta(l10n),
          editor: _bodyEditor(
            _isInteractive
                ? l10n.snippetsTemplateFieldHint
                : l10n.snippetsBodyHint,
          ),
          extras: _extras(l10n, Theme.of(context)),
          footer: Text(
            l10n.snippetsDialogHint,
            key: const ValueKey('snippets-editor-hint'),
            style: TextStyle(
              color: WpColors.textMuted,
              fontSize: WpTypography.caption,
            ),
          ),
        ),
      ),
    );
  }

  /// Why the current state is not stored, at the pane (#1498). Only after a
  /// save met it (the pause, Ctrl/Cmd+S, closing), never while the first
  /// keystrokes of a new snippet are on their way. A stored snippet offers
  /// the way back to its stored state.
  Widget? _invalidNotice(L10n l10n) {
    if (!_showInvalid || _isValid) return null;
    final reason = _invalidReason(l10n);
    if (reason == null) return null;
    return Padding(
      padding: WpEditorPane.sideInset,
      child: Semantics(
        identifier: 'snippets-editor-invalid',
        liveRegion: true,
        child: WpBanner(
          key: const ValueKey('snippets-editor-invalid'),
          tone: WpBannerTone.warning,
          message: l10n.snippetsNotSaved(reason),
          action: _saved == null
              ? null
              : WpButton(
                  testId: 'snippets-editor-revert',
                  label: l10n.snippetsRevertToSaved,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: _revert,
                ),
        ),
      ),
    );
  }

  /// Width from which the kind choice sits beside the title field instead of
  /// below it.
  static const double _kindInlineMinWidth = 520;
  static const double _kindChoiceWidth = 240;

  /// The shared editor head (#1498), the note's and the recording's: the
  /// title field IS the head, in the heading style without a frame at rest,
  /// the kind choice sits beside it where the width allows, then the actions
  /// in the notes' order (copy, star, trash, the … menu, close). The heading
  /// survives for screen readers only.
  Widget _header(L10n l10n) {
    final isStored = _id != null;
    final title = Row(
      children: [
        Semantics(
          header: true,
          label: isStored ? l10n.snippetsEditSnippet : l10n.snippetsNewSnippet,
          child: const SizedBox.shrink(),
        ),
        Expanded(
          child: WpTextField(
            key: const ValueKey('snippets-title-field'),
            controller: _titleCtrl,
            focusNode: _titleFocus,
            variant: WpTextFieldVariant.heading,
            semanticsLabel: l10n.snippetsTitleLabel,
            // An existing snippet opens where it was left, in its body (#678).
            autofocus: widget.existing == null,
            hintText: l10n.snippetsTitleHint,
            onSubmitted: (_) => unawaited(_save()),
          ),
        ),
      ],
    );
    final kind = WpSegmentedChoice<String>(
      key: const ValueKey('snippets-kind-choice'),
      height: WpIconButton.compactExtent,
      options: [
        WpSegmentOption(value: 'static', label: l10n.snippetsKindStatic),
        WpSegmentOption(
          value: 'interactive',
          label: l10n.snippetsKindInteractive,
        ),
      ],
      selected: _kind,
      onChanged: _setKind,
    );
    final existing = widget.existing;
    final actions = <Widget>[
      // An interactive snippet's body is a template, not final text —
      // nothing to copy, same rule as the row.
      if (isStored && !_isInteractive && widget.onCopy != null)
        WpIconButton.ghost(
          compact: true,
          testId: 'snippets-detail-copy',
          icon: LucideIcons.copy,
          tooltip: l10n.historyCopyText,
          onPressed: () => widget.onCopy!(_bodyCtrl.text),
        ),
      if (isStored && existing != null)
        WpFavouriteStar.head(
          testId: 'snippets-detail-favourite',
          isFavourite: existing.isFavorite,
          onToggle: widget.onToggleFavourite,
        ),
      // Trash a stored snippet; throw away a new one (with a question).
      WpIconButton.ghost(
        compact: true,
        testId: 'snippets-detail-delete',
        icon: LucideIcons.trash2,
        tooltip: isStored ? l10n.actionDelete : l10n.unsavedInputDiscard,
        onPressed: () => unawaited(_delete()),
      ),
    ];
    final menu = !isStored
        ? null
        : WpHeadMenuButton<String>(
            testId: 'snippets-detail-more',
            tooltip: l10n.historyMoreActions,
            onSelected: (value) => switch (value) {
              'duplicate' => widget.onDuplicate?.call(),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                key: const ValueKey('snippets-detail-duplicate'),
                value: 'duplicate',
                enabled: widget.onDuplicate != null,
                child: Semantics(
                  identifier: 'snippets-detail-duplicate',
                  child: WpMenuRow(
                    icon: LucideIcons.files,
                    label: l10n.actionDuplicate,
                  ),
                ),
              ),
            ],
          );
    final close = WpIconButton.ghost(
      compact: true,
      testId: 'snippets-editor-close',
      icon: LucideIcons.x,
      tooltip: '${l10n.actionClose} (Esc)',
      onPressed: _close,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            constraints.maxWidth - WpEditorHead.padding.horizontal >=
            _kindInlineMinWidth;
        return WpEditorHead(
          title: title,
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inline) ...[
                SizedBox(width: _kindChoiceWidth, child: kind),
                const SizedBox(width: WpSpacing.sm),
              ],
              WpHeadActions(actions: actions, menu: menu, close: close),
            ],
          ),
          below: inline ? null : kind,
        );
      },
    );
  }

  /// The pane's meta row: the failed-save banner, or nothing.
  Widget? _meta(L10n l10n) {
    final saveFailed = _saveFailed;
    if (saveFailed == null) return _sourceNote(l10n);
    return Semantics(
      identifier: 'snippets-editor-save-failed',
      liveRegion: true,
      child: WpBanner(
        key: const ValueKey('snippets-editor-save-failed'),
        tone: WpBannerTone.error,
        message: saveFailed,
      ),
    );
  }

  /// The back-reference to the note this snippet was saved from (#664), or
  /// nothing.
  Widget? _sourceNote(L10n l10n) {
    final title = _sourceNoteTitle;
    if (title == null) return null;
    return Semantics(
      identifier: 'snippets-editor-source-note',
      child: Row(
        key: const ValueKey('snippets-editor-source-note'),
        children: [
          Icon(
            LucideIcons.notebookPen,
            size: WpIconSize.xs,
            color: WpColors.textMuted,
          ),
          const SizedBox(width: WpSpacing.xxs),
          Flexible(
            child: Text(
              l10n.snippetSourceNote(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.small,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The pane's extras below the editor (#1498): warnings about the text
  /// first, right under it; for an interactive snippet then the template
  /// hint and the field list. Title and kind (Static / Interactive,
  /// interactive-snippets PRD) live in the compact head, see [_header].
  List<Widget> _extras(L10n l10n, ThemeData theme) {
    final caption = TextStyle(
      color: WpColors.textMuted,
      fontSize: WpTypography.caption,
    );
    final warning = TextStyle(
      color: WpColors.warning,
      fontSize: WpTypography.caption,
    );
    return [
      if (_isInteractive && !_templateReferencesAllFields)
        Text(l10n.snippetsTemplateMissingFieldsWarning, style: warning),
      // Unknown `{$name}` variables stay in the text; warn, never block (#663).
      if (unknownSystemVariables(_bodyCtrl.text) case final unknown
          when unknown.isNotEmpty)
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.snippetsUnknownVariablesWarning(
              unknown.join(', '),
              systemVariableNames.map((n) => '{\$$n}').join(', '),
            ),
            key: const ValueKey('snippets-unknown-variables-warning'),
            style: warning,
          ),
        ),
      if (_isInteractive) ...[
        Text(l10n.snippetsTemplateHint, style: caption),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _fieldEditor(l10n, theme, caption, warning),
        ),
      ],
    ];
  }

  /// The app's one editor block (#638), same toolbar, undo, counter and
  /// Ctrl/Cmd+S as the transcript and the note. Static, it expands into the
  /// pane; interactive, the form scrolls, so the line count does the growing.
  Widget _bodyEditor(String hint) => Listener(
    onPointerDown: (_) => _pointerOnBody = true,
    onPointerUp: (_) => _releasePointer(),
    onPointerCancel: (_) => _releasePointer(),
    child: WpTextEditor(
      key: const ValueKey('snippets-body-editor'),
      testId: 'snippets-body',
      fieldKey: const ValueKey('snippets-body-field'),
      controller: _bodyCtrl,
      focusNode: _bodyFocus,
      // The transcript's surface (#1498): no frame at rest, the focus ring
      // only while typing, same radius as the note and the recording. It is
      // the pane's editor slot and draws the page inset itself.
      variant: WpTextFieldVariant.passage,
      hintText: hint,
      semanticsLabel: _isInteractive
          ? L10n.of(context).snippetsTemplateLabel
          : L10n.of(context).snippetsBodyLabel,
      // No line cap (#664): the form scrolls, so long templates grow freely.
      minLines: _isInteractive ? 10 : null,
      expands: !_isInteractive,
      onSave: () => unawaited(_save()),
      saveStatus: _saveStatus,
      onInsertSnippet: widget.onInsertSnippet == null ? null : _insertSnippet,
      toolbarTrailing: widget.tags,
      // `[[` opens the link chooser (#660).
      onPickLink: () => pickEntryLinkText(
        context,
        except: switch (widget.existing) {
          final existing? => (kind: EntryLinkKind.snippet, id: existing.id),
          null => null,
        },
      ),
      // A snippet not yet saved has no row to remember a place for (#678).
      viewMemory: switch (widget.existing) {
        final existing? => (kind: ContentKind.snippet, id: existing.id),
        null => null,
      },
    ),
  );

  /// Named-field editor for an `interactive` snippet — add/rename/reorder/
  /// remove, at least [_minFields] fields (PRD User Stories 3/4). Reordering
  /// is up/down buttons rather than drag-and-drop, keyboard-reachable.
  List<Widget> _fieldEditor(
    L10n l10n,
    ThemeData theme,
    TextStyle caption,
    TextStyle warning,
  ) {
    return [
      Text(l10n.snippetsFieldsLabel, style: theme.textTheme.titleSmall),
      const SizedBox(height: WpSpacing.xxs),
      Text(l10n.snippetsFieldsHint, style: caption),
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
              WpIconButton.ghost(
                compact: true,
                key: const ValueKey('snippets-field-insert'),
                testId: 'snippets-field-insert-$i',
                icon: LucideIcons.plus,
                tooltip: l10n.snippetsFieldInsertIntoTemplate,
                onPressed: _fieldCtrls[i].text.trim().isEmpty
                    ? null
                    : () => _insertFieldPlaceholder(_fieldCtrls[i].text.trim()),
              ),
              WpIconButton.ghost(
                compact: true,
                key: ValueKey('snippets-field-move-up-$i'),
                testId: 'snippets-field-move-up-$i',
                icon: LucideIcons.chevronUp,
                tooltip: l10n.snippetsFieldMoveUp,
                onPressed: i > 0 ? () => _moveField(i, -1) : null,
              ),
              WpIconButton.ghost(
                compact: true,
                key: ValueKey('snippets-field-move-down-$i'),
                testId: 'snippets-field-move-down-$i',
                icon: LucideIcons.chevronDown,
                tooltip: l10n.snippetsFieldMoveDown,
                onPressed: i < _fieldCtrls.length - 1
                    ? () => _moveField(i, 1)
                    : null,
              ),
              WpIconButton.ghost(
                compact: true,
                key: ValueKey('snippets-field-remove-$i'),
                testId: 'snippets-field-remove-$i',
                icon: LucideIcons.x,
                tooltip: l10n.snippetsFieldRemove,
                onPressed: _fieldCtrls.length > _minFields
                    ? () => _removeField(i)
                    : null,
              ),
            ],
          ),
        ),
      WpButton(
        key: const ValueKey('snippets-field-add'),
        label: l10n.snippetsFieldAdd,
        variant: WpButtonVariant.ghost,
        size: WpButtonSize.dense,
        onPressed: _addField,
      ),
      if (!_fieldsValid) ...[
        const SizedBox(height: WpSpacing.xxs),
        Text(l10n.snippetsFieldsMinWarning(_minFields), style: warning),
      ],
      if (!_fieldNamesUnique) ...[
        const SizedBox(height: WpSpacing.xxs),
        Text(l10n.snippetsFieldsDuplicateWarning, style: warning),
      ],
    ];
  }
}
