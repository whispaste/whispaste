// Ticket 13 — the history list's avatar hue is a *category* statement now, not
// a title hash. Three things have to hold and each has its own group below:
// the hue follows the avatar rule, the fallback stays out of the category hues,
// and a runtime theme switch repaints every avatar at once (the cache trap: the
// slot is cached, the color is not).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/history/widgets/history_card_view.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry({
  required String id,
  required String title,
  String tags = '[]',
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
  colorSlot: 0,
);

/// One entry per avatar rule, plus one that matches none.
final _oneEntryPerRule = <String, HistoryEntry>{
  'meeting': _entry(id: 'r1', title: 'Weekly meeting'),
  'email': _entry(id: 'r2', title: 'Email to Anna'),
  'blog': _entry(id: 'r3', title: 'Blog draft'),
  'personal': _entry(id: 'r4', title: 'Sunday', tags: '["personal"]'),
  'feedback': _entry(id: 'r5', title: 'Feedback round'),
  'project': _entry(id: 'r6', title: 'Project brief'),
  'idea': _entry(id: 'r7', title: 'Loose thought', tags: '["idea"]'),
  'reminder': _entry(id: 'r8', title: 'Reminder for tomorrow'),
};

final _fallbackEntry = _entry(id: 'f1', title: 'Recording 2026-04-14');

typedef _ViewBuilder =
    Widget Function(List<HistoryEntry> entries, {required bool isDark});

// Scrollable, but not lazy: every row has to be built for the sweep below to
// see all of them, which a ListView.builder would not guarantee.
Widget _list(List<HistoryEntry> entries, {required bool isDark}) =>
    SingleChildScrollView(
      child: Column(
        children: [
          for (final entry in entries)
            HistoryEntryRow(
              entry: entry,
              isDark: isDark,
              isSelected: false,
              onTap: () {},
              onCopy: () {},
              onPin: () {},
              onDelete: () {},
            ),
        ],
      ),
    );

/// The same nine entries as cards. The card view caches the slot in its own
/// `State`, so the theme-switch guarantee has to be proven twice — a fix
/// applied to only one of the two views is the failure mode this arm catches.
Widget _cards(List<HistoryEntry> entries, {required bool isDark}) =>
    SingleChildScrollView(
      child: Column(
        children: [
          for (final entry in entries)
            SizedBox(
              width: 260,
              child: HistoryEntryCard(
                entry: entry,
                isDark: isDark,
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

List<Color> _avatarColors(WidgetTester tester) => tester
    .widgetList<HistoryEntryAvatar>(find.byType(HistoryEntryAvatar))
    .map((a) => a.color)
    .toList();

void main() {
  group('Avatar hue follows the rule, not the title', () {
    test('each of the eight rules gets its own category slot', () {
      final slots = _oneEntryPerRule.map(
        (key, entry) => MapEntry(key, historyAvatarSlot(entry)),
      );

      expect(
        slots.values.toSet().length,
        8,
        reason:
            'two rules share a hue — the assignment is a bijection over a '
            'closed set of eight, so a collision is a defect, not a trade-off. '
            'Got: $slots',
      );
      expect(
        slots.values,
        isNot(contains(WpCategorySlot.neutral)),
        reason: 'neutral means "no category" and is never a rule\'s slot',
      );
    });

    test('two entries under one rule share a hue despite different titles', () {
      final standup = _entry(id: 'a', title: 'Standup Tuesday');
      final weekly = _entry(id: 'b', title: 'Weekly meeting with Tom');

      expect(historyAvatarSlot(standup), historyAvatarSlot(weekly));
      expect(historyAvatarIcon(standup), historyAvatarIcon(weekly));
    });

    test('the color is never the sole carrier — the icon says it too', () {
      final icons = _oneEntryPerRule.values.map(historyAvatarIcon).toSet();

      expect(
        icons.length,
        8,
        reason:
            'eight hues but fewer icons would leave the hue carrying meaning '
            'on its own for the rules that share a glyph',
      );
      expect(historyAvatarIcon(_fallbackEntry), LucideIcons.mic);
    });
  });

  group('The fallback is not a ninth category', () {
    test('an entry matching no rule takes the neutral slot', () {
      expect(historyAvatarSlot(_fallbackEntry), WpCategorySlot.neutral);
    });

    test('untitled entries do not hash into a category hue', () {
      for (final title in ['', 'Recording 3', 'Aufnahme vom Montag']) {
        expect(
          historyAvatarSlot(_entry(id: title, title: title)),
          WpCategorySlot.neutral,
          reason: '"$title" matches no rule and must stay uncategorised',
        );
      }
    });
  });

  group('Runtime theme switch', () {
    final views = <String, ({_ViewBuilder build, Type stateOwner})>{
      'list': (build: _list, stateOwner: HistoryEntryRow),
      'card grid': (build: _cards, stateOwner: HistoryEntryCard),
    };

    for (final view in views.entries) {
      testWidgets('repaints every avatar in the open history ${view.key}', (
        tester,
      ) async {
        final build = view.value.build;
        final entries = [..._oneEntryPerRule.values, _fallbackEntry];

        await tester.pumpWidget(makeTestable(build(entries, isDark: true)));
        final darkColors = _avatarColors(tester);
        final stateBefore = tester.state(
          find.byType(view.value.stateOwner).first,
        );

        // Same entries, same tree shape — only the theme flips, which is
        // exactly the case a cached `Color` survives and a cached slot does
        // not.
        await tester.pumpWidget(
          makeTestable(
            build(entries, isDark: false),
            brightness: Brightness.light,
          ),
        );
        final lightColors = _avatarColors(tester);
        final stateAfter = tester.state(
          find.byType(view.value.stateOwner).first,
        );

        expect(
          identical(stateBefore, stateAfter),
          isTrue,
          reason:
              'the ${view.key} was rebuilt from scratch, so this run would pass '
              'even against a cached color — the regression it guards needs the '
              'same State to survive the theme switch',
        );
        expect(darkColors.length, entries.length);
        for (var i = 0; i < entries.length; i++) {
          final slot = historyAvatarSlot(entries[i]);
          expect(darkColors[i], slot.color(true));
          expect(
            lightColors[i],
            slot.color(false),
            reason:
                'avatar ${entries[i].id} still paints the dark theme\'s hue '
                'after the switch — the resolved color was cached instead of '
                'the slot',
          );
        }
      });
    }
  });

  group('Tag chips', () {
    testWidgets('carry their tag\'s category hue at 12 % fill / 30 % border', (
      tester,
    ) async {
      final entry = _entry(
        id: 't1',
        title: 'Weekly meeting',
        tags: '["meeting"]',
      );

      await tester.pumpWidget(makeTestable(_list([entry], isDark: true)));

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

      expect(decoration.color, slot.chipFill(true));
      expect(decoration.border!.top.color, slot.chipBorder(true));

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
