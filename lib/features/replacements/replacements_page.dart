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
import '../../widgets/trigger_chip.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_text_field.dart';
import '../settings/settings_widgets.dart' show SettingRow, settingsToggle;
import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class Replacement {
  const Replacement({
    required this.id,
    required this.triggers,
    required this.replacement,
  });

  final String id;

  /// Every trigger phrase that fires this replacement. Always non-empty.
  final List<String> triggers;
  final String replacement;
}

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

class ReplacementsNotifier extends AsyncNotifier<List<Replacement>>
    with ReloadableListNotifier<Replacement> {
  @override
  Future<List<Replacement>> readAll() async {
    final db = ref.read(historyDatabaseProvider);
    return (await db.readAllReplacements()).map(_fromDb).toList();
  }

  @override
  Future<List<Replacement>> build() async {
    final db = ref.read(historyDatabaseProvider);
    final rows = await db.readAllReplacements();
    if (rows.isEmpty) {
      await _insertSampleData(db);
      return readAll();
    }
    return rows.map(_fromDb).toList();
  }

  Future<void> _insertSampleData(HistoryDatabase db) async {
    final now = DateTime.now();
    const samples = [
      ('mfg', 'Mit freundlichen Grüßen'),
      ('lg', 'Liebe Grüße'),
      ('tel', '+49 123 456789'),
    ];
    for (final (trigger, replacement) in samples) {
      final id = '${now.millisecondsSinceEpoch}_$trigger';
      await db.upsertReplacementWithTriggers(
        id: id,
        triggers: [trigger],
        replacement: replacement,
        createdAt: now,
      );
    }
  }

  // Deliberately not further extracted: shares its "generate a uuid,
  // upsert, reload" shape with SnippetsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  Future<void> add(List<String> triggers, String replacement) async {
    final db = ref.read(historyDatabaseProvider);
    final id = generateV4Uuid();
    await db.upsertReplacementWithTriggers(
      id: id,
      triggers: triggers,
      replacement: replacement,
      createdAt: DateTime.now(),
    );
    await reload();
  }

  Future<void> updateReplacement(
    String id, {
    required List<String> triggers,
    required String replacement,
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertReplacementWithTriggers(
      id: id,
      triggers: triggers,
      replacement: replacement,
      createdAt: DateTime.now(),
    );
    await reload();
  }

  Future<void> remove(String id) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteReplacement(id);
    await reload();
  }

  /// Replaces the entire set of replacements with [items] — used by settings
  /// import (Cluster 5 portability) so the imported file becomes the exact
  /// new contents rather than being merged with existing entries.
  // Deliberately not further extracted: shares its "clear, loop with an
  // index-ordered id, upsert, reload" shape with SnippetsNotifier.replaceAll;
  // same closure-indirection trade-off as [add] above, evaluated and
  // rejected for the same reason.
  Future<void> replaceAll(List<Replacement> items) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteAllReplacements();
    final now = DateTime.now();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      await db.upsertReplacementWithTriggers(
        id: '${now.millisecondsSinceEpoch}_$i',
        triggers: item.triggers,
        replacement: item.replacement,
        createdAt: now,
      );
    }
    await reload();
  }

  static Replacement _fromDb(ReplacementWithTriggers joined) => Replacement(
    id: joined.row.id,
    triggers: joined.triggers,
    replacement: joined.row.replacement,
  );
}

