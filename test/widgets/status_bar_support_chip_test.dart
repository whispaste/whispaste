/// Widget tests for the sponsor chip: it sits in the dock row (#374), moves
/// into the Mehr menu when the row is too narrow, and forwards its tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/app_fonts.dart';

import '../fixtures/test_helpers.dart';

Widget _bar({WpSupportChipMode? mode, VoidCallback? onTap}) => makeTestable(
  Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      WpRecordingDock(
        sttModeLabel: 'On device',
        supportChipMode: mode,
        onSupportTap: onTap,
      ),
    ],
  ),
  locale: const Locale('en'),
);

void main() {
  // Measure with the bundled fonts: the default Ahem test font is far wider
  // than the app's, which would push entries out of the row.
  setUpAll(loadAppFontsOnce);

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

  testWidgets('no Mehr menu when there is no sponsor entry', (tester) async {
    await tester.pumpWidget(_bar());
    await tester.pump();
    expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
  });

  void setWidth(double width) {
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .views
        .first
        .physicalSize = Size(
      width,
      800,
    );
  }

  testWidgets('the chip sits in the row and forwards its tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _bar(mode: WpSupportChipMode.thanks, onTap: () => taps++),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dock-support')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a narrow row moves the chip into Mehr', (tester) async {
    setWidth(360);
    var taps = 0;
    await tester.pumpWidget(
      _bar(mode: WpSupportChipMode.sponsor, onTap: () => taps++),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('dock-support')), findsNothing);
    await openMehr(tester);
    await tester.tap(find.byKey(const ValueKey('dock-menu-sponsor')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('without a tap handler there is no dead entry', (tester) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.thanks));
    await tester.pump();
    expect(find.byKey(const ValueKey('dock-support')), findsNothing);
    expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
  });
}
