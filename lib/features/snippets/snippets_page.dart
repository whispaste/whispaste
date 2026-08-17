import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/snippet_picker/snippet_picker_controller.dart';
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
import '../../widgets/wp_button.dart';
import '../../widgets/wp_text_field.dart';
import '../settings/hotkey_flow.dart';
import '../settings/settings_widgets.dart';
import '../settings/snippet_picker_hotkey_flow.dart';
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
  });

  final String id;
  final String title;
  final String body;
}

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

class SnippetsNotifier extends AsyncNotifier<List<SnippetItem>>
    with ReloadableListNotifier<SnippetItem> {
  @override
  Future<List<SnippetItem>> readAll() async {
    final db = ref.read(historyDatabaseProvider);
    return (await db.readAllSnippets()).map(_fromDb).toList();
  }

  @override
  Future<List<SnippetItem>> build() => readAll();

  // Deliberately not further extracted: shares its "generate a uuid,
  // upsert, reload" shape with ReplacementsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  Future<void> add(String title, String body) async {
    final db = ref.read(historyDatabaseProvider);
    final id = generateV4Uuid();
    await db.upsertSnippet(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime.now(),
    );
    await reload();
  }

  Future<void> updateSnippet(
    String id, {
    required String title,
    required String body,
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertSnippet(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime.now(),
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
    await db.deleteAllSnippets();
    final now = DateTime.now();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      await db.upsertSnippet(
        id: '${now.millisecondsSinceEpoch}_$i',
        title: item.title,
        body: item.body,
        createdAt: now,
      );
    }
    await reload();
  }

  static SnippetItem _fromDb(Snippet row) =>
      SnippetItem(id: row.id, title: row.title, body: row.body);
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
    final trigger =
        ref.watch(settingsProvider).value?.behavior.snippetPickerTrigger ?? '';
    // `?? true` while the list is still loading — the "trigger does nothing
    // yet" warning must not flash before the first read lands.
    final hasSnippets = ref.watch(snippetsProvider).value?.isNotEmpty ?? true;

    return WpSearchableListPage<SnippetItem>(
      header: _SnippetPickerHeader(
        trigger: trigger,
        pageRef: ref,
        showEmptyListHint: trigger.trim().isNotEmpty && !hasSnippets,
      ),
      asyncAll: ref.watch(snippetsProvider),
      searchMatches: (s, q) =>
          q.hasMatch(s.title) || q.hasMatch(s.body),
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
          snippet: s,
          isCursor: isCursor,
          onTap: () => _showAddEditDialog(existing: s),
          onDelete: () => _confirmDelete(s),
          onCopy: () => _copySnippet(s),
        );
      },
    );
  }

  // ── Add / Edit dialog ────────────────────────────────────────────────

  // Deliberately not further extracted into an onCreate/onUpdate-callback
  // helper: tried it, the result was longer than the original and replaced
  // the direct `final (title, body) = result;` destructuring with closure
  // indirection — net readability loss, so this stays as-is (unlike the
  // dialog-scaffold + delete flow, which extracted cleanly into
  // WpSearchableListPage/showWpDeleteConfirmDialog).
  Future<void> _showAddEditDialog({SnippetItem? existing}) async {
    final result = await showWpFormDialog<(String, String)>(
      context: context,
      builder: (_, a) => _SnippetDialog(animation: a, existing: existing),
    );
    if (result == null) return;
    final (title, body) = result;
    final notifier = ref.read(snippetsProvider.notifier);
    if (existing != null) {
      notifier.updateSnippet(existing.id, title: title, body: body);
    } else {
      notifier.add(title, body);
      ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'snippets', action: 'create');
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

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(SnippetItem s) {
    final l10n = L10n.of(context);
    return showWpDeleteConfirmDialog(
      context: context,
      title: l10n.snippetsDeleteTitle,
      message: l10n.snippetsDeleteMessage(s.title),
      onConfirm: () => ref.read(snippetsProvider.notifier).remove(s.id),
    );
  }
}

// ---------------------------------------------------------------------------
// Picker header card: trigger word (ticket 06) + hotkey (ticket 27)
// ---------------------------------------------------------------------------

