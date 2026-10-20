// Shortcut keycaps stay in reading order under an RTL locale (UX-024): a
// neutral symbol such as "⌘" or "⇧" would otherwise take the paragraph
// direction and render "D ⌘ ⇧" in Hebrew.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/widgets/wp_keycap.dart';

void main() {
  for (final dock in [false, true]) {
    testWidgets('keycap "⌘ ⇧ D" keeps LTR order under RTL (dock: $dock)', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: Center(
              child: dock
                  ? const WpKeycap.dock(label: '⌘ ⇧ D')
                  : const WpKeycap(label: '⌘ ⇧ D'),
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(WpKeycap),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.textDirection, TextDirection.ltr);
    });
  }
}
