/// FB-03/FB-04/FB-05 on the form (#998): category and star rating are
/// optional, the category travels as `kind` to /v1/contact, the text carries
/// no tag, and diagnostics only leave the app when attached.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/widgets/wp_consent_checkbox.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/feedback/feedback_type.dart';
import 'package:whispaste/services/feedback_diagnostics.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';
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
  late int logReads;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = {};
    requests = 0;
    logReads = 0;
  });

  FeedbackSubmissionService service() => FeedbackSubmissionService(
    client: MockClient((req) async {
      requests++;
      sent = (jsonDecode(req.body) as Map).cast<String, Object?>();
      return http.Response('', 202);
    }),
    baseUrl: 'https://api.example.test',
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
          feedbackDiagnosticAttachmentProvider.overrideWith((ref) {
            logReads++;
            return '$_block\n--- recent logs ---\nline';
          }),
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
    final finder = find.byKey(const ValueKey('contact-form-submit'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool sendEnabled(WidgetTester tester) {
    final finder = find.byKey(const ValueKey('contact-form-submit'));
    return tester
            .widget<WpButton>(
              find.ancestor(of: finder, matching: find.byType(WpButton)),
            )
            .onPressed !=
        null;
  }

  TextField messageField(WidgetTester tester) => tester.widget<TextField>(
    find.descendant(
      of: find.byKey(const Key('feedbackCommentField')),
      matching: find.byType(TextField),
    ),
  );

  Finder blockPreview() => find.byWidgetPredicate(
    (w) => w is SelectableText && (w.data?.startsWith(_block) ?? false),
  );

  group('rating and category are optional', () {
    testWidgets('a message alone is sent, as kind other and without rating', (
      tester,
    ) async {
      await pump(tester);
      await typeMessage(tester, 'How does it work?');

      expect(sendEnabled(tester), isTrue);
      await submit(tester);

      expect(requests, 1);
      expect(sent['kind'], 'other');
      expect(sent['message'], 'How does it work?');
      expect(sent['rating'], isNull);
    });

    testWidgets('a chosen rating is sent', (tester) async {
      await pump(tester);
      await choose(tester, l10n.feedbackTypeProblem);
      await typeMessage(tester, 'Rated message');
      await rate(tester, 5);
      await submit(tester);

      expect(sent['rating'], 5);
    });

    testWidgets('the rating label is marked optional', (tester) async {
      await pump(tester);
      expect(find.text(l10n.feedbackOptionalMarker), findsWidgets);
    });

    testWidgets('no category is preselected', (tester) async {
      await pump(tester);
      for (final type in FeedbackType.values) {
        final chip = tester.widget<WpFilterChip>(
          find.descendant(
            of: find.bySemanticsIdentifier('feedback-type-${type.name}'),
            matching: find.byType(WpFilterChip),
          ),
        );
        expect(chip.isActive, isFalse, reason: type.name);
      }
    });
  });

  for (final type in FeedbackType.values) {
    testWidgets('type ${type.name} is a testable chip and sent as its kind', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.bySemanticsIdentifier('feedback-type-${type.name}'),
        findsOneWidget,
      );

      final label = switch (type) {
        FeedbackType.problem => l10n.feedbackTypeProblem,
        FeedbackType.idea => l10n.feedbackTypeIdea,
        FeedbackType.praise => l10n.feedbackTypePraise,
        FeedbackType.question => l10n.feedbackTypeQuestion,
        FeedbackType.other => l10n.feedbackTypeOther,
      };
      await choose(tester, label);
      await rate(tester, 4);
      await typeMessage(tester, 'Message for ${type.name}');
      await submit(tester);

      expect(sent['kind'], type.name);
      expect(sent['source'], 'app');
      expect(sent['rating'], 4);
      // The type travels as kind: the text carries no tag.
      expect(sent['message'], 'Message for ${type.name}');
    });
  }

  testWidgets('diagnostics are off by default and nothing is appended', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);

    expect(blockPreview(), findsNothing);
    expect(find.text(l10n.feedbackDiagnosticsPreview), findsNothing);
    await typeMessage(tester, 'Plain message');
    await submit(tester);

    expect(sent['message'], 'Plain message');
    expect(sent.containsKey('appVersion'), isFalse);
    expect(sent.containsKey('os'), isFalse);
    expect(sent.containsKey('diagnostics'), isFalse);
    // Without the tick no log file is even read.
    expect(logReads, 0);
  });

  testWidgets('opt-in preview shows the exact block and it is sent', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);
    await tester.ensureVisible(
      find.byKey(const Key('feedback-diagnostics-attach')),
    );
    await tester.tap(find.byKey(const Key('feedback-diagnostics-attach')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.feedbackDiagnosticsPreview));
    await tester.pumpAndSettle();
    expect(blockPreview(), findsOneWidget);

    await typeMessage(tester, 'With block');
    await submit(tester);
    expect(sent['message'], 'With block\n\n$_block');
    expect(sent['diagnostics'], '$_block\n--- recent logs ---\nline');
    expect(sent['appVersion'], isNotNull);
    expect(logReads, greaterThan(0));
  });

  testWidgets('the diagnostics choice is the shared consent checkbox with '
      'its focus ring (#1845)', (tester) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypeProblem);
    expect(
      tester.widget(find.byKey(const Key('feedback-diagnostics-attach'))),
      isA<WpConsentCheckbox>(),
    );
  });

  testWidgets('the message field honours the attached block', (tester) async {
    await pump(tester);
    await choose(tester, l10n.feedbackTypePraise);
    await tester.ensureVisible(
      find.byKey(const Key('feedback-diagnostics-attach')),
    );
    await tester.tap(find.byKey(const Key('feedback-diagnostics-attach')));
    await tester.pumpAndSettle();

    expect(
      messageField(tester).maxLength,
      kContactMessageMaxLength - _block.length - 2,
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