final replacementsProvider =
    AsyncNotifierProvider<ReplacementsNotifier, List<Replacement>>(
      ReplacementsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Replacements page — auto-replace words during dictation.
class ReplacementsPage extends ConsumerStatefulWidget {
  const ReplacementsPage({super.key});

  @override
  ConsumerState<ReplacementsPage> createState() => _ReplacementsPageState();
}

class _ReplacementsPageState extends ConsumerState<ReplacementsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value;
    final enabled = settings?.textReplacementsEnabled ?? true;

    return WpSearchableListPage<Replacement>(
      // The master switch lives in a header card, not in the toolbar.
      //
      // In the toolbar it was a bare `Text` next to an unlabelled `Switch`:
      // measured on the semantics tree, the switch node carried an empty
      // label while its caption merged into the page-level focus node far
      // away from it — a screen reader announced "switch, on" with no clue
      // what it switches. It also broke the house tooltip rule by putting a
      // Tooltip on a control that already had a visible caption.
      //
      // `SettingRow` is the shape the app already uses for "labelled control
      // with an explanatory subtitle", it names the switch correctly by
      // construction (see no_double_announcement_test), and it puts this
      // screen's own setting exactly where the sibling Snippets screen puts
      // its picker-trigger field. That leaves all three screens with the
      // same toolbar: search plus the add button, nothing else.
      //
      // Unlike the Snippets header this one is not platform-gated —
      // replacements run on all three platforms.
      header: _ReplacementsToggleCard(
        enabled: enabled,
        onChanged: (v) => ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(textReplacementsEnabled: v)),
      ),
      asyncAll: ref.watch(replacementsProvider),
      searchMatches: (r, q) =>
          r.triggers.any((t) => t.toLowerCase().contains(q)) ||
          r.replacement.toLowerCase().contains(q),
      searchHint: l10n.replacementsSearch,
      searchFieldLabel: l10n.replacementsSearchFieldLabel,
      addLabel: l10n.replacementsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(replacementsProvider),
      emptyIcon: LucideIcons.replace,
      emptyTitle: l10n.replacementsEmpty,
      emptyHint: l10n.replacementsEmptyHint,
      emptyActionLabel: l10n.replacementsAdd,
      noMatchesTitle: l10n.replacementsNoMatches,
      noMatchesHint: l10n.replacementsNoMatchesHint,
      // Content — dimmed when disabled so users can still see their shortcuts
      contentWrapper: (context, child) => AnimatedOpacity(
        duration: WpMotion.durationFor(context, WpMotion.normal),
        opacity: enabled ? 1.0 : 0.5,
        child: child,
      ),
      itemBuilder: (context, r, isDark) {
        // loam-ignore: a11y-interactive-semantics – semantics provided in _ReplacementTileState.build
        return _ReplacementTile(
          replacement: r,
          isDark: isDark,
          onTap: () => _showAddEditDialog(existing: r),
          onDelete: () => _confirmDelete(r),
        );
      },
    );
  }

  // ── Add / Edit dialog ────────────────────────────────────────────────

  Future<void> _showAddEditDialog({Replacement? existing}) async {
    final result = await showWpFormDialog<(List<String>, String)>(
      context: context,
      builder: (_, a) => _ReplacementDialog(animation: a, existing: existing),
    );
    if (result == null) return;
    final (triggers, replacement) = result;
    final notifier = ref.read(replacementsProvider.notifier);
    if (existing != null) {
      notifier.updateReplacement(
        existing.id,
        triggers: triggers,
        replacement: replacement,
      );
    } else {
      notifier.add(triggers, replacement);
      ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'replacements', action: 'create');
    }
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(Replacement r) {
    final l10n = L10n.of(context);
    return showWpDeleteConfirmDialog(
      context: context,
      title: l10n.replacementsDeleteTitle,
      message: l10n.replacementsDeleteMessage(r.triggers.join(', ')),
      onConfirm: () => ref.read(replacementsProvider.notifier).remove(r.id),
    );
  }
}

// ---------------------------------------------------------------------------
// Master switch
// ---------------------------------------------------------------------------

