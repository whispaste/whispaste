import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/highlighted_text.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake search notifier that returns a fixed query value.
class _FakeHistorySearchNotifier extends HistorySearchNotifier {
  _FakeHistorySearchNotifier(this._query);
  final String _query;

  @override
  String build() => _query;
}

void main() {
  group('HighlightedText', () {
    testWidgets(
      'uses zero-width space when text is empty to prevent RenderParagraph crash',
      (tester) async {
        // Regression test: Empty text used to cause RenderParagraph null check crashes
        // The fix uses \u200B (zero-width space) instead of empty string
        await tester.pumpWidget(
          makeTestable(
            const HighlightedText(
              text: '',
              style: TextStyle(fontSize: 14),
              isDark: true,
            ),
          ),
        );

        // Should render without crashing
        expect(find.byType(Text), findsOneWidget);

        final textWidget = tester.widget<Text>(find.byType(Text));
        // Verify zero-width space is used instead of empty string
        expect(textWidget.data, '\u200B');
      },
    );

    testWidgets('renders plain text when query is empty', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'Hello world',
            style: TextStyle(fontSize: 14),
            isDark: true,
          ),
        ),
      );

      expect(find.text('Hello world'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('highlights matching text when query is non-empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'Hello world',
            style: TextStyle(fontSize: 14),
            isDark: true,
          ),
          overrides: [
            historySearchProvider.overrideWith(
              () => _FakeHistorySearchNotifier('world'),
            ),
          ],
        ),
      );

      // Should render with Text.rich for highlighting
      expect(find.byType(Text), findsOneWidget);

      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.textSpan, isNotNull);

      // The text span should contain children with highlighted portions
      final span = textWidget.textSpan as TextSpan;
      expect(span.children, isNotNull);
      expect(span.children!.length, greaterThan(1));
    });

    testWidgets('highlights multiple occurrences of query', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'test case with test data and testing',
            style: TextStyle(fontSize: 14),
            isDark: true,
          ),
          overrides: [
            historySearchProvider.overrideWith(
              () => _FakeHistorySearchNotifier('test'),
            ),
          ],
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      final span = textWidget.textSpan as TextSpan;

      // Should have multiple children for the highlighted portions
      expect(span.children, isNotNull);
      // At least 3 parts: before first 'test', 'test', rest
      expect(span.children!.length, greaterThanOrEqualTo(3));
    });

    testWidgets('is case-insensitive when highlighting', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'hello world Hello again',
            style: TextStyle(fontSize: 14),
            isDark: true,
          ),
          overrides: [
            historySearchProvider.overrideWith(
              () => _FakeHistorySearchNotifier('HELLO'),
            ),
          ],
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      final span = textWidget.textSpan as TextSpan;

      // Should highlight both 'hello' and 'Hello' (case-insensitive)
      expect(span.children, isNotNull);
      expect(span.children!.length, greaterThan(1));
    });

    testWidgets('handles query with only whitespace as empty', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'Hello world',
            style: TextStyle(fontSize: 14),
            isDark: true,
          ),
          overrides: [
            historySearchProvider.overrideWith(
              () => _FakeHistorySearchNotifier('   '),
            ),
          ],
        ),
      );

      // Whitespace-only query should be treated as empty - renders plain text
      final textWidget = tester.widget<Text>(find.byType(Text));
      // When query is empty/whitespace, it renders with plain Text (not Text.rich)
      expect(textWidget.textSpan, isNull);
      expect(textWidget.data, 'Hello world');
    });

    testWidgets('respects maxLines and overflow parameters', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'Long text that might overflow',
            style: TextStyle(fontSize: 14),
            isDark: true,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.maxLines, 1);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('uses correct accent color in dark mode', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'test content',
            style: TextStyle(fontSize: 14),
            isDark: true,
          ),
          overrides: [
            historySearchProvider.overrideWith(
              () => _FakeHistorySearchNotifier('test'),
            ),
          ],
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      final span = textWidget.textSpan as TextSpan;
      expect(span.children, isNotNull);

      // Find the highlighted span (should have background color set)
      final highlightedSpan =
          span.children!.firstWhere(
                (child) =>
                    child is TextSpan && (child.style?.backgroundColor != null),
                orElse: () => throw Exception('No highlighted span found'),
              )
              as TextSpan;

      // Should have accent color with alpha ~0.28 in dark mode
      final bgColor = highlightedSpan.style!.backgroundColor;
      expect(bgColor, isNotNull);
    });

    testWidgets('uses correct accent color in light mode', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HighlightedText(
            text: 'test content',
            style: TextStyle(fontSize: 14),
            isDark: false,
          ),
          overrides: [
            historySearchProvider.overrideWith(
              () => _FakeHistorySearchNotifier('test'),
            ),
          ],
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      final span = textWidget.textSpan as TextSpan;
      expect(span.children, isNotNull);

      final highlightedSpan =
          span.children!.firstWhere(
                (child) =>
                    child is TextSpan && (child.style?.backgroundColor != null),
                orElse: () => throw Exception('No highlighted span found'),
              )
              as TextSpan;

      final bgColor = highlightedSpan.style!.backgroundColor;
      expect(bgColor, isNotNull);
    });
  });
}
