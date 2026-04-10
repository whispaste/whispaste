import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // computeFeedbackDeviceIdHash — pure unit tests
  // ───────────────────────────────────────────────────────────────────────
  group('computeFeedbackDeviceIdHash', () {
    test('always returns exactly 12 characters', () {
      expect(computeFeedbackDeviceIdHash('my-pc').length, 12);
      expect(computeFeedbackDeviceIdHash('').length, 12);
      expect(computeFeedbackDeviceIdHash('x' * 100).length, 12);
    });

    test('is deterministic', () {
      final a = computeFeedbackDeviceIdHash('test-host');
      final b = computeFeedbackDeviceIdHash('test-host');
      expect(a, equals(b));
    });

    test('produces only lowercase hex characters', () {
      final hash = computeFeedbackDeviceIdHash('my-computer');
      expect(hash, matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('different hostnames produce different hashes', () {
      final a = computeFeedbackDeviceIdHash('host-a');
      final b = computeFeedbackDeviceIdHash('host-b');
      expect(a, isNot(equals(b)));
    });

    test('fallback hostname used on error produces valid hash', () {
      // 'fallback_device' is the seed used by _deriveDeviceId when
      // Platform.localHostname throws — must produce a valid 12-char hash.
      final hash = computeFeedbackDeviceIdHash('fallback_device');
      expect(hash.length, 12);
      expect(hash, matches(RegExp(r'^[0-9a-f]{12}$')));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // FeedbackPage widget tests
  // ───────────────────────────────────────────────────────────────────────
  group('FeedbackPage widget', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(makeTestable(const FeedbackPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('submit button is disabled before inputs are filled',
        (tester) async {
      await tester.pumpWidget(makeTestable(const FeedbackPage()));
      await tester.pumpAndSettle();

      // "Send Feedback" comes from l10n.feedbackSubmit (app_en.arb).
      final submitFinder =
          find.widgetWithText(ElevatedButton, 'Send Feedback');
      expect(submitFinder, findsOneWidget);

      // No rating/category/comment yet → onPressed must be null.
      final button = tester.widget<ElevatedButton>(submitFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'submit button becomes enabled after all three inputs are filled',
        (tester) async {
      await tester.pumpWidget(makeTestable(const FeedbackPage()));
      await tester.pumpAndSettle();

      // Select the "General" category chip (l10n.feedbackCategoryGeneral).
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();

      // Tap the 🤩 emoji (rating = 5).
      await tester.tap(find.text('🤩'));
      await tester.pumpAndSettle();

      // Enter a comment so feedback_text is non-empty.
      await tester.enterText(find.byType(TextField), 'Great app!');
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Send Feedback'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'tapping submit when Supabase is not configured shows success state',
        (tester) async {
      // SUPABASE_URL is empty in tests (no --dart-define) → the "not
      // configured" branch runs, treating the submission as successful.
      await tester.pumpWidget(makeTestable(const FeedbackPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🤩'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Test feedback');
      await tester.pumpAndSettle();

      // The submit button may be below the fold — scroll it into view first.
      final submitFinder =
          find.widgetWithText(ElevatedButton, 'Send Feedback');
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      // Success state: _ThankYouView shows l10n.feedbackThankYou ("Thank you!")
      expect(find.text('Thank you!'), findsOneWidget);
    });
  });
}

