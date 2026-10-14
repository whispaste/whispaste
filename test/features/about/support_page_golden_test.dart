/// Golden tests for the support page: one direct-build macOS picture at
/// desktop width and one at 800 px, the narrow end of the layout range.
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/features/about/support_page.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/support_fakes.dart';
import '../../fixtures/test_helpers.dart';

Future<void> _pumpPage(WidgetTester tester, Size size) async {
  // makeTestable only feeds `size` into MediaQuery; the real surface must match.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      const SupportPage(),
      size: size,
      locale: const Locale('en'),
      overrides: supportOverrides(
        channel: DeployChannel.packageManaged,
        platform: SupportPlatform.macos,
        status: FakeSupportStatusNotifier(const SupportStatus()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadAppFonts());

  testWidgets('support page, direct build, wide', (tester) async {
    await _pumpPage(tester, const Size(1280, 1400));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/support_page_wide.png'),
    );
  });

  testWidgets('support page, direct build, 800 px', (tester) async {
    await _pumpPage(tester, const Size(800, 1600));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/support_page_800.png'),
    );
  });
}
