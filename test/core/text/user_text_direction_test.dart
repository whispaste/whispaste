/// User text keeps its own direction inside a UI of the other direction
/// (#1845): a German recording in the Hebrew UI ends with its full stop and
/// its ellipsis on the right, not at the start of the line.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/user_text_direction.dart';
import 'package:whispaste/features/history/widgets/highlighted_text.dart';

void main() {
  test('direction follows the first strong letter', () {
    expect(userTextDirection('Hallo Welt.'), TextDirection.ltr);
    expect(userTextDirection('שלום עולם.'), TextDirection.rtl);
    expect(userTextDirection('42 — Hallo'), TextDirection.ltr);
    expect(userTextDirection('123 ...'), isNull);
  });

  Future<RenderParagraph> pumpIn(
    WidgetTester tester,
    TextDirection ui,
    String text,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Directionality(
          textDirection: ui,
          child: SizedBox(
            width: 200,
            child: HighlightedText(
              text: text,
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderParagraph>(find.byType(RichText));
  }

  testWidgets('a Latin entry in the Hebrew UI runs left to right, '
      'aligned to the UI start', (tester) async {
    final p = await pumpIn(tester, TextDirection.rtl, 'Hallo Welt.');
    expect(p.textDirection, TextDirection.ltr);
    expect(p.textAlign, TextAlign.right);
  });

  testWidgets('a Hebrew entry in the German UI runs right to left', (
    tester,
  ) async {
    final p = await pumpIn(tester, TextDirection.ltr, 'שלום עולם.');
    expect(p.textDirection, TextDirection.rtl);
    expect(p.textAlign, TextAlign.left);
  });
}
