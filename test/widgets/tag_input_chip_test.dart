/// Tag chip remove control (UIA-CMP-04, UIA-CMP-05).
///
/// The remove glyph is the only visible way to delete a tag, so it must read
/// at rest (not only on hover), and its screen-reader label must follow the
/// app language.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/widgets/tag_input.dart';

import '../fixtures/test_helpers.dart';

Widget _chip({Locale? locale}) => makeTestable(
  WpTagInput(
    tags: [Tag(id: 't1', name: 'Fachbegriff', createdAt: DateTime(2026))],
    onAdd: (_) {},
    onRemove: (_) {},
    hintText: 'Tag',
    searchHintText: 'Tag suchen',
  ),
  locale: locale,
);

void main() {
  testWidgets('remove glyph is readable at rest, not only on hover (CMP-04)', (
    tester,
  ) async {
    await tester.pumpWidget(_chip());
    await tester.pumpAndSettle();

    final fade = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byIcon(LucideIcons.x),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(
      fade.opacity,
      greaterThanOrEqualTo(0.6),
      reason: 'at rest the only delete affordance must reach about 3:1',
    );
  });

  testWidgets('remove label follows the app language (CMP-05)', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_chip(locale: const Locale('de')));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Tag „Fachbegriff“ entfernen'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Remove Fachbegriff'), findsNothing);
    handle.dispose();
  });
}
