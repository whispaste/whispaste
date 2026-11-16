/// UIA-FBK-03: the disabled send button says what is missing, as visible
/// text. Only the message is required (#998); type, rating and e-mail are
/// optional.
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
  client: MockClient((_) async => http.Response('', 202)),
  baseUrl: 'https://api.example.test',
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

  testWidgets('an empty form names the missing message as visible text', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(
      find.text(l10n.feedbackSubmitMissing(l10n.feedbackMissingComment)),
      findsOneWidget,
    );
  });

  testWidgets('a too short message names the minimum length', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('feedbackCommentField')), 'Hi');
    await tester.pumpAndSettle();

    expect(
      find.text(
        l10n.feedbackSubmitMissing(
          l10n.contactMessageTooShort(kContactMessageMinLength),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no hint once the message is long enough, without type or '
      'rating', (tester) async {
    await pumpPage(tester);
    await tester.enterText(
      find.byKey(const Key('feedbackCommentField')),
      'It stopped working',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('To send, please'), findsNothing);
  });
}
