/// Widget tests for the `WpStatusBar` Automation API chip.
///
/// The chip mirrors the update/hotkey chips: it is entirely absent while
/// [WpStatusBar.automationApiRunState] is `null` or `stopped` — the API is
/// off by default (see `AutomationApiController`), so a persistent chip for
/// most users, who never enable it, would be noise. It appears for
/// `running` (plain, or with the fallback-port hint when the bound port
/// differs from the requested one) and `error` (no free port found), and
/// forwards a tap to [WpStatusBar.onAutomationApiTap].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/automation_api/automation_api_controller.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

void main() {
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
          WpStatusBar(
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

    expect(find.byIcon(LucideIcons.terminal), findsNothing);
    expect(find.byIcon(LucideIcons.circleAlert), findsNothing);
  });

  testWidgets('hidden when automationApiRunState is stopped', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(automationApiRunState: AutomationApiRunState.stopped),
    );
    await tester.pump();

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

    expect(find.byIcon(LucideIcons.terminal), findsOneWidget);
    expect(find.text('API: 8765'), findsOneWidget);
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

      expect(find.byIcon(LucideIcons.terminal), findsOneWidget);
      expect(find.text('API: 8766'), findsOneWidget);

      final tooltipWidget = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byIcon(LucideIcons.terminal),
              matching: find.byType(Tooltip),
            )
            .first,
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

    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
    expect(find.text('API: error'), findsOneWidget);
  });

  testWidgets('tapping the chip invokes onAutomationApiTap', (tester) async {
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

    await tester.tap(find.text('API: 8765'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
