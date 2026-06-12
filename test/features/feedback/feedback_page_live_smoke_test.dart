/// Live-smoke test: drives the real [FeedbackPage] UI against the real
/// Supabase backend — fill form, tap submit, expect the thank-you screen.
///
/// Auto-skipped unless both dart-defines are present:
///
///   flutter test test/features/feedback/feedback_page_live_smoke_test.dart \
///     --dart-define=SUPABASE_URL=`https://<project>.supabase.co` \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_…
///
/// The submitted row is tagged `E2E-TEST` in `feedback_text` so it can be
/// identified and deleted afterwards (server-side moderation defaults keep
/// it out of `public_testimonials` regardless). Mirrors the env-gated
/// pattern of the Deepgram live-smoke test.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

import '../../fixtures/test_helpers.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('FeedbackPage (live-smoke)', () {
    testWidgets('live: full UI submit reaches Supabase and shows thank-you', (
      tester,
    ) async {
      if (_url.isEmpty || _key.isEmpty) {
        // Skip gracefully without dart-defines.
        return;
      }

      // TestWidgetsFlutterBinding installs a mock HttpClient that answers
      // every request with HTTP 400 — restore real networking for this test.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});

      final service = FeedbackSubmissionService(
        client: http.Client(),
        supabaseUrl: _url,
        supabasePublishableKey: _key,
        breadcrumbSink: (_) {},
        messageSink: (_, _, _) {},
      );

      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: service),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Fill the form through the real UI.
      await tester.tap(find.text(l10n.feedbackCategoryGeneral));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🤩'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'E2E-TEST live-smoke (automated) — bitte ignorieren, wird gelöscht',
      );
      await tester.pumpAndSettle();

      final submitFinder = find.widgetWithText(
        ElevatedButton,
        l10n.feedbackSubmit,
      );
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();

      // The tap — and therefore the real http.post and its timeout timer —
      // must run inside runAsync: outside of it the widget test's fake-async
      // zone never completes real I/O.
      await tester.runAsync(() async {
        await tester.tap(submitFinder);
        await Future<void>.delayed(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.feedbackThankYou),
        findsOneWidget,
        reason:
            'Live submit must reach Supabase (HTTP 2xx) and flip the page '
            'into the thank-you state within 5 s',
      );
    });
  });
}
