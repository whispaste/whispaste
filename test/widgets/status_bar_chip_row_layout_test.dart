/// Layout tests for the `WpStatusBar` chip row.
///
/// The row used to be start-anchored, deliberately, because a centred row
/// re-flows every chip sideways whenever one arrives or leaves. That decision
/// was reversed (see the comment on the content-area span in
/// `status_bar.dart`): the row is centred over the content column now, and the
/// jump the old comment objected to is answered by an `AnimatedSize` that
/// resolves the membership change as one damped ~200 ms reflow.
///
/// These tests pin the four properties that are easy to break silently while
/// refactoring the bar: the centring itself, the sidebar-width spacer the
/// chips align against, the damped (not instant) reflow, and the fact that no
/// chip sits in a reserved fixed-width slot. Horizontal scrolling in a narrow
/// window is covered too — centring is implemented *inside* the scroll
/// viewport, which is exactly where scrolling is easiest to break.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  Widget buildStatusBar({
    bool showAutoPasteOffHint = false,
    String? microphoneLabel,
    List<String>? microphoneOptions,
    String? hotkeyLabel,
    String? updateVersion,
    String? backendKind,
  }) {
    return makeTestable(
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          WpStatusBar(
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
    );
  }

  /// The chip group — the `AnimatedSize` that shrink-wraps the chip `Row`.
  /// Asserted unique so the geometry below can never silently measure some
  /// other animated box that a future refactor drops into this subtree.
  Rect groupRect(WidgetTester tester) {
    expect(find.byType(AnimatedSize), findsOneWidget);
    return tester.getRect(find.byType(AnimatedSize));
  }

  void setWindow(Size size) {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = size;
  }

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

  testWidgets('chip group is centred over the content column, not anchored to '
      'its start', (tester) async {
    await tester.pumpWidget(buildStatusBar(hotkeyLabel: 'Ctrl+Shift+D'));
    await tester.pump();

    final group = groupRect(tester);
    final barWidth = tester.getSize(find.byType(WpStatusBar)).width;

    // Centre of the content column — the window minus the sidebar spacer. The
    // symmetric gutter cancels out, so the expected centre is independent of
    // WpSpacing.xl.
    final contentCentre = (WpLayout.sidebarWidth + barWidth) / 2;
    expect(group.center.dx, moreOrLessEquals(contentCentre, epsilon: 0.5));

    // Guards against a regression to start alignment passing by accident: a
    // start-anchored group would sit at the gutter, far left of centre.
    expect(
      group.left,
      greaterThan(WpLayout.sidebarWidth + WpSpacing.xl + 1),
      reason: 'group must not be flush against the start gutter',
    );
  });

  testWidgets('sidebar-width spacer survives — the chip viewport starts at the '
      'content column, inset by the page gutter', (tester) async {
    await tester.pumpWidget(buildStatusBar());
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(
      viewport.left,
      moreOrLessEquals(WpLayout.sidebarWidth + WpSpacing.xl, epsilon: 0.01),
    );
  });

  testWidgets('a chip appearing reflows the group over ~200 ms instead of '
      'jumping to its new width', (tester) async {
    await tester.pumpWidget(buildStatusBar(showAutoPasteOffHint: false));
    await tester.pump();
    final before = groupRect(tester).width;

    await tester.pumpWidget(buildStatusBar(showAutoPasteOffHint: true));
    // First frame after the membership change: AnimatedSize has only just
    // learned the new child size, so the box itself has not moved yet.
    await tester.pump();
    expect(groupRect(tester).width, moreOrLessEquals(before, epsilon: 0.01));

    await tester.pump(const Duration(milliseconds: 100));
    final midway = groupRect(tester).width;

    await tester.pumpAndSettle();
    final settled = groupRect(tester).width;

    expect(
      settled,
      greaterThan(before),
      reason: 'the extra chip must widen the group',
    );
    expect(
      midway,
      greaterThan(before),
      reason: 'the reflow must have started by 100 ms',
    );
    expect(
      midway,
      lessThan(settled),
      reason:
          'the reflow must still be running at 100 ms — a jump would '
          'already be at its final width on the first frame',
    );
  });

  testWidgets('chip widths follow their content — no reserved fixed-width '
      'slots', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: 'Mic',
        microphoneOptions: const ['Mic', 'Other'],
      ),
    );
    await tester.pump();
    final withShortName = groupRect(tester).width;

    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: 'Studio Mic 42',
        microphoneOptions: const ['Studio Mic 42', 'Other'],
      ),
    );
    await tester.pumpAndSettle();
    final withLongerName = groupRect(tester).width;

    expect(
      withLongerName,
      greaterThan(withShortName),
      reason:
          'a longer device name must grow the group; equal widths would '
          'mean the chip sits in a reserved slot',
    );
  });

  testWidgets('wide window does not scroll — the centred group must not leave '
      'a phantom scroll extent', (tester) async {
    await tester.pumpWidget(buildStatusBar(hotkeyLabel: 'Ctrl+Shift+D'));
    await tester.pump();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, 0);
  });

  testWidgets('narrow window still scrolls horizontally with the row centred '
      'inside the viewport', (tester) async {
    setWindow(const Size(420, 800));
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

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'over-wide content must stay scrollable',
    );

    await tester.drag(find.byType(SingleChildScrollView), const Offset(-80, 0));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
  });
}
