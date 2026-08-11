// Ticket 12 — the history avatar makes no claim about content any more. The
// app classifies nothing, so every entry wears the same microphone glyph and
// the hue is pure decoration, read straight off the slot Ticket 03 persisted
// on the entry. Three things have to hold and each has its own group below:
// the hue is the persisted slot and nothing else, the entry's own content no
// longer moves it, and all three history surfaces show the microphone.
//
// What is deliberately *not* here: the rotation itself — which entry gets
// which slot, and never twice in a row. That is written once at creation time
// and belongs to Ticket 03 (`database_test.dart`, `recording_store_test.dart`).
// This file only reads.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/history_card_view.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry({
  required String id,
  required String title,
  String tags = '[]',
  int colorSlot = 0,
}) => HistoryEntry(
  id: id,
  content: 'Content of $id',
  title: title,
  timestamp: DateTime(2026, 4, 14),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: tags,
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: colorSlot,
);

/// One entry per rotation position — the eight slots the write path rolls into.
final _oneEntryPerSlot = <HistoryEntry>[
  for (var slot = 0; slot < 8; slot++)
    _entry(id: 's$slot', title: 'Recording $slot', colorSlot: slot),
];

typedef _ViewBuilder = Widget Function(List<HistoryEntry> entries);

// Scrollable, but not lazy: every row has to be built for the sweep below to
// see all of them, which a ListView.builder would not guarantee.
Widget _list(List<HistoryEntry> entries) => SingleChildScrollView(
  child: Column(
    children: [
      for (final entry in entries)
        HistoryEntryRow(
          entry: entry,
          isSelected: false,
          onTap: () {},
          onCopy: () {},
          onPin: () {},
          onDelete: () {},
        ),
    ],
  ),
);

/// The same entries as cards. The card view caches the slot in its own
/// `State`, so the microphone-glyph guarantee has to be proven twice — a fix
/// applied to only one of the two views is the failure mode this arm catches.
Widget _cards(List<HistoryEntry> entries) => SingleChildScrollView(
  child: Column(
    children: [
      for (final entry in entries)
        SizedBox(
          width: 260,
          child: HistoryEntryCard(
            entry: entry,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            multiSelectMode: false,
            isChecked: false,
          ),
        ),
    ],
  ),
);

Iterable<HistoryEntryAvatar> _avatars(WidgetTester tester) =>
    tester.widgetList<HistoryEntryAvatar>(find.byType(HistoryEntryAvatar));

List<Color> _avatarColors(WidgetTester tester) =>
    _avatars(tester).map((a) => a.color).toList();

List<IconData> _avatarIcons(WidgetTester tester) =>
    _avatars(tester).map((a) => a.icon).toList();

/// Swallows the detail panel's long-standing tight-fit horizontal overflow so
/// it does not fail an avatar assertion — same carve-out, and same reason, as
/// `history_export_wiring_test.dart`.
void _ignoreOverflowErrors() {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.toString().contains('overflowed')) return;
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

