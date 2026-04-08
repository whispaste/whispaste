import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class Replacement {
  const Replacement({
    required this.id,
    required this.trigger,
    required this.replacement,
  });

  final String id;
  final String trigger;
  final String replacement;

  Replacement copyWith({String? trigger, String? replacement}) => Replacement(
    id: id,
    trigger: trigger ?? this.trigger,
    replacement: replacement ?? this.replacement,
  );
}

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

class ReplacementsNotifier extends AsyncNotifier<List<Replacement>> {
  @override
  Future<List<Replacement>> build() async {
    final db = ref.read(historyDatabaseProvider);
    final rows = await db.readAllReplacements();
    if (rows.isEmpty) {
      await _insertSampleData(db);
      return (await db.readAllReplacements())
          .map(_fromDb)
          .toList();
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
      await db.upsertReplacement(TextReplacementsCompanion(
        id: Value(id),
        trigger: Value(trigger),
        replacement: Value(replacement),
        createdAt: Value(now),
      ));
    }
  }

  Future<void> add(String trigger, String replacement) async {
    final db = ref.read(historyDatabaseProvider);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await db.upsertReplacement(TextReplacementsCompanion(
      id: Value(id),
      trigger: Value(trigger),
      replacement: Value(replacement),
      createdAt: Value(DateTime.now()),
    ));
    state = AsyncData(
      (await db.readAllReplacements()).map(_fromDb).toList(),
    );
  }

  Future<void> updateReplacement(
    String id, {
    required String trigger,
    required String replacement,
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertReplacement(TextReplacementsCompanion(
      id: Value(id),
      trigger: Value(trigger),
      replacement: Value(replacement),
      createdAt: Value(DateTime.now()),
    ));
    state = AsyncData(
      (await db.readAllReplacements()).map(_fromDb).toList(),
    );
  }

  Future<void> remove(String id) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteReplacement(id);
    state = AsyncData(
      (await db.readAllReplacements()).map(_fromDb).toList(),
    );
  }

  static Replacement _fromDb(TextReplacement row) => Replacement(
        id: row.id,
        trigger: row.trigger,
        replacement: row.replacement,
      );
}

