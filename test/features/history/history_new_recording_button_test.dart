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
/// **It cannot cut someone else's recording short.** The button is a second
/// trigger for `RecordingOrchestrator.toggleRecording`, the very method the
/// systemwide hotkey calls — which is what makes it honest (identical
/// pipeline, identical clipboard/notification behaviour) and also what makes
/// it dangerous: *toggle* means a click during a running recording would stop
/// a recording that was started from a completely different window. So the
/// button only acts while the pipeline is idle. That is a behavioural
/// contract, not styling, hence a test rather than a comment.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../../fixtures/test_helpers.dart';

void main() {
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
            isDark: true,
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
        overrides: [recordingPhaseProvider.overrideWithValue(phase)],
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

  for (final phase in const [
    RecordingPhase.recording,
    RecordingPhase.transcribing,
  ]) {
    testWidgets(
      'a $phase started anywhere else cannot be cut short from here',
      (tester) async {
        final button = await pumpBar(tester, phase);
        expect(
          button.onPressed == null || button.isLoading,
          isTrue,
          reason:
              'toggleRecording() toggles, so a pressable button during $phase '
              'would let a click on the History page stop a recording somebody '
              'started with the systemwide hotkey in another app',
        );
        expect(
          button.disabledTooltip,
          isNotNull,
          reason:
              'a button that stops responding without saying why reads as '
              'broken — the running phase is the explanation',
        );
      },
    );
  }
}