/// Header card above the replacement list: the single switch that turns
/// automatic text replacement on or off during dictation.
///
/// Lives on this page rather than in Settings because it only matters in the
/// context of the list it governs — the same placement rule that keeps the
/// Snippets picker-trigger field on the Snippets page. Card geometry is
/// deliberately identical to `_SnippetPickerTriggerField`'s so switching
/// between the two sibling screens never nudges the toolbar below it.
class _ReplacementsToggleCard extends StatelessWidget {
  const _ReplacementsToggleCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

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
        child: SettingRow(
          icon: LucideIcons.replace,
          label: l10n.replacementsToggleLabel,
          // The subtitle states the current state in words, which is what
          // the toolbar's caption used to do — except a screen reader now
          // gets it too, and `semanticToggledValue` adds the on/off state to
          // the row's own announcement. No Tooltip: the row is labelled on
          // screen, so one would only repeat what is already there.
          subtitle: enabled
              ? l10n.replacementsToggleEnabled
              : l10n.replacementsToggleDisabled,
          semanticToggledValue: enabled,
          trailing: settingsToggle(value: enabled, onChanged: onChanged),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit dialog
// ---------------------------------------------------------------------------

class _ReplacementDialog extends StatefulWidget {
  const _ReplacementDialog({required this.animation, this.existing});

  final Animation<double> animation;
  final Replacement? existing;

  @override
  State<_ReplacementDialog> createState() => _ReplacementDialogState();
}

class _ReplacementDialogState extends State<_ReplacementDialog> {
  /// Maximum height of the trigger list before it scrolls, so the dialog
  /// stays on screen when a shortcut has many trigger phrases. Derived from
  /// the row height rather than guessed, so it always ends on a row edge
  /// instead of cutting one in half: four 48 dp fields plus the three 4 dp
  /// gaps between them.
  static const double _triggerListMaxHeight =
      WpLayout.minTouchTarget * 4 + WpSpacing.xxs * 3;

  final List<TextEditingController> _triggerCtrls = [];
  final List<FocusNode> _triggerFocusNodes = [];
  late final TextEditingController _replacementCtrl;

  bool get _isValid =>
      _triggerCtrls.any((c) => c.text.trim().isNotEmpty) &&
      _replacementCtrl.text.trim().isNotEmpty;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existingTriggers = widget.existing?.triggers ?? const [];
    for (final trigger
        in existingTriggers.isNotEmpty ? existingTriggers : const ['']) {
      _triggerCtrls.add(TextEditingController(text: trigger));
      _triggerFocusNodes.add(FocusNode());
    }
    _replacementCtrl = TextEditingController(
      text: widget.existing?.replacement ?? '',
    );
  }

  @override
  void dispose() {
    for (final ctrl in _triggerCtrls) {
      ctrl.dispose();
    }
    for (final node in _triggerFocusNodes) {
      node.dispose();
    }
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _addTrigger() {
    final node = FocusNode();
    setState(() {
      _triggerCtrls.add(TextEditingController());
      _triggerFocusNodes.add(node);
    });
    // Focus the new field after it has been built; the surrounding
    // Scrollable auto-scrolls it into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _removeTrigger(int index) {
    final ctrl = _triggerCtrls[index];
    final node = _triggerFocusNodes[index];
    setState(() {
      _triggerCtrls.removeAt(index);
      _triggerFocusNodes.removeAt(index);
    });
    // Dispose after the frame so the outgoing TextField no longer uses them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.dispose();
      node.dispose();
    });
  }

