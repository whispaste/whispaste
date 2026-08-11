/// The "new recording" button in History's search bar.
///
/// Two things are worth pinning about it, and neither is its looks.
///
/// **It is the same row every other list screen has.** Notes offers "new
/// note" beside its search field, Replacements and Snippets offer "Add";
/// History — the screen the app opens on — offered nothing, so the one action
/// that puts an entry *into* the list was the only one with no button
/// anywhere. The geometry guard in
/// `test/widgets/search_field_geometry_consistency_test.dart` already pins the
/// row's measurements (field up to `WpSpacing.sm` short of the button); what
/// is pinned here is that the button exists and carries History's own wording.
///
/// **It also stops the recording it started.** The button is a second trigger
/// for `RecordingOrchestrator.toggleRecording`, the very method the systemwide
/// hotkey calls — identical pipeline, identical clipboard/notification
/// behaviour — and that method already toggles. Greying the button out during
/// a recording therefore suppressed a capability it was handing over for
/// free, and left someone who had switched the recording overlay off with no
/// way back: they started the recording here and could not end it here. So
/// the button stays live and swaps what it offers, in
/// [WpVoiceInputButton]'s vocabulary (mic → filled square, accent → danger).
///
/// Transcribing is the single disabled state, and only because
/// `toggleRecording` is a documented no-op once the audio is in the pipeline.
///
/// All of that is behaviour rather than styling, hence a test rather than a
/// comment.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../../fixtures/test_helpers.dart';

/// Counts `toggleRecording()` calls without starting anything real: `build()`
/// is overridden to a no-op, so no state machine, audio service or STT engine
/// is wired up by mounting it.
class _FakeOrchestrator extends RecordingOrchestrator {
  int toggles = 0;

  @override
  void build() {}

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
  }) async => toggles++;
}

void main() {
  late _FakeOrchestrator orchestrator;

  setUp(() => orchestrator = _FakeOrchestrator());

  Future<WpButton> pumpBar(WidgetTester tester, RecordingPhase phase) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.topCenter,
          child: HistorySearchFilterBar(
            controller: controller,
            activeFilter: HistoryFilter.all,
            onFilterChanged: (_) {},
            onSearchChanged: () {},
            resultCount: 0,
            viewMode: HistoryViewMode.list,
            onViewModeChanged: (_) {},
            multiSelectMode: false,
            onToggleMultiSelect: () {},
            sortOrder: HistorySortOrder.newest,
            onSortOrderChanged: (_) {},
          ),
        ),
        // Overridden rather than driven through the real notifier: this test
        // is about what the button does with a phase, not about how the phase
        // gets there, and instantiating the orchestrator would start real
        // services.
        overrides: [
          recordingPhaseProvider.overrideWithValue(phase),
          recordingOrchestratorProvider.overrideWith(() => orchestrator),
        ],
        // Pinned so the label assertion below compares against a known
        // locale rather than whatever the host machine runs.
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    return tester.widget<WpButton>(find.byType(WpButton).first);
  }

  testWidgets('History offers the same primary action its sibling list screens '
      'do, in the same place', (tester) async {
    final button = await pumpBar(tester, RecordingPhase.idle);
    final l10n = lookupL10n(const Locale('en'));

    expect(
      button.label,
      l10n.historyNewRecording,
      reason:
          'the button must name what History collects — recordings — rather '
          'than borrowing the search field\'s "transcriptions" wording',
    );
    expect(
      button.variant,
      WpButtonVariant.primary,
      reason: 'same hierarchy as Notes\' "new note" and the Add buttons',
    );
    expect(
      button.icon,
      isNotNull,
      reason:
          'the microphone glyph is what makes the action readable at a '
          'glance next to a search field',
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'while nothing is recording the button has to be pressable',
    );

    // The row itself: the field is the flexible half, the button the fixed
    // one. Their order is what makes History read like Notes.
    final field = tester.getRect(find.byType(WpSearchField));
    final buttonRect = tester.getRect(find.byType(WpButton).first);
    expect(
      buttonRect.left,
      greaterThan(field.right - 1),
      reason: 'the button belongs after the field, not before or under it',
    );
  });

  testWidgets('while a recording runs the button offers to stop it, and does', (
    tester,
  ) async {
    final button = await pumpBar(tester, RecordingPhase.recording);
    final l10n = lookupL10n(const Locale('en'));

    expect(
      button.onPressed,
      isNotNull,
      reason:
          'greying out here would strand anyone who runs without the '
          'recording overlay: they started the recording from this button '
          'and would have no way to end it',
    );
    expect(
      button.label,
      l10n.historyStopRecording,
      reason: 'the button must say what pressing it now does, not what it did',
    );
    expect(
      button.icon,
      LucideIcons.square,
      reason:
          'same glyph WpVoiceInputButton uses for a running recording — one '
          'stop symbol in the app, not two',
    );
    expect(
      button.tone,
      WpButtonTone.danger,
      reason:
          'same red WpVoiceInputButton turns while recording; the tone is '
          'what makes the state readable before the label is read',
    );

    await tester.tap(find.byType(WpButton).first);
    await tester.pump();
    expect(
      orchestrator.toggles,
      1,
      reason:
          'the press has to reach toggleRecording(), which stops the '
          'recording — the same method, and therefore the same teardown, the '
          'hotkey and the overlay use',
    );
  });

  testWidgets('while the transcription runs there is nothing left to stop', (
    tester,
  ) async {
    final button = await pumpBar(tester, RecordingPhase.transcribing);

    expect(
      button.isLoading,
      isTrue,
      reason: 'the pipeline is working; the button says so',
    );
    expect(
      button.onPressed,
      isNull,
      reason:
          'toggleRecording() is a documented no-op during transcription, so a '
          'live button would promise something it cannot do',
    );
    expect(
      button.disabledTooltip,
      isNotNull,
      reason:
          'a button that stops responding without saying why reads as broken '
          '— the running phase is the explanation',
    );
  });

  for (final phase in const [RecordingPhase.done, RecordingPhase.error]) {
    testWidgets('a lingering $phase does not lock the button', (tester) async {
      final button = await pumpBar(tester, phase);
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'startRecording() preempts a lingering done/error status itself, '
            'so the button must not be the thing that blocks the next '
            'recording',
      );
      expect(button.icon, LucideIcons.mic);
    });
  }
}
