import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/manual/user_manual_view.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/support_fakes.dart';
import '../../fixtures/test_helpers.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      const HelpPage(),
      size: size,
      overrides: supportOverrides(
        channel: DeployChannel.packageManaged,
        platform: SupportPlatform.macos,
        status: FakeSupportStatusNotifier(const SupportStatus()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tab(HelpTab tab) => find.byKey(ValueKey('help-hub-tab-${tab.name}'));

void main() {
  setUp(() => WpColors.activate(wpLightColors));
  tearDown(() => WpColors.activate(wpLightColors));

  for (final width in [800.0, 1100.0, 1600.0]) {
    testWidgets('help hub renders without exception at ${width.toInt()} px', (
      tester,
    ) async {
      await _pump(tester, Size(width, 900));

      expect(tester.takeException(), isNull);
      for (final tab in HelpTab.values) {
        expect(_tab(tab), findsOneWidget, reason: 'tab ${tab.name}');
      }
      expect(find.byType(UserManualView), findsOneWidget);
    });
  }

  testWidgets('tabs switch the body between handbook and support', (
    tester,
  ) async {
    await _pump(tester, const Size(1100, 900));
    expect(find.byType(UserManualView), findsOneWidget);
    expect(find.byKey(const ValueKey('help-feedback-button')), findsNothing);

    await tester.tap(_tab(HelpTab.support));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-feedback-button')), findsOneWidget);
    expect(find.byType(UserManualView), findsNothing);

    await tester.tap(_tab(HelpTab.manual));
    await tester.pumpAndSettle();
    expect(find.byType(UserManualView), findsOneWidget);
    expect(find.byKey(const ValueKey('help-feedback-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