final replacementsProvider =
    AsyncNotifierProvider<ReplacementsNotifier, List<Replacement>>(
      ReplacementsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Voice Shortcuts (Replacements) page — auto-replace words during dictation.
class ReplacementsPage extends ConsumerStatefulWidget {
  const ReplacementsPage({super.key});

  @override
  ConsumerState<ReplacementsPage> createState() => _ReplacementsPageState();
}

class _ReplacementsPageState extends ConsumerState<ReplacementsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Replacement> _filtered(List<Replacement> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where(
          (r) =>
              r.trigger.toLowerCase().contains(q) ||
              r.replacement.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asyncAll = ref.watch(replacementsProvider);
    final l10n = L10n.of(context);

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: asyncAll.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final visible = _filtered(all);
          return Column(
            children: [
              // Toolbar
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WpSpacing.xl,
                  WpSpacing.sm,
                  WpSpacing.xl,
                  WpSpacing.sm,
                ),
                child: Row(
                  children: [
                    // Search
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: l10n.replacementsSearch,
                          prefixIcon: Icon(
                            LucideIcons.search,
                            size: WpIconSize.sm,
                            color: isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: WpSpacing.md,
                            vertical: WpSpacing.xs + 2,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    // Enable/disable toggle
                    _ReplacementsToggle(),
                    const SizedBox(width: WpSpacing.sm),
                    // Add button
                    ElevatedButton.icon(
                      onPressed: () => _showAddEditDialog(),
                      icon: const Icon(LucideIcons.plus, size: WpIconSize.sm),
                      label: Text(l10n.replacementsAdd),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: all.isEmpty
                    ? WpEmptyState(
                        icon: LucideIcons.replace,
                        title: l10n.replacementsEmpty,
                        hint: l10n.replacementsEmptyHint,
                        actionLabel: l10n.replacementsAddShortcut,
                        onAction: () => _showAddEditDialog(),
                      )
                    : visible.isEmpty
                    ? WpEmptyState(
                        icon: LucideIcons.searchX,
                        title: l10n.replacementsNoMatches,
                        hint: l10n.replacementsNoMatchesHint,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WpSpacing.xl,
                          vertical: WpSpacing.xs,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: WpSpacing.xs),
                        itemBuilder: (context, index) {
                          final r = visible[index];
                          return _ReplacementTile(
                            replacement: r,
                        isDark: isDark,
                        onTap: () => _showAddEditDialog(existing: r),
                        onDelete: () => _confirmDelete(r),
                      );
                    },
                  ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Add / Edit dialog ────────────────────────────────────────────────

  Future<void> _showAddEditDialog({Replacement? existing}) async {
    final result = await showWpFormDialog<(String, String)>(
      context: context,
      builder: (_, a) => _ReplacementDialog(existing: existing),
    );
    if (result == null) return;
    final (trigger, replacement) = result;
    final notifier = ref.read(replacementsProvider.notifier);
    if (existing != null) {
      notifier.updateReplacement(existing.id, trigger: trigger, replacement: replacement);
    } else {
      notifier.add(trigger, replacement);
    }
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(Replacement r) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.replacementsDeleteTitle,
      message: l10n.replacementsDeleteMessage(r.trigger),
      confirmLabel: l10n.actionDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (confirmed) {
      ref.read(replacementsProvider.notifier).remove(r.id);
    }
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
  late final TextEditingController _triggerCtrl;
  late final TextEditingController _replacementCtrl;

  bool get _isValid =>
      _triggerCtrl.text.trim().isNotEmpty &&
      _replacementCtrl.text.trim().isNotEmpty;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _triggerCtrl = TextEditingController(text: widget.existing?.trigger ?? '');
    _replacementCtrl = TextEditingController(
      text: widget.existing?.replacement ?? '',
    );
  }

  @override
  void dispose() {
    _triggerCtrl.dispose();
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(
      context,
    ).pop((_triggerCtrl.text.trim(), _replacementCtrl.text.trim()));
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
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final l10n = L10n.of(context);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: WpMotion.fast,
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(
                l10n.replacementsDialogHint,
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
              const SizedBox(height: WpSpacing.lg),

              // Trigger field
              Text(
                l10n.replacementsTriggerLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _triggerCtrl,
                autofocus: true,
                style: TextStyle(color: textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: l10n.replacementsTriggerHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.md,
                    vertical: WpSpacing.sm,
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: WpSpacing.md),

              // Replacement field
              Text(
                l10n.replacementsReplacementLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _replacementCtrl,
                style: TextStyle(color: textPrimary, fontSize: 13),
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
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.actionCancel,
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  ElevatedButton(
                    onPressed: _isValid ? _submit : null,
                    child: Text(
                      _isEditing ? l10n.actionSave : l10n.replacementsAdd,
                      style: TextStyle(
                        color: _isValid ? accent : textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
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
              // Trigger
              Text(
                '"${widget.replacement.trigger}"',
                style: TextStyle(
                  color: widget.isDark
                      ? WpColorsDark.textPrimary
                      : WpColorsLight.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              Icon(
                LucideIcons.arrowRight,
                size: 12,
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
                    fontSize: 13,
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
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle widget for text replacements enabled state
// ---------------------------------------------------------------------------

class _ReplacementsToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value;
    final enabled = settings?.textReplacementsEnabled ?? true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: enabled
          ? l10n.replacementsToggleEnabled
          : l10n.replacementsToggleDisabled,
      child: InkWell(
        borderRadius: WpRadius.borderSm,
        onTap: () => ref
            .read(settingsProvider.notifier)
            .updateSettings(
                (s) => s.copyWith(textReplacementsEnabled: !enabled)),
        child: AnimatedContainer(
          duration: WpMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: enabled
                ? (isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle)
                : Colors.transparent,
            borderRadius: WpRadius.borderSm,
            border: Border.all(
              color: enabled
                  ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                      .withValues(alpha: 0.3)
                  : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
                size: WpIconSize.sm,
                color: enabled
                    ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                    : (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted),
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                enabled ? l10n.settingsOn : l10n.settingsOff,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: enabled
                      ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                      : (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}