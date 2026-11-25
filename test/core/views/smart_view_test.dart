import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/views/smart_view.dart';

void main() {
  final now = DateTime(2026, 11, 23, 15);

  SmartViewItem item({
    DateTime? date,
    Set<String> tagIds = const {},
    Set<String> tagNames = const {},
    Set<SmartViewSource> sources = const {},
    bool hasChecklist = false,
    bool pinned = false,
  }) => SmartViewItem(
    date: date ?? now,
    tagIds: tagIds,
    tagNames: tagNames,
    sources: sources,
    hasChecklist: hasChecklist,
    pinned: pinned,
  );

  group('rules', () {
    test('each rule reads its own field', () {
      final cases = <(SmartRule, SmartViewItem, bool)>[
        (
          const TagRule(tagId: 't1', tagName: 'Work'),
          item(tagIds: {'t1'}),
          true,
        ),
        (
          const TagRule(tagId: 't1', tagName: 'Work'),
          item(tagNames: {'work'}),
          true,
        ),
        (
          const TagRule(tagId: 't1', tagName: 'Work'),
          item(tagIds: {'t2'}),
          false,
        ),
        (const TagRule(tagId: 't1', tagName: ''), item(tagNames: {''}), false),
        (const UntaggedRule(), item(), true),
        (const UntaggedRule(), item(tagNames: {'x'}), false),
        (const UntaggedRule(), item(tagIds: {'t1'}), false),
        (const ChecklistRule(), item(hasChecklist: true), true),
        (const ChecklistRule(), item(), false),
        (const PinnedRule(), item(pinned: true), true),
        (const PinnedRule(), item(), false),
        (
          const SourceRule(SmartViewSource.quickNote),
          item(sources: {SmartViewSource.quickNote}),
          true,
        ),
        (
          const SourceRule(SmartViewSource.audioImport),
          item(sources: {SmartViewSource.dictation}),
          false,
        ),
      ];
      for (final (rule, it, expected) in cases) {
        expect(rule.matches(it, now), expected, reason: '$rule');
      }
    });

    test('periods count calendar days, today included', () {
      final cases = <(SmartViewPeriod, DateTime, bool)>[
        (SmartViewPeriod.today, DateTime(2026, 11, 23), true),
        (SmartViewPeriod.today, DateTime(2026, 11, 22, 23, 59), false),
        (SmartViewPeriod.week, DateTime(2026, 11, 17), true),
        (SmartViewPeriod.week, DateTime(2026, 11, 16, 23, 59), false),
        (SmartViewPeriod.month, DateTime(2026, 10, 25), true),
        (SmartViewPeriod.month, DateTime(2026, 10, 24, 12), false),
      ];
      for (final (period, at, expected) in cases) {
        expect(
          PeriodRule(period).matches(item(date: at), now),
          expected,
          reason: '$period $at',
        );
      }
    });

    test('sources per scope never mix', () {
      expect(sourcesFor(SmartViewScope.notes), [
        SmartViewSource.quickNote,
        SmartViewSource.fromRecording,
      ]);
      expect(sourcesFor(SmartViewScope.recordings), [
        SmartViewSource.dictation,
        SmartViewSource.audioImport,
      ]);
    });
  });

  group('views', () {
    const rules = <SmartRule>[
      TagRule(tagId: 't1', tagName: 'Work'),
      ChecklistRule(),
    ];

    test('"all" needs every rule, "any" one of them', () {
      const all = SmartView(id: 'a', name: 'A', rules: rules);
      const any = SmartView(
        id: 'b',
        name: 'B',
        rules: rules,
        match: SmartViewMatch.any,
      );
      final both = item(tagIds: {'t1'}, hasChecklist: true);
      final one = item(tagIds: {'t1'});
      final none = item();
      expect(smartViewMatches(all, both, now), isTrue);
      expect(smartViewMatches(all, one, now), isFalse);
      expect(smartViewMatches(any, one, now), isTrue);
      expect(smartViewMatches(any, none, now), isFalse);
    });

    test('a view without rules shows nothing', () {
      const empty = SmartView(id: 'e', name: 'E', rules: []);
      expect(smartViewMatches(empty, item(), now), isFalse);
    });

    test('built-in views per scope', () {
      expect(builtInSmartViews(SmartViewScope.notes).map((v) => v.id), [
        BuiltInSmartViews.recent,
        BuiltInSmartViews.pinned,
        BuiltInSmartViews.untagged,
        BuiltInSmartViews.quickNotes,
        BuiltInSmartViews.checklist,
      ]);
      expect(
        builtInSmartViews(SmartViewScope.recordings).map((v) => v.id),
        isNot(contains(BuiltInSmartViews.quickNotes)),
      );
      expect(
        builtInSmartViews(SmartViewScope.notes).every((v) => v.builtIn),
        isTrue,
      );
      final recent = builtInSmartViews(SmartViewScope.notes).first;
      expect(
        smartViewMatches(recent, item(date: DateTime(2026, 11, 17)), now),
        isTrue,
      );
      expect(
        smartViewMatches(recent, item(date: DateTime(2026, 11, 1)), now),
        isFalse,
      );
    });
  });

  group('storage', () {
    test(
      'round trip keeps name, match and rules; built-ins are not stored',
      () {
        const own = SmartView(
          id: 'v1',
          name: 'Projekt',
          match: SmartViewMatch.any,
          rules: [
            TagRule(tagId: 't1', tagName: 'Work'),
            UntaggedRule(),
            PeriodRule(SmartViewPeriod.month),
            SourceRule(SmartViewSource.fromRecording),
            ChecklistRule(),
            PinnedRule(),
            FolderRule(folderId: 'f1', folderName: 'Clients'),
          ],
        );
        final raw = encodeSmartViews([
          ...builtInSmartViews(SmartViewScope.notes),
          own,
        ]);
        final back = decodeSmartViews(raw);
        expect(back, hasLength(1));
        expect(back.single.id, 'v1');
        expect(back.single.name, 'Projekt');
        expect(back.single.match, SmartViewMatch.any);
        expect(back.single.rules, own.rules);
        expect(back.single.builtIn, isFalse);
      },
    );

    test('broken input loses only what is broken', () {
      expect(decodeSmartViews(null), isEmpty);
      expect(decodeSmartViews(''), isEmpty);
      expect(decodeSmartViews('{not json'), isEmpty);
      expect(decodeSmartViews('{"id":"x"}'), isEmpty);
      final back = decodeSmartViews('''[
        {"id":"a","name":"A","rules":[{"type":"pinned"},{"type":"future"}]},
        {"id":"a","name":"Dup","rules":[{"type":"pinned"}]},
        {"id":"b","name":"B","rules":[{"type":"future"}]},
        {"id":"c","rules":[{"type":"pinned"}]},
        {"id":"d","name":"D","match":"weird","rules":[{"type":"tag"}, {"type":"checklist"}]},
        7
      ]''');
      expect(back.map((v) => v.id), ['a', 'd']);
      expect(back.first.name, 'A');
      expect(back.first.rules, [const PinnedRule()]);
      expect(back.last.match, SmartViewMatch.all);
      expect(back.last.rules, [const ChecklistRule()]);
    });
  });
}
