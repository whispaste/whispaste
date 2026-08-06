import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/trigger_chip.dart';
import '../../widgets/wp_button.dart';
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
      asyncAll: ref.watch(replacementsProvider),
      searchMatches: (r, q) =>
          r.triggers.any((t) => t.toLowerCase().contains(q)) ||
          r.replacement.toLowerCase().contains(q),
      searchHint: l10n.replacementsSearch,
      addLabel: l10n.replacementsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(replacementsProvider),
      emptyIcon: LucideIcons.replace,
      emptyTitle: l10n.replacementsEmpty,
      emptyHint: l10n.replacementsEmptyHint,
      emptyActionLabel: l10n.replacementsAddShortcut,
      noMatchesTitle: l10n.replacementsNoMatches,
      noMatchesHint: l10n.replacementsNoMatchesHint,
      // Enable/disable toggle — label is context-sensitive
      toolbarTrailing: [
        Text(
          enabled
              ? l10n.replacementsDisableAction
              : l10n.replacementsEnableAction,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: WpSpacing.xs),
        Tooltip(
          message: enabled
              ? l10n.replacementsToggleEnabled
              : l10n.replacementsToggleDisabled,
          child: Switch(
            value: enabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(textReplacementsEnabled: v)),
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
      ],
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
      builder: (_, a) => _ReplacementDialog(existing: existing),
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
// Add / Edit dialog
// ---------------------------------------------------------------------------

class _ReplacementDialog extends StatefulWidget {
  const _ReplacementDialog({this.existing});

  final Replacement? existing;

  @override
  State<_ReplacementDialog> createState() => _ReplacementDialogState();
}

class _ReplacementDialogState extends State<_ReplacementDialog> {
  /// Maximum height of the trigger list before it scrolls, so the dialog
  /// stays on screen when a shortcut has many trigger phrases.
  static const double _triggerListMaxHeight = 220;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final border = isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final l10n = L10n.of(context);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: WpMotion.durationFor(context, WpMotion.fast),
          width: 400,
          padding: const EdgeInsets.all(WpSpacing.xl),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: border),
            boxShadow: WpShadows.elevated,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                _isEditing
                    ? l10n.replacementsEditShortcut
                    : l10n.replacementsNewShortcut,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.heading,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(
                l10n.replacementsDialogHint,
                style: TextStyle(
                  color: textMuted,
                  fontSize: WpTypography.small,
                ),
              ),
              const SizedBox(height: WpSpacing.lg),

              // Trigger phrases — dynamic list, one text field per phrase
              Text(
                l10n.replacementsTriggerLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _triggerListMaxHeight,
                ),
                child: SingleChildScrollView(
                  child: AnimatedSize(
                    duration: WpMotion.durationFor(context, WpMotion.fast),
                    curve: WpMotion.defaultCurve,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _triggerCtrls.length; i++)
                          Padding(
                            key: ObjectKey(_triggerCtrls[i]),
                            padding: EdgeInsets.only(
                              top: i == 0 ? 0 : WpSpacing.xxs,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _triggerCtrls[i],
                                    focusNode: _triggerFocusNodes[i],
                                    autofocus: i == 0,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: WpTypography.body,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: l10n.replacementsTriggerHint,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: WpSpacing.md,
                                            vertical: WpSpacing.sm,
                                          ),
                                    ),
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
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _replacementCtrl,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.body,
                ),
                decoration: InputDecoration(
                  hintText: l10n.replacementsReplacementHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.md,
                    vertical: WpSpacing.sm,
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: WpSpacing.xl),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
              ),
            ],
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${L10n.of(context).replacementsEditShortcut}: ${widget.replacement.triggers.join(', ')}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: WpMotion.durationFor(
              context,
              _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
            ),
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
                  : (widget.isDark
                        ? WpColorsDark.surfaceElevated
                        : WpColorsLight.surfaceElevated),
              borderRadius: WpRadius.borderMd,
              border: Border.all(
                color: _isHovered
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
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Delete on hover
                if (_isHovered)
                  IconButton(
                    tooltip: L10n.of(context).actionDelete,
                    icon: Icon(
                      LucideIcons.trash2,
                      size: WpIconSize.sm,
                      color: widget.isDark
                          ? WpColorsDark.error
                          : WpColorsLight.error,
                    ),
                    onPressed: widget.onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
