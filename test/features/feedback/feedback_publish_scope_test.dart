/// Which feedback may be quoted on the website (decision 24, CONTEXT 6.7a).
///
/// Only praise is written like a rating, so only praise offers the quote
/// consent. Problems (bug reports) and ideas (feature wishes) are never
/// published, and a consent ticked for praise does not survive a switch to
/// another type.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_diagnostics.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

const _block =
    '--- diagnostics ---\n'
    'App 9.9.9 · OS linux 6.8 · Engine whisper · Backend cuda';

void main() {
  late L10n l10n;
  late Map<String, Object?> sent;
  late int requests;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = {};
    requests = 0;
  });

  FeedbackSubmissionService service() => FeedbackSubmissionService(
    client: MockClient((req) async {
      requests++;
      sent = (jsonDecode(req.body) as Map).cast<String, Object?>();
      return http.Response('', 201);
    }),
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'test-key',
    breadcrumbSink: (_) {},
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(
        FeedbackPage(submissionService: service()),
        locale: const Locale('en'),
        overrides: [feedbackDiagnosticBlockProvider.overrideWithValue(_block)],
      ),
    );
    await tester.pumpAndSettle();
  }

  // The type chips scroll out of view once the form is scrolled down, so each
  // choice brings its chip on screen first.
  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> rate(WidgetTester tester, int stars) async {
    final target = find.bySemanticsIdentifier('feedback-rating-$stars');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final finder = find.widgetWithText(WpButton, l10n.feedbackSubmit);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder consentBox() => find.byKey(const Key('feedbackPublishConsent'));

  Future<void> tapConsent(WidgetTester tester) async {
    await tester.ensureVisible(consentBox());
    await tester.pumpAndSettle();
    await tester.tap(consentBox());
    await tester.pumpAndSettle();
  }

  testWidgets('the quote consent is offered for praise only', (tester) async {
    await pump(tester);

    await choose(tester, l10n.feedbackTypePraise);
    expect(consentBox(), findsOneWidget);
    expect(find.text(l10n.feedbackPublishReviewHint), findsOneWidget);

    for (final label in [
      l10n.feedbackTypeProblem,
      l10n.feedbackTypeIdea,
      l10n.feedbackTypeQuestion,
    ]) {
      await choose(tester, label);
      expect(consentBox(), findsNothing, reason: '$label must not offer it');
    }
  });

  testWidgets('a consent ticked for praise is not sent after a switch', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypePraise);
    await rate(tester, 5);
    await tester.enterText(
      find.byKey(const Key('feedbackCommentField')),
      'Works well',
    );
    await tester.pumpAndSettle();
    await tapConsent(tester);

    await choose(tester, l10n.feedbackTypeProblem);
    await submit(tester);

    expect(requests, 1);
    expect(sent['publish_consent'], isFalse);
    expect(sent.containsKey('withdraw_token_hash'), isFalse);
    expect(sent['category'], 'bug');
  });
}
