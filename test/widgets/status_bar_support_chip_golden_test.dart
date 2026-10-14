/// Golden test for the sponsor chip in its two looks, sponsor and thanks,
/// inside the real status bar.
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

Future<void> _pumpBar(WidgetTester tester, WpSupportChipMode mode) async {
  tester.view.physicalSize = const Size(900, 60);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      WpStatusBar(
        sttModeLabel: 'On device',
        supportChipMode: mode,
        onSupportTap: () {},
      ),
      size: const Size(900, 60),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadAppFonts());

  testWidgets('sponsor chip in status bar', (tester) async {
    await _pumpBar(tester, WpSupportChipMode.sponsor);
    await expectLater(
      find.byType(WpStatusBar),
      matchesGoldenFile('goldens/status_bar_support_chip_sponsor.png'),
    );
  });

  testWidgets('thanks chip in status bar', (tester) async {
    await _pumpBar(tester, WpSupportChipMode.thanks);
    await expectLater(
      find.byType(WpStatusBar),
      matchesGoldenFile('goldens/status_bar_support_chip_thanks.png'),
    );
  });
}
