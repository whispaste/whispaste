import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/automation_dispatch_service.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/trigger_chip.dart';
import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// UI-facing "open a URL" automation — the only action type today. Wraps a
/// DB [Automation] row (`actionType`/`payload`), decoding its payload so the
/// settings UI never has to know about the JSON encoding.
class AutomationItem {
  const AutomationItem({
    required this.id,
    required this.trigger,
    required this.url,
  });

  final String id;
  final String trigger;
  final String url;
}

// ---------------------------------------------------------------------------
// State management (Riverpod AsyncNotifier — persisted in Drift DB)
// ---------------------------------------------------------------------------

class AutomationsNotifier extends AsyncNotifier<List<AutomationItem>> {
  @override
  Future<List<AutomationItem>> build() async {
    final db = ref.read(historyDatabaseProvider);
    final rows = await db.readAllAutomations();
    return rows.map(_fromDb).toList();
  }

  Future<void> add(String trigger, String url) async {
    final db = ref.read(historyDatabaseProvider);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await db.upsertAutomation(
      id: id,
      trigger: trigger,
      actionType: AutomationActionType.openUrl.dbValue,
      payload: jsonEncode({'url': url}),
      createdAt: DateTime.now(),
    );
    state = AsyncData((await db.readAllAutomations()).map(_fromDb).toList());
  }

  Future<void> updateAutomation(
    String id, {
    required String trigger,
    required String url,
  }) async {
    final db = ref.read(historyDatabaseProvider);
    await db.upsertAutomation(
      id: id,
      trigger: trigger,
      actionType: AutomationActionType.openUrl.dbValue,
      payload: jsonEncode({'url': url}),
      createdAt: DateTime.now(),
    );
    state = AsyncData((await db.readAllAutomations()).map(_fromDb).toList());
  }

  Future<void> remove(String id) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteAutomation(id);
    state = AsyncData((await db.readAllAutomations()).map(_fromDb).toList());
  }

  static AutomationItem _fromDb(Automation row) {
    // A malformed payload surfaces as an empty URL rather than crashing the
    // whole list — see [decodeOpenUrlPayload].
    return AutomationItem(
      id: row.id,
      trigger: row.trigger,
      url: decodeOpenUrlPayload(row.payload) ?? '',
    );
  }
}

