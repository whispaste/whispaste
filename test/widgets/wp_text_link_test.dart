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

  testWidgets('resting text uses the accent role', (tester) async {
    await tester.pumpWidget(
      makeTestable(WpTextLink(label: 'Link', onPressed: () {})),
    );

    final text = tester.widget<Text>(find.text('Link'));
    expect(text.style?.color, WpColors.accent);
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

  testWidgets('leading icon renders when given', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        WpTextLink(
          label: 'Kontext',
          icon: Icons.visibility_outlined,
          onPressed: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });
  testWidgets('a long label wraps at a large text size instead of '
      'overflowing (UX-030)', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: SizedBox(
            width: 240,
            child: WpTextLink(
              label: 'Trigger word and hotkey in Settings',
              icon: Icons.settings,
              onPressed: () {},
            ),
          ),
        ),
        size: const Size(400, 600),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.text('Trigger word and hotkey in Settings')).width,
      lessThanOrEqualTo(240),
    );
  });
}
