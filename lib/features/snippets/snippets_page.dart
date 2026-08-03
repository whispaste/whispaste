import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/data/reloadable_list_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/telemetry_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/managed_list_page.dart';
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

  // Deliberately not further extracted: shares its "generate a millis-epoch id,
  // upsert, reload" shape with ReplacementsNotifier.add. A shared
  // `createThenReload(persist)` helper was tried on ReloadableListNotifier:
  // it replaced this direct, linear code with a persist-callback closure for
  // no net line reduction — not worth the indirection for three lines.
  Future<void> add(String title, String body) async {
    final db = ref.read(historyDatabaseProvider);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
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
/// area from Replacements and Automations (dictation-automations ticket 05).
class SnippetsPage extends ConsumerStatefulWidget {
  const SnippetsPage({super.key});

  @override
  ConsumerState<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends ConsumerState<SnippetsPage> {
  @override
  // Deliberately not further extracted: WpManagedListPage call-site parameter
  // skeleton shared with AutomationsPage: every value is feature-specific
  // (l10n keys, icon, callbacks), only the parameter *names* repeat. A
  // further-generic factory (e.g. keyed by notifier + string-map) was
  // evaluated and rejected as the exact "Data Clumps"-in-reverse trade the
  // WpManagedListPage extraction already made — this is its irreducible
  // residue, not unextracted duplication.
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return WpManagedListPage<SnippetItem>(
      asyncAll: ref.watch(snippetsProvider),
      searchMatches: (s, q) =>
          s.title.toLowerCase().contains(q) || s.body.toLowerCase().contains(q),
      searchHint: l10n.snippetsSearch,
      addLabel: l10n.snippetsAdd,
      onAdd: () => _showAddEditDialog(),
      onRetry: () => ref.invalidate(snippetsProvider),
      emptyIcon: LucideIcons.notebookText,
      emptyTitle: l10n.snippetsEmpty,
      emptyHint: l10n.snippetsEmptyHint,
      emptyActionLabel: l10n.snippetsAddSnippet,
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

  // Deliberately not further extracted: shares its open-dialog/branch-on-existing
  // shape with AutomationsPage._showAddEditDialog, but the result tuples and
  // notifier update-method names differ per feature. Tried extracting this
  // to an onCreate/onUpdate-callback helper: the result was longer than the
  // original and replaced the direct `final (title, body) = result;`
  // destructuring with closure indirection — net readability loss, so this
  // one stays duplicated on purpose (unlike the dialog-scaffold + delete
  // flow, which extracted cleanly into WpManagedListPage/
  // confirmWpManagedDelete).
  Future<void> _showAddEditDialog({SnippetItem? existing}) async {
    final result = await showWpFormDialog<(String, String)>(
      context: context,
      builder: (_, a) => _SnippetDialog(existing: existing),
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
    return confirmWpManagedDelete(
      context: context,
      title: l10n.snippetsDeleteTitle,
      message: l10n.snippetsDeleteMessage(s.title),
      onConfirm: () => ref.read(snippetsProvider.notifier).remove(s.id),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit dialog
// ---------------------------------------------------------------------------

class _SnippetDialog extends StatefulWidget {
  const _SnippetDialog({this.existing});

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
                _isEditing ? l10n.snippetsEditSnippet : l10n.snippetsNewSnippet,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.heading,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WpSpacing.lg),

              // Title
              Text(
                l10n.snippetsTitleLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.body,
                ),
                decoration: InputDecoration(
                  hintText: l10n.snippetsTitleHint,
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

              // Body (multi-line)
              Text(
                l10n.snippetsBodyLabel,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              TextField(
                controller: _bodyCtrl,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: WpTypography.body,
                ),
                decoration: InputDecoration(
                  hintText: l10n.snippetsBodyHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.md,
                    vertical: WpSpacing.sm,
                  ),
                ),
                onChanged: (_) => setState(() {}),
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
                      _isEditing ? l10n.actionSave : l10n.snippetsAdd,
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

  /// Single-line preview of the body — newlines and runs of whitespace
  /// collapse to single spaces so the ellipsis works on one visual line.
  String get _bodyPreview =>
      widget.snippet.body.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${L10n.of(context).snippetsEditSnippet}: ${widget.snippet.title}',
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
