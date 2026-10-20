/// A recording row shows its per-item actions while it is active. Those
/// actions must not take width from the metadata line (time, duration, words):
/// the title gives way instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry() => HistoryEntry(
  id: 'meta-1',
  content: 'Some transcript text for the preview line',
  title: 'Meeting notes',
  timestamp: DateTime(2026, 10, 17, 9, 30),
  durationSec: 95.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: false,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

/// [active] reveals the row actions (the row is focused or hovered).
Future<double> _metaMaxWidth(
  WidgetTester tester, {
  required bool active,
}) async {
  await tester.pumpWidget(
    makeTestable(
      SizedBox(
        width: 260,
        child: HistoryEntryRow(
          entry: _entry(),
          isSelected: false,
          isFocused: active,
          inSplitView: true,
          onTap: () {},
          onCopy: () {},
          onPin: () {},
          onDelete: () {},
          onDuplicate: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The metadata line is the one Text.rich carrying the separator dot.
  final meta = find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(' · '),
  );
  expect(meta, findsOneWidget);
  return tester.renderObject<RenderParagraph>(meta).constraints.maxWidth;
}

void main() {
  testWidgets('row actions do not narrow the metadata line of an active row', (
    tester,
  ) async {
    final idle = await _metaMaxWidth(tester, active: false);
    final active = await _metaMaxWidth(tester, active: true);
    expect(
      active,
      equals(idle),
      reason: 'the actions took ${idle - active} px from the metadata',
    );
  });
}