void main() {
  group('The avatar hue is the persisted slot and nothing else', () {
    test('each of the eight slots resolves to its own decorative hue', () {
      final slots = _oneEntryPerSlot.map(historyAvatarSlot).toList();

      expect(
        slots,
        WpCategorySlot.categories,
        reason:
            'slot n must resolve to rotation position n — the read path is a '
            'plain index into the eight-slot space the write path rolls into',
      );
      expect(
        slots.toSet(),
        hasLength(8),
        reason: 'two rotation positions collapsed onto one hue',
      );
    });

    test('no rotation position lands on the neutral fallback', () {
      // The ninth slot is the uncategorised grey. It sits outside
      // `WpCategorySlot.categories` on purpose and the rotation must never
      // reach it, or one entry in nine would read as "special" while meaning
      // exactly what the other eight mean.
      expect(
        _oneEntryPerSlot.map(historyAvatarSlot),
        isNot(contains(WpCategorySlot.neutral)),
      );
      expect(
        WpCategorySlot.categories,
        isNot(contains(WpCategorySlot.neutral)),
      );
    });

    test('title and tags no longer move the hue', () {
      // Under the deleted keyword rules this entry was a "meeting" and took
      // that rule's hue. Its slot is picked one step off the tag axis *by
      // construction*, so this stays a statement about the read path even if
      // the tag hash or the palette order moves later.
      final tagSlot = categorySlotForTag('meeting');
      final decorSlot =
          (WpCategorySlot.categories.indexOf(tagSlot) + 1) %
          WpCategorySlot.categories.length;
      final meeting = _entry(
        id: 'm1',
        title: 'Weekly meeting',
        tags: '["meeting"]',
        colorSlot: decorSlot,
      );

      expect(historyAvatarSlot(meeting), WpCategorySlot.categories[decorSlot]);
      expect(
        historyAvatarSlot(meeting),
        isNot(tagSlot),
        reason:
            'the avatar hue followed the content again — the tag axis is a '
            'separate scale and the avatar is decoration, not a category',
      );
    });

    test('the hue follows the slot across unrelated titles', () {
      final same = [
        _entry(id: 'a', title: 'Standup Tuesday', colorSlot: 5),
        _entry(id: 'b', title: '', colorSlot: 5),
        _entry(
          id: 'c',
          title: 'Blog draft',
          tags: '["personal"]',
          colorSlot: 5,
        ),
      ].map(historyAvatarSlot).toSet();

      expect(same, {WpCategorySlot.categories[5]});
      expect(
        historyAvatarSlot(_entry(id: 'd', title: 'Standup Tuesday')),
        isNot(WpCategorySlot.categories[5]),
        reason:
            'the same title under a different slot must take a different hue '
            '— otherwise something is still deriving color from content',
      );
    });
  });

  group('One microphone glyph everywhere', () {
    final views = <String, _ViewBuilder>{'list': _list, 'card grid': _cards};

    for (final view in views.entries) {
      testWidgets('the history ${view.key} shows nothing but the microphone', (
        tester,
      ) async {
        await tester.pumpWidget(makeTestable(view.value(_oneEntryPerSlot)));

        expect(
          _avatarIcons(tester),
          List.filled(_oneEntryPerSlot.length, LucideIcons.mic),
          reason:
              'a glyph other than the microphone claims the app understood '
              'what kind of thing was dictated. It does not.',
        );
        expect(
          _avatarColors(tester),
          [
            for (final entry in _oneEntryPerSlot)
              historyAvatarSlot(entry).color(),
          ],
          reason: 'the ${view.key} paints a hue its entry does not carry',
        );
      });
    }

    testWidgets('the detail header shows the same glyph and the same hue', (
      tester,
    ) async {
      _ignoreOverflowErrors();
      final entry = _entry(id: 'd1', title: 'Slot seven', colorSlot: 7);

      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          // Wide enough for the master/detail split to open the panel next to
          // the list rather than replacing it.
          size: const Size(1800, 900),
          locale: const Locale('en'),
          overrides: [
            historyEntriesProvider.overrideWith((ref) => Stream.value([entry])),
            archivedEntriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Slot seven').first);
      await tester.pumpAndSettle();

      // Two avatars now: the list row and the detail header. Both are the one
      // entry's, so both owe the same glyph and the same hue.
      expect(_avatarIcons(tester), [LucideIcons.mic, LucideIcons.mic]);
      expect(
        _avatarColors(tester),
        everyElement(WpCategorySlot.categories[7].color()),
      );

      // Drain pending Drift/Riverpod cleanup timers before teardown — see
      // history_export_wiring_test.dart for the invariant this protects.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Removed 2026-08-11 (dark-only build): this group ('Runtime theme
  // switch') proved that flipping Brightness.dark → Brightness.light on the
  // same widget State still repainted every avatar with the correct hue,
  // guarding against a cached `Color` surviving the switch. The app now
  // ships a single dark theme only, so there is no runtime theme switch left
  // to prove — the state-identity/cache-trap guarantee this group existed
  // for no longer has a scenario to exercise.

  group('Tag chips', () {
    testWidgets('carry their tag\'s category hue at 12 % fill / 30 % border', (
      tester,
    ) async {
      final entry = _entry(
        id: 't1',
        title: 'Weekly meeting',
        tags: '["meeting"]',
      );

      await tester.pumpWidget(makeTestable(_list([entry])));

      final chip = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('#meeting'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = chip.decoration! as BoxDecoration;
      final slot = categorySlotForTag('meeting');

      expect(decoration.color, slot.chipFill());
      expect(decoration.border!.top.color, slot.chipBorder());

      final label = tester.widget<Text>(find.text('#meeting'));
      expect(
        label.style!.color,
        WpColorsDark.textSecondary,
        reason:
            'the label stays neutral — eight hues behind a 10px word is eight '
            'contrast problems, and the tag name already carries the meaning',
      );
    });
  });
}
