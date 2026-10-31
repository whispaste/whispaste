/// UIA-FBK-03: the disabled send button says what is missing, as visible
/// text. The type and the message are required; rating and e-mail are not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

import '../../fixtures/test_helpers.dart';

FeedbackSubmissionService _service() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('', 201)),
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'test-key',
  breadcrumbSink: (_) {},
);

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(
        FeedbackPage(submissionService: _service()),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty form names the missing type as visible text', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(
      find.text(l10n.feedbackSubmitMissing(l10n.feedbackMissingCategory)),
      findsOneWidget,
    );
  });

  testWidgets('after a type, the hint asks for the message', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text(l10n.feedbackTypeProblem));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.feedbackSubmitMissing(l10n.feedbackMissingComment)),
      findsOneWidget,
    );
  });

  testWidgets('no hint once a type, a rating and a message are set', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text(l10n.feedbackTypeProblem));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('feedback-rating-3'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('feedbackCommentField')),
      'It stopped working',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('To send, please'), findsNothing);
  });

  testWidgets('without a rating, the hint asks for it', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text(l10n.feedbackTypeQuestion));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('feedbackCommentField')),
      'How does it work?',
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.feedbackSubmitMissing(l10n.feedbackMissingRating)),
      findsOneWidget,
    );
  });
}
