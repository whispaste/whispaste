/// Widget tests for the Automation API entry in the dock's Mehr menu.
///
/// The entry is absent while
/// [WpRecordingDock.automationApiRunState] is `null` or `stopped` — the API is
/// off by default (see `AutomationApiController`), so a persistent chip for
/// most users, who never enable it, would be noise. It appears for
/// `running` (plain, or with the fallback-port hint when the bound port
/// differs from the requested one) and `error` (no free port found), and
/// forwards a tap to [WpRecordingDock.onAutomationApiTap].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/automation_api/automation_api_controller.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import 'package:golden_screenshot/golden_screenshot.dart';

import '../fixtures/test_helpers.dart';

void main() {
  // Measure with the bundled fonts: the default Ahem test font is far wider
  // than the app's, which would make the chips fall back to icon form.
  setUpAll(loadAppFonts);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(1280, 800);
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetDevicePixelRatio();
    view.resetPhysicalSize();
  });

  Future<void> openMehr(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dock-overflow')));
    await tester.pumpAndSettle();
  }

  Finder inEntry(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey('dock-menu-automation')),
    matching: finder,
  );

  Widget buildStatusBar({
    AutomationApiRunState? automationApiRunState,
    int? automationApiPort,
    int? automationApiRequestedPort,
    VoidCallback? onAutomationApiTap,
  }) {
    return makeTestable(
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          WpRecordingDock(
            sttModeLabel: 'On device',
            sttState: SttServerState.ready,
            automationApiRunState: automationApiRunState,
            automationApiPort: automationApiPort,
            automationApiRequestedPort: automationApiRequestedPort,
            onAutomationApiTap: onAutomationApiTap,
          ),
        ],
      ),
    );
  }

  testWidgets('hidden when automationApiRunState is null', (tester) async {
    await tester.pumpWidget(buildStatusBar());
    await tester.pump();
    expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
    expect(find.byIcon(LucideIcons.terminal), findsNothing);
    expect(find.byIcon(LucideIcons.circleAlert), findsNothing);
  });

  testWidgets('hidden when automationApiRunState is stopped', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(automationApiRunState: AutomationApiRunState.stopped),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
    expect(find.byIcon(LucideIcons.terminal), findsNothing);
  });

  testWidgets('running on the requested port shows the plain port label', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(
        automationApiRunState: AutomationApiRunState.running,
        automationApiPort: 8765,
        automationApiRequestedPort: 8765,
      ),
    );
    await tester.pump();
    await openMehr(tester);
    expect(inEntry(find.byIcon(LucideIcons.terminal)), findsOneWidget);
    expect(inEntry(find.text('Automation: 8765')), findsOneWidget);
  });

  testWidgets(
    'running on a fallback port still shows the bound port label, with the '
    'fallback noted in the tooltip',
    (tester) async {
      await tester.pumpWidget(
        buildStatusBar(
          automationApiRunState: AutomationApiRunState.running,
          automationApiPort: 8766,
          automationApiRequestedPort: 8765,
        ),
      );
      await tester.pump();
      await openMehr(tester);

      expect(inEntry(find.byIcon(LucideIcons.terminal)), findsOneWidget);
      expect(inEntry(find.text('Automation: 8766')), findsOneWidget);

      final tooltipWidget = tester.widget<Tooltip>(
        find.descendant(
          of: find.byKey(const ValueKey('dock-menu-automation')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(
        tooltipWidget.message,
        'Automation API active on port 8766 (port 8765 was in use)',
      );
    },
  );

  testWidgets('error state shows the error icon and label', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(automationApiRunState: AutomationApiRunState.error),
    );
    await tester.pump();
    await openMehr(tester);

    expect(inEntry(find.byIcon(LucideIcons.circleAlert)), findsOneWidget);
    expect(inEntry(find.text('Automation: error')), findsOneWidget);
  });

  testWidgets('selecting the entry invokes onAutomationApiTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      buildStatusBar(
        automationApiRunState: AutomationApiRunState.running,
        automationApiPort: 8765,
        automationApiRequestedPort: 8765,
        onAutomationApiTap: () => tapped = true,
      ),
    );
    await tester.pump();
    await openMehr(tester);
    await tester.tap(find.byKey(const ValueKey('dock-menu-automation')));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
