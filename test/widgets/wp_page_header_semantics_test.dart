/// The page title is a heading of its own: it must not merge into the
/// shell's node and turn everything around it into one heading (#1845).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

void main() {
  testWidgets('only the title is the heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Semantics(
          label: 'WhisPaste',
          child: const Column(
            children: [
              WpPageHeader(title: 'Overview'),
              Text('Body'),
            ],
          ),
        ),
      ),
    );
    final data = tester.getSemantics(find.text('Overview')).getSemanticsData();
    expect(data.flagsCollection.isHeader, isTrue);
    expect(data.label, 'Overview');
    final outer = tester.getSemantics(find.text('Body')).getSemanticsData();
    expect(outer.flagsCollection.isHeader, isFalse);
    handle.dispose();
  });
}
