/// The primary dictate button in the dock shows a focus ring for keyboard
/// focus, and only for keyboard focus (WP-50 follow-up).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';

import '../fixtures/test_helpers.dart';
import '../fixtures/dock_choice_fixtures.dart';

const _dictateKey = ValueKey('dock-dictate');

// The ring paints on the WpFocusRing around the button, i.e. an ancestor of
// the InkWell that carries the key.
Finder _ringOnDictate() => find.ancestor(
  of: find.byKey(_dictateKey),
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.foregroundPainter is WpFocusRingPainter,
  ),
);

Widget _dock() => makeTestable(
  Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      width: 1000,
      child: WpRecordingDock(
        sttModeLabel: 'whisper-small',
        sttState: SttServerState.ready,
        smartMode: dockTestSmartMode(label: 'Smart Mode · Aus'),
        hotkeyLabel: 'Ctrl+Shift+D',
        microphoneLabel: 'Built-in',
        microphoneOptions: const ['Built-in'],
        onMicrophoneChanged: (_) {},
        language: dockTestLanguage(label: 'DE'),
      ),
    ),
  ),
);

void main() {
  setUp(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch,
  );
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  testWidgets('no ring without focus', (tester) async {
    await tester.pumpWidget(_dock());
    expect(_ringOnDictate(), findsNothing);
  });

  testWidgets('keyboard focus shows the ring around the dictate button', (
    tester,
  ) async {
    await tester.pumpWidget(_dock());
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final inkWell = tester.widget<InkWell>(find.byKey(_dictateKey));
    inkWell.focusNode!.requestFocus();
    await tester.pump();
    expect(_ringOnDictate(), findsOneWidget);
  });

  testWidgets('pointer focus (touch highlight mode) shows no ring', (
    tester,
  ) async {
    await tester.pumpWidget(_dock());
    final inkWell = tester.widget<InkWell>(find.byKey(_dictateKey));
    inkWell.focusNode!.requestFocus();
    await tester.pump();
    expect(_ringOnDictate(), findsNothing);
  });

  // UIA-R-FND-011: the ring sits outside the dictate fill, so its contrast is
  // measured against the dock surface it stands on (WCAG 1.4.11, 3:1).
  testWidgets('Tab reaches the dictate button and its ring keeps 3:1 against '
      'the dock surface (UIA-R-FND-011)', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpWidget(_dock());
    await tester.pump();

    final dictateFocus = tester
        .widget<InkWell>(find.byKey(_dictateKey))
        .focusNode;
    var reached = false;
    for (var i = 0; i < 25 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reached = FocusManager.instance.primaryFocus == dictateFocus;
    }
    expect(reached, isTrue, reason: 'Tab never reached the dictate button');
    expect(_ringOnDictate(), findsOneWidget);

    final ring = tester
        .widget<WpFocusRing>(
          find.ancestor(
            of: find.byKey(_dictateKey),
            matching: find.byType(WpFocusRing),
          ),
        )
        .ringColor;
    expect(ring, isNotNull);
    for (final surface in [wpStagePalette.canvas, wpStagePalette.pane]) {
      expect(
        contrastRatio(ring!, surface),
        greaterThanOrEqualTo(3.0),
        reason: 'focus ring must contrast with the dock surface',
      );
    }
  });
}
