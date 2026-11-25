import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/accessibility/announce.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_focus_ring.dart';
import 'overview_providers.dart';

/// Size of the grip at the top centre of a card. It sits in the card's own
/// top padding (24 px), so it covers nothing of the card.
const double _kGripWidth = WpSpacing.xxxl;
const double _kGripHeight = WpSpacing.xl;

/// Whether a card of the Übersicht is being dragged: the page then offers
/// a drop place at the end of each column, and an empty side column.
class OverviewDragActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool active}) => state = active;
}

final overviewDragActiveProvider =
    NotifierProvider<OverviewDragActiveNotifier, bool>(
      OverviewDragActiveNotifier.new,
    );

/// The cards [block] lines up with after a move: all [visible] cards in the
/// one-column layout ([side] null), else those of its column.
List<OverviewBlock> overviewColumnPeers(
  List<OverviewBlock> order,
  Set<OverviewBlock> sideBlocks,
  Iterable<OverviewBlock> visible, {
  required bool? side,
}) => [
  for (final b in order)
    if (visible.contains(b) && (side == null || sideBlocks.contains(b) == side))
      b,
];

/// Stores [order] (and, for a move across columns, [block]'s new column
/// [side]) and tells a screen reader where [block] landed among [peers].
/// Shared by the grip, the column drop places and the "Übersicht anpassen"
/// menu (#1970).
void applyOverviewMove(
  BuildContext context,
  WidgetRef ref, {
  required OverviewBlock block,
  required List<OverviewBlock> order,
  required Iterable<OverviewBlock> peers,
  bool? side,
}) {
  final notifier = ref.read(overviewPrefsProvider.notifier);
  unawaited(notifier.setBlockOrder(order));
  if (side != null &&
      ref.read(overviewPrefsProvider).sideBlocks.contains(block) != side) {
    unawaited(notifier.setBlockSide(block, side: side));
  }
  final line = [
    for (final b in order)
      if (b == block || peers.contains(b)) b,
  ];
  final l10n = L10n.of(context);
  announce(
    View.of(context),
    l10n.overviewMovedAnnounce(
      overviewBlockLabel(l10n, block),
      line.indexOf(block) + 1,
      line.length,
    ),
    Directionality.of(context),
  );
}

/// The name of [block] as "Übersicht anpassen" lists it.
String overviewBlockLabel(L10n l10n, OverviewBlock block) => switch (block) {
  OverviewBlock.figures => l10n.overviewFiguresTitle,
  OverviewBlock.recent => l10n.overviewRecentTitle,
  OverviewBlock.notes => l10n.navNotes,
  OverviewBlock.dictation => l10n.overviewLastDictationTitle,
  OverviewBlock.storage => l10n.overviewStorageTitle,
  OverviewBlock.system => l10n.overviewSystemTitle,
  OverviewBlock.news => l10n.overviewNewsTitle,
  OverviewBlock.weather => l10n.overviewWeatherTitle,
  OverviewBlock.community => l10n.overviewCommunityMenu,
};

/// #1970: one card of the Übersicht that can be moved. A grip sits at the
/// top centre of every card, always visible so the page stays calm and the
/// card plainly looks movable. Drag it onto another card to take that
/// card's place, also in the other column of the wide layout. With the
/// keyboard the grip is a Tab stop: up and down move the card within its
/// column, left and right (mirrored in right-to-left languages) into the
/// other column. The screen reader gets the same moves as actions and hears
/// the new place. Nothing animates, so "reduce motion" has nothing to stop.
class OverviewMovableCard extends ConsumerStatefulWidget {
  const OverviewMovableCard({
    super.key,
    required this.block,
    required this.visible,
    required this.side,
    required this.child,
    this.reserveTop = false,
  });

  final OverviewBlock block;

  /// All shown cards of the page, in page order.
  final List<OverviewBlock> visible;

  /// The column of the wide layout the card sits in (true: side column), or
  /// null in the one-column layout.
  final bool? side;

  final Widget child;

  /// True for a block without a card padding on top ("Mitmachen"): the grip
  /// gets a band of its own above it.
  final bool reserveTop;

  @override
  ConsumerState<OverviewMovableCard> createState() =>
      _OverviewMovableCardState();
}

class _OverviewMovableCardState extends ConsumerState<OverviewMovableCard> {
  final FocusNode _grip = FocusNode(debugLabel: 'OverviewCardGrip');
  bool _dragging = false;

  @override
  void dispose() {
    _grip.dispose();
    super.dispose();
  }

  List<OverviewBlock> _peers(bool? side) {
    final prefs = ref.read(overviewPrefsProvider);
    return overviewColumnPeers(
      prefs.blockOrder,
      prefs.sideBlocks,
      widget.visible,
      side: side,
    );
  }

  void _step({required bool later}) {
    final peers = _peers(widget.side);
    final order = overviewMoveBlockStep(
      ref.read(overviewPrefsProvider).blockOrder,
      widget.block,
      later: later,
      peers: peers,
    );
    if (order == null) return;
    applyOverviewMove(
      context,
      ref,
      block: widget.block,
      order: order,
      peers: peers,
    );
  }

