import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_row_action.dart';
import '../../widgets/dialog.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_text_field.dart';
import '../settings/settings_widgets.dart';
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
      // macOS-only for now (ticket 06) — Windows/Linux land in tickets 07/08.
      // Without this guard the field would still render there, but setting
      // it would silently type the trigger word into the user's document as
      // literal text (createSnippetPickerController() is null, so dispatch
      // falls through to the normal pipeline) instead of opening a picker.
      header: Platform.isMacOS
          ? _SnippetPickerTriggerField(
              trigger: trigger,
              ref: ref,
              showEmptyListHint: trigger.trim().isNotEmpty && !hasSnippets,
            )
          : null,
      asyncAll: ref.watch(snippetsProvider),
      searchMatches: (s, q) =>
          q.hasMatch(s.title) || q.hasMatch(s.body),
      searchHint: l10n.snippetsSearch,
      addLabel: l10n.snippetsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(snippetsProvider),
      emptyIcon: LucideIcons.notebookText,
      emptyTitle: l10n.snippetsEmpty,
      emptyHint: l10n.snippetsEmptyHint,
      emptyActionLabel: l10n.snippetsAdd,
      noMatchesTitle: l10n.snippetsNoMatches,
      noMatchesHint: l10n.snippetsNoMatchesHint,
      itemBuilder: (context, s, isDark) {
        // loam-ignore: a11y-interactive-semantics – semantics provided in _SnippetTileState.build
        return _SnippetTile(
          snippet: s,
          isDark: isDark,
          onTap: () => _showAddEditDialog(existing: s),
          onDelete: () => _confirmDelete(s),
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
// Picker trigger word (dictation-automations ticket 06)
// ---------------------------------------------------------------------------

/// Header card above the snippet list: the single global trigger word that
/// opens the Snippet-Picker when a transcript matches it exactly.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.sm,
        WpSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
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
                    Icon(
                      LucideIcons.triangleAlert,
                      size: WpIconSize.xs,
                      color: isDark
                          ? WpColorsDark.warning
                          : WpColorsLight.warning,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Expanded(
                      child: Text(
                        l10n.snippetsPickerTriggerEmptyListHint,
                        style: TextStyle(
                          color: isDark
                              ? WpColorsDark.warning
                              : WpColorsLight.warning,
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
  late final TextEditingController _bodyCtrl;

  bool get _isValid =>
      _titleCtrl.text.trim().isNotEmpty && _bodyCtrl.text.trim().isNotEmpty;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _bodyCtrl = TextEditingController(text: widget.existing?.body ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
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

        // Body (multi-line)
        Text(l10n.snippetsBodyLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: WpSpacing.xxs),
        WpTextField(
          controller: _bodyCtrl,
          variant: WpTextFieldVariant.form,
          hintText: l10n.snippetsBodyHint,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
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
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  final SnippetItem snippet;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends State<_SnippetTile> {
  bool _isHovered = false;
  bool _isFocused = false;

  /// The row is "active" for pointer and for keyboard alike — the
  /// delete action is revealed by either, so a keyboard user can reach
  /// it at all (an unmounted button cannot be focused).
  bool get _isActive => _isHovered || _isFocused;

  /// Single-line preview of the body — newlines and runs of whitespace
  /// collapse to single spaces so the ellipsis works on one visual line.
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
            child: AnimatedContainer(
              duration: WpMotion.durationFor(
                context,
                _isActive ? WpMotion.hoverIn : WpMotion.hoverOut,
              ),
              curve: WpMotion.defaultCurve,
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: _isActive
                    ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
                    : (widget.isDark
                          ? WpColorsDark.surfaceElevated
                          : WpColorsLight.surfaceElevated),
                borderRadius: WpRadius.borderMd,
                border: Border.all(
                  color: _isActive
                      ? (widget.isDark
                            ? WpColorsDark.glassBorder
                            : WpColorsLight.borderDefault)
                      : (widget.isDark
                            ? WpColorsDark.borderSubtle
                            : WpColorsLight.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.notebookText,
                    size: WpIconSize.sm,
                    color: widget.isDark
                        ? WpColorsDark.accent
                        : WpColorsLight.accent,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.snippet.title,
                          style: TextStyle(
                            color: widget.isDark
                                ? WpColorsDark.textPrimary
                                : WpColorsLight.textPrimary,
                            fontSize: WpTypography.body,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: WpSpacing.xxs),
                        Text(
                          _bodyPreview,
                          style: TextStyle(
                            color: widget.isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                            fontSize: WpTypography.small,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  WpRowActions(
                    visible: _isActive,
                    children: [
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                      WpRowAction(
                        icon: LucideIcons.trash2,
                        tooltip: L10n.of(context).actionDelete,
                        isDark: widget.isDark,
                        onTap: widget.onDelete,
                        isDestructive: true,
                      ),
                    ],
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
