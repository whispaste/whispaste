// #58: every recording row shows the icon of the app it was pasted into.
// When no target app is known (older entries, no answer) the app segment is
// left out of the meta line, no empty slot between two separators (#1498).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/services/app_identity/app_category.dart';
import 'package:whispaste/services/app_identity/app_identity_service.dart';
import 'package:whispaste/widgets/wp_app_icon.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry({String? targetApp}) => HistoryEntry(
  id: 'target-1',
  content: 'Some content',
  title: 'Some title',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 10.0,
  processingDurationSec: 0.5,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  titleEdited: false,
  colorSlot: 0,
  targetApp: targetApp,
);

Future<void> _pumpRow(WidgetTester tester, HistoryEntry entry) async {
  await tester.pumpWidget(
    makeTestable(
      HistoryEntryRow(
        entry: entry,
        isSelected: false,
        onTap: () {},
        onCopy: () {},
        onPin: () {},
        onDelete: () {},
      ),
      overrides: [
        appIdentityProvider.overrideWith(
          (ref, id) async =>
              const AppIdentity(name: 'Notes', category: AppCategory.notes),
        ),
      ],
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a row with a target app shows that app', (tester) async {
    await _pumpRow(tester, _entry(targetApp: 'com.example.notes'));

    final icon = find.byKey(const ValueKey('history-entry-app-icon'));
    expect(icon, findsOneWidget);
    expect(tester.widget<WpAppIcon>(icon).identifier, 'com.example.notes');
    expect(
      find.byKey(const ValueKey('history-entry-app-unknown')),
      findsNothing,
    );
  });

  testWidgets('a row without a target app drops the app segment', (
    tester,
  ) async {
    await _pumpRow(tester, _entry());

    expect(find.byKey(const ValueKey('history-entry-app-icon')), findsNothing);
    _expectNoEmptySegment(tester);
  });

  testWidgets('a blank target app counts as unknown', (tester) async {
    await _pumpRow(tester, _entry(targetApp: '  '));

    expect(find.byKey(const ValueKey('history-entry-app-icon')), findsNothing);
    _expectNoEmptySegment(tester);
  });
}

void _expectNoEmptySegment(WidgetTester tester) {
  final meta = find.descendant(
    of: find.byKey(const ValueKey('history-row-meta-target-1')),
    matching: find.byType(RichText),
  );
  final text = tester.widget<RichText>(meta.first).text.toPlainText();
  expect(text, isNot(matches(RegExp(r'·\s*·'))));
  expect(text.trim(), isNot(startsWith('·')));
  expect(text.trim(), isNot(endsWith('·')));
}
