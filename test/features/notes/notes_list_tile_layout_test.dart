/// Layout of a note row (UX-036): the body is sized to its content instead of
/// to the 48 px touch box of the favourite star, the metadata line sits inside
/// the body above the divider, and a note that is not from today shows its
/// date next to its time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';

import '../../fixtures/test_helpers.dart';

Note _note({required String content, required DateTime updatedAt}) => Note(
  id: 'n1',
  content: content,
  pinned: false,
  isQuickNote: false,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

Widget _row(Note note) => SizedBox(
  width: 480,
  child: NotesListTile(
    note: note,
    tags: const [],
    isTrashView: false,
    isSelected: false,
    isFocused: false,
    onTap: () {},
    onCopy: () {},
    onDuplicate: () {},
    onFavoriteToggle: () {},
    onQuickNoteSet: () {},
    onQuickNoteClear: () {},
    onRestore: () {},
    onDeleteForever: () {},
  ),
);

Future<void> _pump(WidgetTester tester, Note note) async {
  await tester.pumpWidget(
    makeTestable(Center(child: _row(note)), locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await L10n.delegate.load(const Locale('en'));
  });

  group('note row layout (UX-036)', () {
    testWidgets('single-line note is sized to its content, not to the star', (
      tester,
    ) async {
      final now = DateTime.now();
      await _pump(
        tester,
        _note(
          content: 'Einkaufsliste',
          updatedAt: DateTime(now.year, now.month, now.day, 16, 58),
        ),
      );

      // A single-line row used to stand at about 83 px: the title line was
      // forced to the 48 px favourite touch box, and the metadata sat below it.
      final height = tester.getSize(find.byType(NotesListTile)).height;
      // Measured 76.0 px: title line, 4 px gap, metadata line, row padding.
      expect(height, 76.0);
    });

    testWidgets('metadata line keeps its distance above the divider', (
      tester,
    ) async {
      final now = DateTime.now();
      await _pump(
        tester,
        _note(
          content: 'Einkaufsliste',
          updatedAt: DateTime(now.year, now.month, now.day, 16, 58),
        ),
      );

      final time = tester.getRect(find.text('16:58'));
      final divider = tester.getRect(
        find.byKey(const ValueKey('wp-list-tile-divider')),
      );
      // The row's own panel padding (14 px) separates the text from the rule.
      // Measured at 5 px before the fix.
      expect(
        divider.top - time.bottom,
        greaterThanOrEqualTo(WpListTileSurface.panelVerticalPadding - 1),
      );
    });

    testWidgets('today shows only the time', (tester) async {
      final now = DateTime.now();
      await _pump(
        tester,
        _note(
          content: 'Einkaufsliste',
          updatedAt: DateTime(now.year, now.month, now.day, 16, 58),
        ),
      );

      expect(find.text('16:58'), findsOneWidget);
    });

    testWidgets('an older note shows its date next to its time', (
      tester,
    ) async {
      final updated = DateTime(2026, 4, 14, 9, 41);
      await _pump(tester, _note(content: 'Einkaufsliste', updatedAt: updated));

      final expected = '${DateFormat.MMMd('en').format(updated)} · 09:41';
      expect(find.text(expected), findsOneWidget);
    });
  });
}
