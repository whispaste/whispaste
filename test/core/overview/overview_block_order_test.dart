import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/overview_logic.dart';

/// #1970: the stored order of the Übersicht cards and the two moves (drag
/// onto a card, one keyboard step).
void main() {
  const figures = OverviewBlock.figures;
  const recent = OverviewBlock.recent;
  const notes = OverviewBlock.notes;
  const dictation = OverviewBlock.dictation;
  const storage = OverviewBlock.storage;
  const news = OverviewBlock.news;
  const community = OverviewBlock.community;

  group('stored order', () {
    test(
      'nothing stored keeps the former page order for existing installs',
      () {
        final order = overviewBlockOrderFromStored(null);
        expect(order, kOverviewDefaultBlockOrder);
        expect(overviewBlockOrderFromStored(''), kOverviewDefaultBlockOrder);
        expect(overviewBlockOrderIsCustom(order), isFalse);
        // The wide layout reads the same list per column: its former order.
        expect(
          [
            for (final b in order)
              if (!b.side) b,
          ],
          [recent, notes, news, community],
        );
        expect(
          [
            for (final b in order)
              if (b.side) b,
          ],
          [
            figures,
            dictation,
            storage,
            OverviewBlock.system,
            OverviewBlock.weather,
          ],
        );
      },
    );

    test('every block is in the default order exactly once', () {
      expect(kOverviewDefaultBlockOrder.toSet(), OverviewBlock.values.toSet());
      expect(kOverviewDefaultBlockOrder.length, OverviewBlock.values.length);
    });

    test('round trip, unknown and repeated ids dropped', () {
      final moved = overviewMoveBlockTo(
        kOverviewDefaultBlockOrder,
        community,
        target: figures,
      );
      expect(
        overviewBlockOrderFromStored(overviewBlockOrderToStored(moved)),
        moved,
      );
      final parsed = overviewBlockOrderFromStored('notes, gone ,notes,recent');
      expect(parsed.indexOf(notes), lessThan(parsed.indexOf(recent)));
      expect(parsed.toSet(), OverviewBlock.values.toSet());
      expect(parsed.length, OverviewBlock.values.length);
    });

    test('a block the stored list lacks takes its default place', () {
      // Stored by a version without "storage": it follows "dictation".
      final order = overviewBlockOrderFromStored(
        'notes,recent,figures,dictation,system,weather,news,community',
      );
      expect(order.indexOf(storage), order.indexOf(dictation) + 1);
      // Missing first block of the default order goes to the top.
      final noFigures = overviewBlockOrderFromStored(
        'recent,notes,dictation,storage,system,weather,news,community',
      );
      expect(noFigures.first, figures);
    });
  });

  group('moves', () {
    test('dragging down lands after the target, up before it', () {
      final down = overviewMoveBlockTo(
        kOverviewDefaultBlockOrder,
        recent,
        target: dictation,
      );
      expect(down.indexOf(recent), down.indexOf(dictation) + 1);
      final up = overviewMoveBlockTo(
        kOverviewDefaultBlockOrder,
        news,
        target: recent,
      );
      expect(up.indexOf(news), up.indexOf(recent) - 1);
      expect(overviewBlockOrderIsCustom(up), isTrue);
    });

    test('a keyboard step skips cards that are not among the peers', () {
      // Main column of the wide layout with "Notizen" hidden.
      const peers = [recent, news, community];
      final order = overviewMoveBlockStep(
        kOverviewDefaultBlockOrder,
        news,
        later: false,
        peers: peers,
      )!;
      expect(
        [
          for (final b in order)
            if (peers.contains(b)) b,
        ],
        [news, recent, community],
      );
    });

    test('no step past the edge', () {
      expect(
        overviewMoveBlockStep(
          kOverviewDefaultBlockOrder,
          figures,
          later: false,
          peers: OverviewBlock.values,
        ),
        isNull,
      );
      expect(
        overviewMoveBlockStep(
          kOverviewDefaultBlockOrder,
          community,
          later: true,
          peers: OverviewBlock.values,
        ),
        isNull,
      );
    });
  });

  group('columns', () {
    test('nothing stored keeps the former columns', () {
      expect(overviewSideBlocksFromStored(null), kOverviewDefaultSideBlocks);
      expect(
        overviewSideBlocksFromStored(kOverviewSideBlocksDefault),
        kOverviewDefaultSideBlocks,
      );
      expect(kOverviewDefaultSideBlocks, {
        for (final b in OverviewBlock.values)
          if (b.side) b,
      });
      expect(overviewSideBlocksAreCustom(kOverviewDefaultSideBlocks), isFalse);
    });

    test('an empty side column is a choice of its own and round trips', () {
      expect(overviewSideBlocksFromStored(''), isEmpty);
      final moved = {...kOverviewDefaultSideBlocks, recent}..remove(figures);
      expect(
        overviewSideBlocksFromStored(overviewSideBlocksToStored(moved)),
        moved,
      );
      expect(overviewSideBlocksAreCustom(moved), isTrue);
    });

    test('a card dropped at the end of a column follows its last card', () {
      final order = overviewMoveBlockAfter(
        kOverviewDefaultBlockOrder,
        recent,
        after: storage,
      );
      expect(order.indexOf(recent), order.indexOf(storage) + 1);
      expect(overviewMoveBlockAfter(order, recent, after: recent), same(order));
    });
  });
}