  void _submit() {
    if (!_isValid) return;
    final triggers = _triggerCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    Navigator.of(context).pop((triggers, _replacementCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final l10n = L10n.of(context);

    return WpFormDialogShell(
      animation: widget.animation,
      title: _isEditing
          ? l10n.replacementsEditShortcut
          : l10n.replacementsNewShortcut,
      subtitle: l10n.replacementsDialogHint,
      fields: [
        // Trigger phrases — dynamic list, one text field per phrase
        Text(l10n.replacementsTriggerLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: WpSpacing.xxs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _triggerListMaxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _triggerCtrls.length; i++)
                  Padding(
                    key: ObjectKey(_triggerCtrls[i]),
                    padding: EdgeInsets.only(top: i == 0 ? 0 : WpSpacing.xxs),
                    child: Row(
                      children: [
                        Expanded(
                          child: WpTextField(
                            controller: _triggerCtrls[i],
                            variant: WpTextFieldVariant.form,
                            focusNode: _triggerFocusNodes[i],
                            autofocus: i == 0,
                            hintText: l10n.replacementsTriggerHint,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        // The last remaining trigger cannot be
                        // removed — a shortcut always keeps at
                        // least one phrase.
                        if (_triggerCtrls.length > 1) ...[
                          const SizedBox(width: WpSpacing.xxs),
                          IconButton(
                            tooltip: l10n.replacementsRemoveTrigger,
                            icon: Icon(
                              LucideIcons.x,
                              size: WpIconSize.sm,
                              color: textMuted,
                            ),
                            onPressed: () => _removeTrigger(i),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.xxs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          child: WpButton(
            label: l10n.replacementsAddTrigger,
            variant: WpButtonVariant.ghost,
            size: WpButtonSize.dense,
            icon: LucideIcons.plus,
            onPressed: _addTrigger,
          ),
        ),
        const SizedBox(height: WpSpacing.md),

        // Replacement field
        Text(
          l10n.replacementsReplacementLabel,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: WpSpacing.xxs),
        WpTextField(
          controller: _replacementCtrl,
          variant: WpTextFieldVariant.form,
          hintText: l10n.replacementsReplacementHint,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
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
          label: _isEditing ? l10n.actionSave : l10n.replacementsAdd,
          variant: WpButtonVariant.primary,
          onPressed: _isValid ? _submit : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Replacement tile
// ---------------------------------------------------------------------------

class _ReplacementTile extends StatefulWidget {
  const _ReplacementTile({
    required this.replacement,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  final Replacement replacement;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ReplacementTile> createState() => _ReplacementTileState();
}

class _ReplacementTileState extends State<_ReplacementTile> {
  bool _isHovered = false;
  bool _isFocused = false;

  /// The row is "active" for pointer and for keyboard alike — the
  /// delete action is revealed by either, so a keyboard user can reach
  /// it at all (an unmounted button cannot be focused).
  bool get _isActive => _isHovered || _isFocused;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Delete/Backspace on the focused row — same binding, same reasoning
      // and same row-scoping as _SnippetTile, which see.
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
      // Affordance as `hint:`, identity from the rendered trigger chips —
      // same reasoning and same shape as _SnippetTile, which see. The label
      // used to repeat the trigger phrases the chips already render, and a
      // Semantics label is prepended to its subtree's text rather than
      // substituted for it, so each row announced "Ersetzung bearbeiten:
      // mfg, mfg, …". MergeSemantics is not an option: the delete action
      // mounts as a second interactive node once the row is active.
      hint: L10n.of(context).replacementsEditShortcut,
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
                    LucideIcons.arrowRightLeft,
                    size: WpIconSize.sm,
                    color: widget.isDark
                        ? WpColorsDark.accent
                        : WpColorsLight.accent,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Trigger phrases — one chip per phrase, wrapping onto
                  // additional lines when a shortcut has many triggers.
                  Flexible(
                    child: Wrap(
                      spacing: WpSpacing.xxs,
                      runSpacing: WpSpacing.xxs,
                      children: [
                        for (final trigger in widget.replacement.triggers)
                          WpTriggerChip(label: trigger, isDark: widget.isDark),
                      ],
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Icon(
                    LucideIcons.arrowRight,
                    size: WpIconSize.xs,
                    color: widget.isDark
                        ? WpColorsDark.textMuted
                        : WpColorsLight.textMuted,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Replacement
                  Expanded(
                    child: Text(
                      '"${widget.replacement.replacement}"',
                      style: TextStyle(
                        color: widget.isDark
                            ? WpColorsDark.textSecondary
                            : WpColorsLight.textSecondary,
                        fontSize: WpTypography.body,
                      ),
                      // `maxLines: 1` is load-bearing, not cosmetic: without
                      // it `overflow: ellipsis` still lets the text wrap to
                      // as many lines as it likes (the Row leaves its cross
                      // axis unbounded), so a long replacement grew the row
                      // without limit while the sibling snippet row truncated
                      // its body preview after one line — the same content
                      // shape behaving differently on two neighbouring
                      // screens. It also restores the premise
                      // `WpSearchableListPage`'s skeleton row height rests on
                      // ("a Snippets tile and a Replacements tile both render
                      // at exactly 70 dp"). The trigger-chip `Wrap` above can
                      // still add lines; that growth is deliberate and
                      // documented, so 70 dp stays a base height, not a cap.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Delete on hover
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
