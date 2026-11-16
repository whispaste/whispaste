// "Change order" (#1004): the replacement rules in the order the cascade
// applies them, sortable by drag & drop and by the arrow buttons (keyboard).
//
// A dialog rather than handles in the main list: the list itself keeps its
// display sort (A–Z, favourites first, search), which is not the order the
// rules act in. Every move is saved at once, so there is no Save button.
part of 'replacements_page.dart';

Future<void> showReplacementOrderDialog(BuildContext context) {
  return showWpFormDialog<void>(
    context: context,
    builder: (_, a) => _ReplacementOrderDialog(animation: a),
  );
}

class _ReplacementOrderDialog extends ConsumerWidget {
  const _ReplacementOrderDialog({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // Provider order is the database order, i.e. the application order.
    final items =
        ref.watch(replacementsProvider).value ?? const <Replacement>[];
    final ids = [for (final r in items) r.id];
    void save(List<String> next) =>
        ref.read(replacementsProvider.notifier).reorder(next);

    return WpFormDialogShell(
      animation: animation,
      title: l10n.replacementsOrderTitle,
      subtitle: l10n.replacementsOrderSubtitle,
      fields: [
        Semantics(
          identifier: 'replacements-order-list',
          child: ReorderableListView(
            key: const ValueKey('replacements-order-list'),
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) =>
                save(reorderedReplacementIds(ids, oldIndex, newIndex)),
            children: [
              for (var i = 0; i < items.length; i++)
                _OrderRow(
                  key: ValueKey('replacements-order-row-${items[i].id}'),
                  index: i,
                  count: items.length,
                  replacement: items[i],
                  onUp: () => save(movedReplacementIds(ids, items[i].id, -1)),
                  onDown: () => save(movedReplacementIds(ids, items[i].id, 1)),
                ),
            ],
          ),
        ),
      ],
      actions: [
        WpDialogAction(
          label: l10n.actionClose,
          testId: 'replacements-order-close',
          role: WpDialogActionRole.cancel,
        ),
      ],
    );
  }
}

/// One rule: position, drag handle, "triggers → replacement", move buttons.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    super.key,
    required this.index,
    required this.count,
    required this.replacement,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final int count;
  final Replacement replacement;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final id = replacement.id;
    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              identifier: 'replacements-order-drag-$id',
              child: KeyedSubtree(
                key: ValueKey('replacements-order-drag-$id'),
                child: Tooltip(
                  message: l10n.replacementsOrderDragHandle,
                  child: const Padding(
                    padding: EdgeInsets.all(WpSpacing.sm),
                    child: Icon(
                      LucideIcons.gripVertical,
                      size: WpIconSize.smMd,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: WpSpacing.xl,
            child: Text(
              '${index + 1}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: WpColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${replacement.triggers.join(', ')} → ${replacement.replacement}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Semantics(
            identifier: 'replacements-order-up-$id',
            child: KeyedSubtree(
              key: ValueKey('replacements-order-up-$id'),
              child: WpIconButton(
                icon: LucideIcons.arrowUp,
                tooltip: l10n.replacementsOrderMoveUp,
                onPressed: index > 0 ? onUp : null,
              ),
            ),
          ),
          Semantics(
            identifier: 'replacements-order-down-$id',
            child: KeyedSubtree(
              key: ValueKey('replacements-order-down-$id'),
              child: WpIconButton(
                icon: LucideIcons.arrowDown,
                tooltip: l10n.replacementsOrderMoveDown,
                onPressed: index < count - 1 ? onDown : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
