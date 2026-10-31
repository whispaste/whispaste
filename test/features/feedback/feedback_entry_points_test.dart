// Entry points of the feedback form (FB-02): every entry opens the same form,
// and "Idee vorschlagen…" opens it with the Idea type already chosen.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/feedback/feedback_type.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/app_menu_bar.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../../fixtures/test_helpers.dart';

late L10n en;

/// A preset that is already in place when the form opens.
class _PresetNotifier extends FeedbackPresetTypeNotifier {
  _PresetNotifier(this._type);
  final FeedbackType? _type;

  @override
  FeedbackType? build() => _type;
}

FeedbackSubmissionService _service() => FeedbackSubmissionService(
  client: MockClient((_) async => throw UnimplementedError()),
  supabaseUrl: '',
  supabasePublishableKey: '',
  breadcrumbSink: (_) {},
);

void main() {
  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('the tray offers Send feedback right after Settings', () {
    final commands = buildTrayCommands(
      const TrayMenuState(
        isRecording: false,
        micDeviceLabels: [],
        selectedMic: '',
      ),
      trayLabelsFor(en),
    );
    final ids = [
      for (final c in commands)
        if (!c.isSeparator) c.id,
    ];
    final at = ids.indexOf(TrayCommandIds.feedback);
    expect(at, isNot(-1));
    expect(ids[at - 1], TrayCommandIds.settings);
    final feedback = commands.firstWhere(
      (c) => c.id == TrayCommandIds.feedback,
    );
    expect(trayLabelsFor(en)[feedback.labelKey], en.trayFeedback);
  });

  test('each form type maps to one server category', () {
    expect(feedbackCategoryFor(FeedbackType.problem), 'bug');
    expect(feedbackCategoryFor(FeedbackType.idea), 'feature');
    expect(feedbackCategoryFor(FeedbackType.praise), 'general');
    expect(feedbackCategoryFor(FeedbackType.question), 'general');
  });

  testWidgets('Idea from the menu bar opens the form with the Idea type set', (
    tester,
  ) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [windowActivatorProvider.overrideWithValue(() async {})],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );

    await runMenuBarCommand(ref, WpMenuBarCommandIds.helpIdea);
    expect(ref.read(activePageProvider), 'feedback');
    expect(ref.read(feedbackPresetTypeProvider), FeedbackType.idea);

    await runMenuBarCommand(ref, WpMenuBarCommandIds.helpFeedback);
    expect(ref.read(activePageProvider), 'feedback');
    expect(ref.read(feedbackPresetTypeProvider), isNull);
  });

  testWidgets('the form starts with the preset type chosen', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        FeedbackPage(submissionService: _service()),
        locale: const Locale('en'),
        overrides: [
          feedbackPresetTypeProvider.overrideWith(
            () => _PresetNotifier(FeedbackType.idea),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final idea = find.byWidgetPredicate(
      (w) => w is WpFilterChip && w.label == en.feedbackTypeIdea,
    );
    expect(tester.widget<WpFilterChip>(idea).isActive, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plain open starts without a preselected type', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        FeedbackPage(submissionService: _service()),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byWidgetPredicate(
      (w) => w is WpFilterChip && w.isActive,
    );
    expect(active, findsNothing);
  });
}
