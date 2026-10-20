/// Layout tests for the `WpRecordingDock` row.
///
/// The dock lays its groups out from the start edge (dictate, status, then the
/// selectors) and the status and selector groups take the width the row
/// leaves. Optional entries (hints, updates, automation API) live in the Mehr
/// menu, so showing or hiding them never moves the groups. These tests pin the
/// properties that are easy to break silently while refactoring the dock:
/// start-anchored order, no reserved fixed-width slot per selector, no
/// scrolling, and the minimum-width behaviour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';

void main() {
  // The dark default paints a 1 dp rim on the dock, which shifts the group by
  // one pixel. This layout test pins the light appearance it was written for.
  setUp(() => WpColors.activate(wpLightColors));

  Widget buildStatusBar({
    bool showAutoPasteOffHint = false,
    String? microphoneLabel,
    List<String>? microphoneOptions,
    String? hotkeyLabel,
    String? updateVersion,
    String? backendKind,
    bool disableAnimations = false,
  }) {
    return makeTestable(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              WpRecordingDock(
                sttModeLabel: 'On device',
                sttState: SttServerState.ready,
                showAutoPasteOffHint: showAutoPasteOffHint,
                microphoneLabel: microphoneLabel,
                microphoneOptions: microphoneOptions,
                onMicrophoneChanged: microphoneOptions != null ? (_) {} : null,
                hotkeyLabel: hotkeyLabel,
                updateVersion: updateVersion,
                backendKind: backendKind,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void setWindow(Size size) {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = size;
  }

  // Measure with the bundled fonts, as the goldens and the shell tests do.
  setUpAll(loadAppFonts);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    setWindow(const Size(1280, 800));
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetDevicePixelRatio();
    view.resetPhysicalSize();
  });

  testWidgets('the status group follows the dictate button, never over it', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(hotkeyLabel: 'Ctrl+Shift+D', updateVersion: '9.9.9'),
    );
    await tester.pump();

    final status = tester.getRect(find.byKey(const ValueKey('dock-status')));
    final dictate = tester.getRect(find.byKey(const ValueKey('dock-dictate')));
    expect(
      status.left,
      greaterThan(dictate.right),
      reason: 'the status comes after the dictate button, never over it',
    );
  });

  testWidgets('the groups start at the dock gutter, not the sidebar', (
    tester,
  ) async {
    await tester.pumpWidget(buildStatusBar(updateVersion: '9.9.9'));
    await tester.pump();

    final dock = tester.getRect(find.byKey(const ValueKey('dock-surface')));
    final dictate = tester.getRect(find.byKey(const ValueKey('dock-dictate')));
    expect(
      dictate.left,
      moreOrLessEquals(dock.left + WpSpacing.md, epsilon: 0.01),
    );
  });

  testWidgets('a hint appearing in Mehr does not move the groups', (
    tester,
  ) async {
    await tester.pumpWidget(buildStatusBar(showAutoPasteOffHint: false));
    await tester.pump();
    final status = tester.getRect(find.byKey(const ValueKey('dock-status')));
    final dictate = tester.getRect(find.byKey(const ValueKey('dock-dictate')));

    await tester.pumpWidget(
      buildStatusBar(showAutoPasteOffHint: true, updateVersion: '9.9.9'),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const ValueKey('dock-status'))),
      status,
      reason: 'the status group keeps its place and width',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('dock-dictate'))),
      dictate,
      reason: 'the dictate button keeps its place and width',
    );
  });

  testWidgets('selector widths follow their content — no reserved fixed-width '
      'slots', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: 'Mic',
        microphoneOptions: const ['Mic', 'Other'],
      ),
    );
    await tester.pump();
    final withShortName = tester
        .getSize(find.byKey(const ValueKey('dock-microphone')))
        .width;

    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: 'Studio Mic 42',
        microphoneOptions: const ['Studio Mic 42', 'Other'],
      ),
    );
    await tester.pumpAndSettle();
    final withLongerName = tester
        .getSize(find.byKey(const ValueKey('dock-microphone')))
        .width;

    expect(
      withLongerName,
      greaterThan(withShortName),
      reason:
          'a longer device name must grow the selector; equal widths would '
          'mean it sits in a reserved slot',
    );
  });

  testWidgets('the dock never scrolls', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(hotkeyLabel: 'Ctrl+Shift+D', updateVersion: '9.9.9'),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dock-surface')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
  });

  testWidgets('a narrow window keeps the groups whole inside the dock', (
    tester,
  ) async {
    // 800 px is the minimum window width: the groups must stay whole there.
    setWindow(const Size(800, 800));
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: 'Studio Mic 42',
        microphoneOptions: const ['Studio Mic 42', 'Other'],
        showAutoPasteOffHint: true,
        hotkeyLabel: 'Ctrl+Shift+D',
        updateVersion: '9.9.9',
      ),
    );
    await tester.pump();

    final dock = tester.getRect(find.byKey(const ValueKey('dock-surface')));
    for (final key in ['dock-dictate', 'dock-status']) {
      final group = tester.getRect(find.byKey(ValueKey(key)));
      expect(group.right, lessThanOrEqualTo(dock.right));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a chip appearing under reduced motion (disableAnimations) does not '
    'crash RenderAnimatedSize',
    (tester) async {
      // Regression: WpMotion.durationFor resolves to Duration.zero under
      // disableAnimations, and a bare AnimatedSize restarts its controller
      // synchronously from inside its own performLayout when that duration
      // is zero — a hard Flutter assertion. golden_screenshot's DeviceBox
      // sets disableAnimations: true unconditionally, so every store
      // screenshot tripped this. See WpAnimatedSize in tokens.dart for the
      // fix (bypasses AnimatedSize entirely once the duration is zero) and
      // test/core/theme/motion_test.dart's former repro group for the
      // isolated reproduction that pinned the root cause.
      await tester.pumpWidget(
        buildStatusBar(showAutoPasteOffHint: false, disableAnimations: true),
      );
      await tester.pump();

      await tester.pumpWidget(
        buildStatusBar(showAutoPasteOffHint: true, disableAnimations: true),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
