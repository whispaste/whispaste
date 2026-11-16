/// A read-only tag input shows the tags only (UIA-HIS-29), and the history
/// detail keeps its overflow menu named (UIA-HIS-22).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/widgets/tag_input.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets(
    'a read-only tag input shows the tags without add field or remove buttons (UIA-HIS-29)',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          Scaffold(
            body: WpTagInput(
              tags: [Tag(id: 't1', name: 'alpha', createdAt: DateTime(2026))],
              onAdd: (_) {},
              onRemove: (_) {},
              hintText: 'Add tag',
              searchHintText: 'Search tags',
              readOnly: true,
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('alpha'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Add tag'), findsNothing);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    },
  );

  test('the detail overflow menu has a tooltip (UIA-HIS-22)', () {
    final source = File(
      'lib/features/history/widgets/history_detail_panel.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("tooltip: ''")));
  });
}
