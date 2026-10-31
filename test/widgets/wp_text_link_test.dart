import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_text_link.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('shows the label and fires onPressed on tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      makeTestable(
        WpTextLink(label: 'Kontextvorschau', onPressed: () => taps++),
      ),
    );

    expect(find.text('Kontextvorschau'), findsOneWidget);
    await tester.tap(find.text('Kontextvorschau'));
    expect(taps, 1);
  });

  testWidgets('disabled link is muted and does not respond', (tester) async {
    await tester.pumpWidget(
      makeTestable(const WpTextLink(label: 'Off', onPressed: null)),
    );

    final text = tester.widget<Text>(find.text('Off'));
    expect(text.style?.color, WpColors.textMuted);
    final semantics = tester.getSemantics(find.byType(WpTextLink));
    expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
  });

  testWidgets('exposes itself as a link with its label and testID', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        WpTextLink(label: 'Mehr', onPressed: () {}, testID: 'sample-link'),
      ),
    );

    expect(find.bySemanticsLabel('Mehr'), findsOneWidget);
    final node = tester.getSemantics(find.byType(WpTextLink));
    expect(node.flagsCollection.isLink, isTrue);
    expect(node.flagsCollection.isButton, isFalse);
    expect(node.identifier, 'sample-link');
    handle.dispose();
  });

  testWidgets('a link without a testID carries no identifier', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(WpTextLink(label: 'Mehr', onPressed: () {})),
    );

    expect(tester.getSemantics(find.byType(WpTextLink)).identifier, isEmpty);
    handle.dispose();
  });

  testWidgets('exposes itself as a link with its label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(WpTextLink(label: 'Mehr', onPressed: () {})),
    );

    expect(find.bySemanticsLabel('Mehr'), findsOneWidget);
    handle.dispose();
  });
}
