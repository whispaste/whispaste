import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';

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
// State management (Riverpod Notifier)
// ---------------------------------------------------------------------------

int _nextId = 4; // starts after sample data

class ReplacementsNotifier extends Notifier<List<Replacement>> {
  @override
  List<Replacement> build() => const [
        Replacement(id: '1', trigger: 'mfg', replacement: 'Mit freundlichen Grüßen'),
        Replacement(id: '2', trigger: 'lg', replacement: 'Liebe Grüße'),
        Replacement(id: '3', trigger: 'tel', replacement: '+49 123 456789'),
      ];

  void add(String trigger, String replacement) {
    state = [
      ...state,
      Replacement(id: '${_nextId++}', trigger: trigger, replacement: replacement),
    ];
  }

  void update(String id, {required String trigger, required String replacement}) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(trigger: trigger, replacement: replacement) else r,
    ];
  }

  void remove(String id) {
    state = state.where((r) => r.id != id).toList();
  }
}

final replacementsProvider =
    NotifierProvider<ReplacementsNotifier, List<Replacement>>(
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
        .where((r) =>
            r.trigger.toLowerCase().contains(q) ||
            r.replacement.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final all = ref.watch(replacementsProvider);
    final visible = _filtered(all);

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.sm,
          ),
          child: Row(
            children: [
              // Search
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search shortcuts…',
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
              // Add button
              ElevatedButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(LucideIcons.plus, size: WpIconSize.sm),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: all.isEmpty
              ? WpEmptyState(
                  icon: LucideIcons.replace,
                  title: 'No voice shortcuts yet',
                  hint:
                      'Add shortcuts to auto-replace words during dictation.\n'
                      'Example: "btw" → "by the way"',
                  actionLabel: 'Add Shortcut',
                  onAction: () => _showAddEditDialog(),
                )
              : visible.isEmpty
                  ? const WpEmptyState(
                      icon: LucideIcons.searchX,
                      title: 'No matches',
                      hint: 'Try a different search term.',
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
  }

  // ── Add / Edit dialog ────────────────────────────────────────────────

  Future<void> _showAddEditDialog({Replacement? existing}) async {
    final result = await showDialog<(String, String)>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ReplacementDialog(existing: existing),
    );
    if (result == null) return;
    final (trigger, replacement) = result;
    final notifier = ref.read(replacementsProvider.notifier);
    if (existing != null) {
      notifier.update(existing.id, trigger: trigger, replacement: replacement);
    } else {
      notifier.add(trigger, replacement);
    }
  }

  // ── Delete confirmation ──────────────────────────────────────────────

  Future<void> _confirmDelete(Replacement r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _DeleteConfirmDialog(trigger: r.trigger),
    );
    if (confirmed == true) {
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
    _replacementCtrl =
        TextEditingController(text: widget.existing?.replacement ?? '');
  }

  @override
  void dispose() {
    _triggerCtrl.dispose();
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context)
        .pop((_triggerCtrl.text.trim(), _replacementCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surfaceElevated;
    final border =
        isDark ? WpColorsDark.borderDefault : WpColorsLight.borderDefault;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

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
                _isEditing ? 'Edit Shortcut' : 'New Shortcut',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(
                'The trigger phrase will be replaced automatically during dictation.',
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
              const SizedBox(height: WpSpacing.lg),

              // Trigger field
              Text(
                'Trigger phrase',
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
                decoration: const InputDecoration(
                  hintText: 'e.g. btw',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
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
                'Replacement text',
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
                decoration: const InputDecoration(
                  hintText: 'e.g. by the way',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
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
                      'Cancel',
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  ElevatedButton(
                    onPressed: _isValid ? _submit : null,
                    child: Text(
                      _isEditing ? 'Save' : 'Add',
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
// Delete confirmation dialog
// ---------------------------------------------------------------------------

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.trigger});

  final String trigger;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surfaceElevated;
    final border =
        isDark ? WpColorsDark.borderDefault : WpColorsLight.borderDefault;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
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
                'Delete Shortcut',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WpSpacing.sm),
              Text(
                'Remove the shortcut "$trigger"? This cannot be undone.',
                style: TextStyle(color: textMuted, fontSize: 13),
              ),
              const SizedBox(height: WpSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: errorColor.withValues(alpha: 0.15),
                    ),
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        color: errorColor,
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
          duration: WpMotion.fast,
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
                  icon: Icon(
                    LucideIcons.trash2,
                    size: WpIconSize.sm,
                    color: widget.isDark
                        ? WpColorsDark.error
                        : WpColorsLight.error,
                  ),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