  /// Into the other column of the wide layout; the card keeps its place in
  /// the shared order, so it lands among its neighbours there.
  void _switchColumn({required bool toSide}) {
    final side = widget.side;
    if (side == null || side == toSide) return;
    applyOverviewMove(
      context,
      ref,
      block: widget.block,
      order: ref.read(overviewPrefsProvider).blockOrder,
      peers: _peers(toSide),
      side: toSide,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _step(later: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _step(later: true);
      return KeyEventResult.handled;
    }
    if (widget.side != null &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      // The side column is at the end of the reading direction.
      final rtl = Directionality.of(context) == TextDirection.rtl;
      _switchColumn(toSide: (key == LogicalKeyboardKey.arrowRight) != rtl);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setDragging(bool on) {
    setState(() => _dragging = on);
    ref.read(overviewDragActiveProvider.notifier).set(active: on);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = overviewBlockLabel(l10n, widget.block);
    final side = widget.side;

    final grip = Semantics(
      key: ValueKey('overview-move-${widget.block.id}'),
      container: true,
      label: l10n.overviewMoveCard(label),
      hint: l10n.overviewMoveHint,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.overviewMoveEarlier): () =>
            _step(later: false),
        CustomSemanticsAction(label: l10n.overviewMoveLater): () =>
            _step(later: true),
        if (side != null)
          CustomSemanticsAction(label: l10n.overviewMoveOtherColumn): () =>
              _switchColumn(toSide: !side),
      },
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _grip,
          onKeyEvent: _onKey,
          child: WpFocusRing(
            focusNode: _grip,
            radius: WpRadius.sm,
            child: Tooltip(
              message: l10n.overviewMoveHint,
              waitDuration: WpMotion.tooltipWait,
              excludeFromSemantics: true,
              child: MouseRegion(
                cursor: _dragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab,
                child: Draggable<OverviewBlock>(
                  data: widget.block,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  onDragStarted: () => _setDragging(true),
                  onDragEnd: (_) => _setDragging(false),
                  feedback: _DragChip(label: label),
                  child: SizedBox(
                    width: _kGripWidth,
                    height: _kGripHeight,
                    child: Icon(
                      LucideIcons.gripHorizontal,
                      size: WpSpacing.md,
                      color: WpColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return DragTarget<OverviewBlock>(
      onWillAcceptWithDetails: (d) => d.data != widget.block,
      onAcceptWithDetails: (d) {
        final order = overviewMoveBlockTo(
          ref.read(overviewPrefsProvider).blockOrder,
          d.data,
          target: widget.block,
        );
        applyOverviewMove(
          context,
          ref,
          block: d.data,
          order: order,
          peers: _peers(side),
          side: side,
        );
      },
      builder: (context, candidates, _) {
        final incoming = candidates.whereType<OverviewBlock>().firstOrNull;
        // The card coming from below lands before this one, from above after.
        final order = ref.watch(
          overviewPrefsProvider.select((p) => p.blockOrder),
        );
        final fromBelow =
            incoming != null &&
            order.indexOf(incoming) > order.indexOf(widget.block);
        return Stack(
          children: [
            Opacity(
              opacity: _dragging ? 0.4 : 1,
              child: Padding(
                padding: EdgeInsets.only(
                  top: widget.reserveTop ? _kGripHeight : 0,
                ),
                child: widget.child,
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: Center(child: grip)),
            if (incoming != null)
              Positioned(
                left: 0,
                right: 0,
                top: fromBelow ? 0 : null,
                bottom: fromBelow ? null : 0,
                child: const _DropLine(),
              ),
          ],
        );
      },
    );
  }
}

/// The drop place at the end of a column of the wide layout, shown only
/// while a card is dragged (#1970): a card dropped here goes to the end of
/// [blocks] in that column. It also stands in for an empty side column.
class OverviewColumnDrop extends ConsumerWidget {
  const OverviewColumnDrop({
    super.key,
    required this.side,
    required this.blocks,
    required this.visible,
  });

  /// The column: true for the side column.
  final bool side;

  /// The shown cards of this column, in page order.
  final List<OverviewBlock> blocks;

  /// All shown cards of the page.
  final List<OverviewBlock> visible;

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => DragTarget<OverviewBlock>(
    key: ValueKey('overview-column-drop-${side ? 'side' : 'main'}'),
    onAcceptWithDetails: (d) {
      final prefs = ref.read(overviewPrefsProvider);
      final rest = [
        for (final b in blocks)
          if (b != d.data) b,
      ];
      final order = rest.isEmpty
          ? prefs.blockOrder
          : overviewMoveBlockAfter(prefs.blockOrder, d.data, after: rest.last);
      final peers = {
        ...overviewColumnPeers(order, prefs.sideBlocks, visible, side: side),
        d.data,
      };
      applyOverviewMove(
        context,
        ref,
        block: d.data,
        order: order,
        peers: peers,
        side: side,
      );
    },
    builder: (context, candidates, _) => SizedBox(
      width: double.infinity,
      height: WpSpacing.xxxl,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WpRadius.md),
          border: Border.all(
            color: candidates.isEmpty ? WpColors.borderSubtle : WpColors.accent,
          ),
        ),
      ),
    ),
  );
}

class _DropLine extends StatelessWidget {
  const _DropLine();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('overview-move-drop-line'),
    height: WpSpacing.xxs,
    decoration: BoxDecoration(
      color: WpColors.accent,
      borderRadius: BorderRadius.circular(WpRadius.full),
    ),
  );
}

/// What follows the pointer while a card is dragged: its name in a chip.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Material(
    color: WpColors.floatingSurface,
    elevation: 4,
    borderRadius: BorderRadius.circular(WpRadius.sm),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.gripHorizontal,
            size: WpSpacing.md,
            color: WpColors.textMuted,
          ),
          const SizedBox(width: WpSpacing.sm),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );
}