/// Header card above the snippet list — everything about *getting to* the
/// Snippet-Picker, in one place above the snippets themselves.
///
/// Both ways in stand here together on purpose: the spoken trigger word and
/// the key combination are not two features but two doors to the same panel,
/// and whoever is maintaining their snippets is exactly the person asking
/// "how do I call these up again?". Sending them to Settings for one of the
/// two answers is the trip this card exists to save.
///
/// Where the platform has no native picker at all, the card says so instead
/// of offering either — the availability answer comes from
/// [snippetPickerAvailabilityProvider], the same one the settings row reads
/// (ticket 26/27), so tickets 29/30 flip one getter and both places follow.
class _SnippetPickerHeader extends ConsumerWidget {
  const _SnippetPickerHeader({
    required this.trigger,
    required this.pageRef,
    required this.showEmptyListHint,
  });

  final String trigger;

  /// The page's own [WidgetRef] — the trigger field commits through it.
  final WidgetRef pageRef;

  final bool showEmptyListHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final available = ref.watch(snippetPickerAvailabilityProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.sm,
        WpSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
        // Card material, not the flat `surfaceElevated` it used to be: this
        // header is a plate on the content plane like every list row below
        // it, and the frost fill lets the one ambient gradient keep running
        // underneath instead of cutting an opaque band across the page.
        decoration: BoxDecoration(
          color: WpColors.cardFill,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: available
              ? [
                  _SnippetPickerTriggerField(
                    trigger: trigger,
                    ref: pageRef,
                    showEmptyListHint: showEmptyListHint,
                  ),
                  const _SnippetPickerHotkeyRow(),
                ]
              : [
                  // Ganz bewusst kein abgeblendeter Umschalter und kein
                  // Eingabefeld: hier ist nichts einzustellen, und der
                  // Trigger würde ohne Picker still als normaler Text
                  // eingefügt. Derselbe Satz wie in den Einstellungen.
                  Padding(
                    key: const Key('snippetsPickerUnavailable'),
                    padding: const EdgeInsets.fromLTRB(
                      WpSpacing.md,
                      WpSpacing.sm,
                      WpSpacing.md,
                      WpSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          LucideIcons.info,
                          size: WpIconSize.xs,
                          color: WpColors.textMuted,
                        ),
                        const SizedBox(width: WpSpacing.xs),
                        Expanded(
                          child: Text(
                            l10n.snippetsPickerUnavailable,
                            style: const TextStyle(
                              color: WpColors.textMuted,
                              fontSize: WpTypography.small,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}

/// The single global trigger word that opens the Snippet-Picker when a
/// transcript matches it exactly.
///
/// Lives on this page (not in Settings) because the trigger only matters in
/// the context of Snippets. Empty string means the picker is off — the
/// subtitle copy spells that out so the off-state is legible at a glance.
/// Debounced-commit shape copied from `_AutoPasteBlocklistField`.
class _SnippetPickerTriggerField extends StatefulWidget {
  const _SnippetPickerTriggerField({
    required this.trigger,
    required this.ref,
    required this.showEmptyListHint,
  });

  final String trigger;
  final WidgetRef ref;

  /// True when a trigger word is set but the snippet list is empty — the
  /// trigger currently does nothing (dictating it falls through to a normal
  /// paste), which this card must say out loud instead of letting the user
  /// discover it mid-dictation.
  final bool showEmptyListHint;

  @override
  State<_SnippetPickerTriggerField> createState() =>
      _SnippetPickerTriggerFieldState();
}

class _SnippetPickerTriggerFieldState
    extends State<_SnippetPickerTriggerField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.trigger);
  }

  @override
  void didUpdateWidget(_SnippetPickerTriggerField old) {
    super.didUpdateWidget(old);
    // External change (e.g. settings import) — not an echo of our own commit.
    if (old.trigger != widget.trigger && widget.trigger != _controller.text) {
      _controller.text = widget.trigger;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      // Raw value on purpose: the dispatcher normalizes both sides via
      // `normalizeForExactMatch` (see `snippet_picker_dispatch.dart`).
      widget.ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              behavior: s.behavior.copyWith(snippetPickerTrigger: value),
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingRow(
          icon: LucideIcons.audioLines,
          label: l10n.snippetsPickerTriggerLabel,
          subtitle: l10n.snippetsPickerTriggerSubtitle,
          trailing: settingsTextField(
            context: context,
            controller: _controller,
            hintText: l10n.snippetsPickerTriggerHint,
            onChanged: _onChanged,
            semanticLabel: l10n.snippetsPickerTriggerLabel,
          ),
        ),
        if (widget.showEmptyListHint)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.md,
              WpSpacing.xxs,
              WpSpacing.md,
              WpSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  size: WpIconSize.xs,
                  color: WpColors.warning,
                ),
                const SizedBox(width: WpSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.snippetsPickerTriggerEmptyListHint,
                    style: const TextStyle(
                      color: WpColors.warning,
                      fontSize: WpTypography.small,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Picker hotkey line (ticket 27)
// ---------------------------------------------------------------------------

/// The key combination that opens the Snippet-Picker — second call site of the
/// settings flow, not a second setting.
///
/// It reads [settingsProvider] and writes through [recordSnippetPickerHotkey]:
/// the same dialog, the same collision check, the same stored state the
/// Settings page shows. Deliberately subordinate — one row in the header card,
/// no toggle of its own, no notice the picker itself does not need; this stays
/// a snippets screen rather than becoming half a settings page. The switch
/// lives in Settings, but a hotkey that is off can be turned on from right
/// here, because "it does nothing and this page won't say why" is exactly the
/// dead end the row exists to prevent.
class _SnippetPickerHotkeyRow extends ConsumerStatefulWidget {
  const _SnippetPickerHotkeyRow();

  @override
  ConsumerState<_SnippetPickerHotkeyRow> createState() =>
      _SnippetPickerHotkeyRowState();
}

class _SnippetPickerHotkeyRowState
    extends ConsumerState<_SnippetPickerHotkeyRow>
    with HotkeyCollisionNotice {
  Future<void> _record(AppSettings settings) => recordAndReport(
    () => recordSnippetPickerHotkey(
      context: context,
      ref: ref,
      settings: settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Solange die Einstellungen nicht geladen sind, behauptet die Zeile
    // nichts — weder eine Kombination noch „ausgeschaltet". Beides wäre
    // geraten.
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();

    final hotkey = settings.snippetPickerHotkey;
    final enabled = hotkey.snippetPickerHotkeyEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingRow(
          icon: LucideIcons.keyboard,
          label: l10n.snippetsPickerHotkeyLabel,
          // Eingeschaltet sagt die Unterzeile, wozu die Kombination gut ist
          // („der zweite Weg zum selben Panel") — ausgeschaltet ist sie die
          // ganze Auskunft, die diesen Zustand überhaupt erklärt.
          subtitle: enabled
              ? l10n.snippetsPickerHotkeySubtitle
              : l10n.snippetsPickerHotkeyOff,
          trailing: enabled
              ? const SizedBox.shrink()
              // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
              : WpButton(
                  key: const Key('snippetsPickerHotkeyEnable'),
                  label: l10n.snippetsPickerHotkeyEnable,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: () => unawaited(
                    setSnippetPickerHotkeyEnabled(ref, enabled: true),
                  ),
                ),
        ),
        if (enabled)
          HotkeyComboLine(
            key: const Key('snippetsPickerHotkeyComboLine'),
            label: l10n.settingsSnippetPickerCurrentHotkey,
            hotkeyKey: hotkey.snippetPickerHotkeyKey,
            hotkeyModifiers: hotkey.snippetPickerHotkeyModifiers,
            hotkeyKeyDisplay: hotkey.snippetPickerHotkeyKeyDisplay,
            changeButtonKey: const Key('snippetsPickerHotkeyChange'),
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.md,
              0,
              WpSpacing.md,
              WpSpacing.sm,
            ),
            onChange: () => unawaited(_record(settings)),
          ),
        if (collidingAction != null)
          Padding(
            key: const Key('snippetsPickerHotkeyCollisionNotice'),
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.md,
              0,
              WpSpacing.md,
              WpSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.circleAlert,
                  size: WpIconSize.xs,
                  color: WpColors.error,
                ),
                const SizedBox(width: WpSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.settingsSnippetPickerHotkeyCollision(collidingAction!),
                    style: const TextStyle(
                      color: WpColors.error,
                      fontSize: WpTypography.small,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit dialog
// ---------------------------------------------------------------------------

class _SnippetDialog extends StatefulWidget {
  const _SnippetDialog({required this.animation, this.existing});

  final Animation<double> animation;
  final SnippetItem? existing;

  @override
  State<_SnippetDialog> createState() => _SnippetDialogState();
}

class _SnippetDialogState extends State<_SnippetDialog> {
  late final TextEditingController _titleCtrl;
  late final WpFindHighlightController _bodyCtrl;
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'snippetBody');

  bool get _isValid =>
      _titleCtrl.text.trim().isNotEmpty && _bodyCtrl.text.trim().isNotEmpty;

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
  }

  @override
  void dispose() {
    _bodyCtrl.removeListener(_onBodyChanged);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    if (mounted) setState(() {});
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop((_titleCtrl.text.trim(), _bodyCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return WpFormDialogShell(
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
          controller: _titleCtrl,
          variant: WpTextFieldVariant.form,
          autofocus: true,
          hintText: l10n.snippetsTitleHint,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: WpSpacing.md),

        // Body (multi-line) — same toolbar the History transcript editor and
        // the Notes editor carry, so bold/italic/lists and find-and-replace
        // work identically wherever text is written in this app.
        Text(l10n.snippetsBodyLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: WpSpacing.xxs),
        WpMarkdownToolbar(controller: _bodyCtrl, focusNode: _bodyFocus),
        const SizedBox(height: WpSpacing.xs),
        // No Expanded/Flexible here on purpose: WpFormDialogShell puts its
        // fields inside a SingleChildScrollView, so an unbounded height would
        // be a layout exception. The line count does the growing instead, and
        // the card's own viewport clamp keeps it on screen.
        CallbackShortcuts(
          bindings: WpMarkdownFormatting(
            controller: _bodyCtrl,
            focusNode: _bodyFocus,
          ).shortcutBindings(),
          child: WpTextField(
            controller: _bodyCtrl,
            focusNode: _bodyFocus,
            variant: WpTextFieldVariant.form,
            hintText: l10n.snippetsBodyHint,
            minLines: 10,
            maxLines: 18,
          ),
        ),
      ],
      actions: [
        // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
        WpButton(
          label: l10n.actionCancel,
          variant: WpButtonVariant.ghost,
          tone: WpButtonTone.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: WpSpacing.sm),
        // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
        WpButton(
          label: _isEditing ? l10n.actionSave : l10n.snippetsAdd,
          variant: WpButtonVariant.primary,
          onPressed: _isValid ? _submit : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Snippet tile
// ---------------------------------------------------------------------------

class _SnippetTile extends StatefulWidget {
  const _SnippetTile({
    required this.snippet,
    required this.isCursor,
    required this.onTap,
    required this.onDelete,
    required this.onCopy,
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
  String get _bodyPreview =>
      widget.snippet.body.trim().replaceAll(RegExp(r'\s+'), ' ');

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
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                  WpRowAction(
                    icon: LucideIcons.copy,
                    tooltip: L10n.of(context).actionCopy,
                    onTap: widget.onCopy,
                  ),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                  WpRowAction(
                    icon: LucideIcons.trash2,
                    tooltip: L10n.of(context).actionDelete,
                    onTap: widget.onDelete,
                    isDestructive: true,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.notebookText,
                    size: WpIconSize.sm,
                    color: WpColors.accent,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.snippet.title,
                          style: const TextStyle(
                            color: WpColors.textPrimary,
                            fontSize: WpTypography.body,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: WpSpacing.xxs),
                        Text(
                          _bodyPreview,
                          style: const TextStyle(
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
