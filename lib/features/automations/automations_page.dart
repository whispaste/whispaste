import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/automation_dispatch_service.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/searchable_list_page.dart';
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

class AutomationsNotifier extends AsyncNotifier<List<AutomationItem>>
    with ReloadableListNotifier<AutomationItem> {
  @override
  Future<List<AutomationItem>> readAll() async {
    final db = ref.read(historyDatabaseProvider);
    return (await db.readAllAutomations()).map(_fromDb).toList();
  }

  @override
  Future<List<AutomationItem>> build() => readAll();

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
    await reload();
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
    await reload();
  }

  Future<void> remove(String id) async {
    final db = ref.read(historyDatabaseProvider);
    await db.deleteAutomation(id);
    await reload();
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
  @override
  // Deliberately not further extracted: WpSearchableListPage call-site parameter
  // skeleton shared with SnippetsPage: every value is feature-specific
  // (l10n keys, icon, callbacks), only the parameter *names* repeat. A
  // further-generic factory (e.g. keyed by notifier + string-map) was
  // evaluated and rejected as the exact "Data Clumps"-in-reverse trade the
  // WpSearchableListPage extraction already made — this is its irreducible
  // residue, not unextracted duplication.
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return WpSearchableListPage<AutomationItem>(
      asyncAll: ref.watch(automationsProvider),
      searchMatches: (a, q) =>
          a.trigger.toLowerCase().contains(q) ||
          a.url.toLowerCase().contains(q),
      searchHint: l10n.automationsSearch,
      addLabel: l10n.automationsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(automationsProvider),
      emptyIcon: LucideIcons.zap,
      emptyTitle: l10n.automationsEmpty,
      emptyHint: l10n.automationsEmptyHint,
      emptyActionLabel: l10n.automationsAddAutomation,
      noMatchesTitle: l10n.automationsNoMatches,
      noMatchesHint: l10n.automationsNoMatchesHint,
      itemBuilder: (context, a, isDark) {
        // loam-ignore: a11y-interactive-semantics – semantics provided in _AutomationTileState.build
        return _AutomationTile(
          automation: a,
          isDark: isDark,
          onTap: () => _showAddEditDialog(existing: a),
          onDelete: () => _confirmDelete(a),
        );
      },
    );
  }

  // ── Add / Edit dialog ────────────────────────────────────────────────

  // Deliberately not further extracted: shares its open-dialog/branch-on-existing
  // shape with SnippetsPage._showAddEditDialog, but the result tuples and
  // notifier update-method names differ per feature. Tried extracting this
  // to an onCreate/onUpdate-callback helper: the result was longer than the
  // original and replaced the direct `final (trigger, url) = result;`
  // destructuring with closure indirection — net readability loss, so this
  // one stays duplicated on purpose (unlike the dialog-scaffold + delete
  // flow, which extracted cleanly into WpSearchableListPage/
  // showWpDeleteConfirmDialog).
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

  Future<void> _confirmDelete(AutomationItem a) {
    final l10n = L10n.of(context);
    return showWpDeleteConfirmDialog(
      context: context,
      title: l10n.automationsDeleteTitle,
      message: l10n.automationsDeleteMessage(a.trigger),
      onConfirm: () => ref.read(automationsProvider.notifier).remove(a.id),
    );
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
