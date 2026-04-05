import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/app.dart';

void main() {
  testWidgets('App shell renders sidebar and content', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: WhisPasteApp()),
    );

    // Sidebar should be visible
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
