/// FB-03/FB-04/FB-05 on the form. The star rating is a required field: nothing
/// is sent without it. Praise and questions carry a neutral tag.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/feedback/feedback_type.dart';
import 'package:whispaste/services/feedback_diagnostics.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';
import 'package:whispaste/widgets/wp_row_checkbox.dart';
import 'package:whispaste/widgets/wp_voice_input_button.dart';

import '../../fixtures/test_helpers.dart';

const _block =
    '--- diagnostics ---\n'
    'App 9.9.9 · OS linux 6.8 · Engine whisper · Backend cuda';

class _PresetNotifier extends FeedbackPresetTypeNotifier {
  _PresetNotifier(this._value);
  final FeedbackType? _value;
  @override
  FeedbackType? build() => _value;
}

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

  Future<void> pump(WidgetTester tester, {FeedbackType? preset}) async {
    await tester.pumpWidget(
      makeTestable(
        FeedbackPage(submissionService: service()),
        locale: const Locale('en'),
        overrides: [
          feedbackPresetTypeProvider.overrideWith(
            () => _PresetNotifier(preset),
          ),
          feedbackDiagnosticBlockProvider.overrideWithValue(_block),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> rate(WidgetTester tester, int stars) async {
    final target = find.bySemanticsIdentifier('feedback-rating-$stars');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> typeMessage(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('feedbackCommentField')), text);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final finder = find.widgetWithText(WpButton, l10n.feedbackSubmit);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool sendEnabled(WidgetTester tester) {
    final finder = find.widgetWithText(WpButton, l10n.feedbackSubmit);
    return tester.widget<WpButton>(finder).onPressed != null;
  }

  TextField messageField(WidgetTester tester) => tester.widget<TextField>(
    find.descendant(
      of: find.byKey(const Key('feedbackCommentField')),
      matching: find.byType(TextField),
    ),
  );

  Finder blockPreview() =>
      find.byWidgetPredicate((w) => w is SelectableText && w.data == _block);

  group('star rating is required', () {
    testWidgets('without a rating nothing is sent and the hint names it', (
      tester,
    ) async {
      await pump(tester);
      await choose(tester, l10n.feedbackTypeQuestion);
      await typeMessage(tester, 'How does it work?');

      expect(sendEnabled(tester), isFalse);
      expect(
        find.text(l10n.feedbackSubmitMissing(l10n.feedbackMissingRating)),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(WpButton, l10n.feedbackSubmit),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
    });

    testWidgets('sending enables once a rating is chosen, and it is sent', (
      tester,
    ) async {
      await pump(tester);
      await choose(tester, l10n.feedbackTypeProblem);
      await typeMessage(tester, 'Rated');
      expect(sendEnabled(tester), isFalse);

      await rate(tester, 5);
      expect(sendEnabled(tester), isTrue);
      await submit(tester);

      expect(sent['rating'], 5);
    });

    testWidgets('the rating label is marked required', (tester) async {
      await pump(tester);
      await choose(tester, l10n.feedbackTypeProblem);
      expect(find.text(l10n.feedbackRequiredMarker), findsOneWidget);
    });
  });

  for (final (id, category) in [
    ('problem', 'bug'),
    ('idea', 'feature'),
    ('praise', 'general'),
    ('question', 'general'),
  ]) {
    testWidgets('type $id is a testable chip and sends category $category', (
      tester,
    ) async {
      await pump(tester);
      expect(find.bySemanticsIdentifier('feedback-type-$id'), findsOneWidget);

      final label = switch (id) {
        'problem' => l10n.feedbackTypeProblem,
        'idea' => l10n.feedbackTypeIdea,
        'praise' => l10n.feedbackTypePraise,
        _ => l10n.feedbackTypeQuestion,
      };
      await choose(tester, label);
      await rate(tester, 4);
      await typeMessage(tester, 'Message for $id');
      await submit(tester);

      expect(sent['category'], category);
      expect(sent['rating'], 4);
    });
  }

  testWidgets('praise is tagged [praise] and sent as category general', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypePraise);
    await rate(tester, 5);
    await typeMessage(tester, 'Works well');
    await submit(tester);
    expect(sent['feedback_text'], '[praise] Works well');
    expect(sent['category'], 'general');
  });

  testWidgets('a question is tagged [question]', (tester) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeQuestion);
    await rate(tester, 3);
    await typeMessage(tester, 'How?');
    await submit(tester);
    expect(sent['feedback_text'], '[question] How?');
  });

  testWidgets('problems and ideas carry no tag', (tester) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeIdea);
    await rate(tester, 3);
    await typeMessage(tester, 'Dark mode');
    await submit(tester);
    expect(sent['feedback_text'], 'Dark mode');
  });

  testWidgets('diagnostics are off by default and nothing is appended', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);

    expect(blockPreview(), findsNothing);
    expect(find.text(l10n.feedbackDiagnosticsPreview), findsNothing);
    await rate(tester, 3);
    await typeMessage(tester, 'Plain');
    await submit(tester);

    expect(sent['feedback_text'], 'Plain');
  });

  testWidgets('opt-in preview shows the exact block and it is sent', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);
    await tester.ensureVisible(find.byType(WpRowCheckbox));
    await tester.tap(find.byType(WpRowCheckbox));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.feedbackDiagnosticsPreview));
    await tester.pumpAndSettle();
    expect(blockPreview(), findsOneWidget);

    await rate(tester, 3);
    await typeMessage(tester, 'With block');
    await submit(tester);
    expect(sent['feedback_text'], 'With block\n\n$_block');
  });

  testWidgets('the message field honours the tag and the attached block', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypePraise);
    await tester.ensureVisible(find.byType(WpRowCheckbox));
    await tester.tap(find.byType(WpRowCheckbox));
    await tester.pumpAndSettle();

    expect(
      messageField(tester).maxLength,
      kFeedbackTextMaxLength - '[praise] '.length - _block.length - 2,
    );
  });

  testWidgets('the dictation button sits in the message field and inserts at '
      'the caret', (tester) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);
    await typeMessage(tester, 'Hello world');

    final button = find.bySemanticsIdentifier('feedback-dictate-button');
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('feedbackCommentField')),
        matching: find.byType(WpVoiceInputButton),
      ),
      findsOneWidget,
    );

    tester
        .widget<WpVoiceInputButton>(
          find.descendant(
            of: button,
            matching: find.byType(WpVoiceInputButton),
          ),
        )
        .onTranscript('dictated');
    await tester.pumpAndSettle();

    expect(messageField(tester).controller!.text, contains('dictated'));
  });

  testWidgets('the idea type shows the ideas board link, other types do not', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);
    expect(
      find.bySemanticsIdentifier('feedback-idea-board-link'),
      findsNothing,
    );

    await choose(tester, l10n.feedbackTypeIdea);
    expect(
      find.bySemanticsIdentifier('feedback-idea-board-link'),
      findsOneWidget,
    );
    expect(find.text(l10n.feedbackIdeaBoardHint), findsOneWidget);
  });

  testWidgets('the idea entry point preselects the idea type', (tester) async {
    await pump(tester, preset: FeedbackType.idea);
    final chip = tester.widget<WpFilterChip>(
      find.descendant(
        of: find.bySemanticsIdentifier('feedback-type-idea'),
        matching: find.byType(WpFilterChip),
      ),
    );
    expect(chip.isActive, isTrue);
  });
}