final automationsProvider =
    AsyncNotifierProvider<AutomationsNotifier, List<AutomationItem>>(
      AutomationsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Automations page — exact-match trigger phrases that open a URL, kept in
/// a separate settings area from Replacements (dictation-automations
/// ticket 02).
class AutomationsPage extends ConsumerStatefulWidget {
  const AutomationsPage({super.key});

  @override
  ConsumerState<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends ConsumerState<AutomationsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AutomationItem> _filtered(List<AutomationItem> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where(
          (a) =>
              a.trigger.toLowerCase().contains(q) ||
              a.url.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asyncAll = ref.watch(automationsProvider);
    final l10n = L10n.of(context);

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: asyncAll.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => WpEmptyState(
          icon: LucideIcons.triangleAlert,
          title: l10n.errorGeneric,
          actionLabel: l10n.actionRetry,
          onAction: () => ref.invalidate(automationsProvider),
        ),
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
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: l10n.automationsSearch,
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
                    ElevatedButton.icon(
                      onPressed: () => _showAddEditDialog(),
                      icon: const Icon(LucideIcons.plus, size: WpIconSize.sm),
                      label: Text(l10n.automationsAdd),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? WpEmptyState(
                        icon: LucideIcons.zap,
                        title: l10n.automationsEmpty,
                        hint: l10n.automationsEmptyHint,
                        actionLabel: l10n.automationsAddAutomation,
                        onAction: () => _showAddEditDialog(),
                      )
                    : visible.isEmpty
                    ? WpEmptyState(
                        icon: LucideIcons.searchX,
                        title: l10n.automationsNoMatches,
                        hint: l10n.automationsNoMatchesHint,
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
                          final a = visible[index];
                          // loam-ignore: a11y-interactive-semantics – semantics provided in _AutomationTileState.build
                          return _AutomationTile(
                            automation: a,
                            isDark: isDark,
                            onTap: () => _showAddEditDialog(existing: a),
                            onDelete: () => _confirmDelete(a),
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

  Future<void> _showAddEditDialog({AutomationItem? existing}) async {
    final result = await showWpFormDialog<(String, String)>(
      context: context,
      builder: (_, a) => _AutomationDialog(existing: existing),
    );
    if (result == null) return;
    final (trigger, url) = result;
    final notifier = ref.read(automationsProvider.notifier);
    if (existing != null) {
      notifier.updateAutomation(existing.id, trigger: trigger, url: url);
    } else {
      notifier.add(trigger, url);
      ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'automations', action: 'create');
    }
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(AutomationItem a) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.automationsDeleteTitle,
      message: l10n.automationsDeleteMessage(a.trigger),
      confirmLabel: l10n.actionDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (confirmed) {
      ref.read(automationsProvider.notifier).remove(a.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Add / Edit dialog
// ---------------------------------------------------------------------------

class _AutomationDialog extends StatefulWidget {
  const _AutomationDialog({this.existing});

  final AutomationItem? existing;

  @override
  State<_AutomationDialog> createState() => _AutomationDialogState();
}

class _AutomationDialogState extends State<_AutomationDialog> {
  late final TextEditingController _triggerCtrl;
  late final TextEditingController _urlCtrl;

  bool get _isValid =>
      _triggerCtrl.text.trim().isNotEmpty && _urlCtrl.text.trim().isNotEmpty;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _triggerCtrl = TextEditingController(text: widget.existing?.trigger ?? '');
    _urlCtrl = TextEditingController(text: widget.existing?.url ?? '');
  }

  @override
  void dispose() {
    _triggerCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop((_triggerCtrl.text.trim(), _urlCtrl.text.trim()));
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
        child: Container(
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
              Text(
                _isEditing
                    ? l10n.automationsEditAutomation
                    : l10n.automationsNewAutomation,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.heading,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(
                l10n.automationsDialogHint,
                style: TextStyle(
                  color: textMuted,
                  fontSize: WpTypography.small,
                ),
              ),
              const SizedBox(height: WpSpacing.lg),

              // Trigger phrase
              Text(
                l10n.automationsTriggerLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _triggerCtrl,
                autofocus: true,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.body,
                ),
                decoration: InputDecoration(
                  hintText: l10n.automationsTriggerHint,
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

              // URL field
              Text(
                l10n.automationsUrlLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _urlCtrl,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.body,
                ),
                decoration: InputDecoration(
                  hintText: l10n.automationsUrlHint,
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
                      style: TextStyle(
                        color: textMuted,
                        fontSize: WpTypography.body,
                      ),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  ElevatedButton(
                    onPressed: _isValid ? _submit : null,
                    child: Text(
                      _isEditing ? l10n.actionSave : l10n.automationsAdd,
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
// Automation tile
// ---------------------------------------------------------------------------

class _AutomationTile extends StatefulWidget {
  const _AutomationTile({
    required this.automation,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  final AutomationItem automation;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_AutomationTile> createState() => _AutomationTileState();
}

class _AutomationTileState extends State<_AutomationTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${L10n.of(context).automationsEditAutomation}: ${widget.automation.trigger}',
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
                  LucideIcons.zap,
                  size: WpIconSize.sm,
                  color: widget.isDark
                      ? WpColorsDark.accent
                      : WpColorsLight.accent,
                ),
                const SizedBox(width: WpSpacing.sm),
                WpTriggerChip(
                  label: widget.automation.trigger,
                  isDark: widget.isDark,
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
                Expanded(
                  child: Text(
                    widget.automation.url,
                    style: TextStyle(
                      color: widget.isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary,
                      fontSize: WpTypography.body,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
