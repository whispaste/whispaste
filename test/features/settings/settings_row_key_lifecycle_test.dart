/// Lifecycle of the static row-key map behind deep links: a row that leaves the
/// tree must drop its key, so per-object row ids (one per app rule) cannot grow
/// the map without bound. Logic only; no layout or appearance is checked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

void main() {
  testWidgets('a removed row releases its key, a kept row keeps it', (
    tester,
  ) async {
    Widget rows(List<String> ids) => MaterialApp(
      home: Column(
        children: [
          for (final id in ids)
            SettingsRowFrame(
              key: ValueKey('frame-$id'),
              rowId: id,
              child: const SizedBox(),
            ),
        ],
      ),
    );

    await tester.pumpWidget(rows(['keep', 'rule-1', 'rule-2']));
    expect(debugSettingsRowKeyCount, 3);

    await tester.pumpWidget(rows(['keep', 'rule-2']));
    await tester.pump();
    expect(debugSettingsRowKeyCount, 2);

    await tester.pumpWidget(rows(['keep']));
    await tester.pump();
    expect(debugSettingsRowKeyCount, 1);
  });

  testWidgets('deleting many per-object rows does not grow the map', (
    tester,
  ) async {
    Widget rows(int count) => MaterialApp(
      home: Column(
        children: [
          for (var i = 0; i < count; i++)
            SettingsRowFrame(
              key: ValueKey('frame-$i'),
              rowId: 'profiles-detail-apps-rule-$i',
              child: const SizedBox(),
            ),
        ],
      ),
    );

    for (var round = 0; round < 20; round++) {
      await tester.pumpWidget(rows(5));
      await tester.pumpWidget(rows(0));
      await tester.pump();
    }
    expect(debugSettingsRowKeyCount, 0);
  });

  testWidgets('a row that moves to another parent keeps its key', (
    tester,
  ) async {
    const frame = SettingsRowFrame(rowId: 'moved', child: SizedBox());
    final before = settingsRowKey('moved');

    await tester.pumpWidget(const MaterialApp(home: Column(children: [frame])));
    expect(before.currentContext, isNotNull);

    // New parent type: the frame state is recreated, the keyed subtree moves.
    await tester.pumpWidget(const MaterialApp(home: Row(children: [frame])));
    await tester.pump();

    expect(identical(settingsRowKey('moved'), before), isTrue);
    expect(before.currentContext, isNotNull);
  });

  testWidgets('an unkeyed list hands a state to another row: old id released', (
    tester,
  ) async {
    // No keys, as in profile_detail: deleting rule-1 moves rule-2 into the
    // slot of rule-1, so the same frame state now carries the id rule-2.
    Widget rows(List<String> ids) => MaterialApp(
      home: Column(
        children: [
          for (final id in ids)
            SettingsRowFrame(rowId: id, child: const SizedBox()),
        ],
      ),
    );

    await tester.pumpWidget(rows(['rule-1', 'rule-2']));
    expect(debugSettingsRowKeyCount, 2);

    await tester.pumpWidget(rows(['rule-2']));
    await tester.pump();
    expect(debugSettingsRowKeyCount, 1);
    expect(settingsRowKey('rule-2').currentContext, isNotNull);
  });
}
