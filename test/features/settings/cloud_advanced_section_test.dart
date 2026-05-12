import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/settings/sections/cloud_advanced_section.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('CloudProvidersSection — free-tier hints', () {
    testWidgets('renders OpenAI hint text', (tester) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('platform.openai.com/api-keys'),
        findsOneWidget,
      );
    });

    testWidgets('renders Deepgram hint text', (tester) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      expect(find.textContaining('console.deepgram.com'), findsOneWidget);
    });

    testWidgets('OpenAI hint has a GestureDetector with correct key', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('openai-hint')), findsOneWidget);
    });

    testWidgets('Deepgram hint has a GestureDetector with correct key', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deepgram-hint')), findsOneWidget);
    });

    testWidgets('hint rows use externalLink Lucide icon', (tester) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      final icons = tester.widgetList<Icon>(find.byType(Icon));
      final hasExternalLink = icons.any(
        (i) => i.icon == LucideIcons.externalLink,
      );
      expect(hasExternalLink, isTrue);
    });

    testWidgets('hint rows meet minimum touch-target height of 48', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      final sizeds = tester.widgetList<SizedBox>(find.byType(SizedBox));
      // At least two SizedBox with height 48 (one per hint row).
      final touchTargets = sizeds
          .where((s) => s.height != null && s.height! >= 48)
          .toList();
      expect(touchTargets.length, greaterThanOrEqualTo(2));
    });

    testWidgets('tapping OpenAI hint does not throw', (tester) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      // Tap on the hint row — url_launcher will fail silently in tests
      // (no platform channel registered), but the widget must not crash.
      await tester.tap(
        find.byKey(const Key('openai-hint')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Deepgram hint does not throw', (tester) async {
      await tester.pumpWidget(makeTestable(const CloudProvidersSection()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('deepgram-hint')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
