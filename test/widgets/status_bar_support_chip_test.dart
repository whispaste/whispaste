/// Widget tests for the sponsor entry in the dock's Mehr menu: its two looks,
/// its tap target, and the hide entry that exists only once hiding is allowed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import 'package:golden_screenshot/golden_screenshot.dart';

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

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
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

  testWidgets('sponsor mode shows the heart and the Sponsor label', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.sponsor));
    await tester.pump();
    await openMehr(tester);
    final entry = find.byKey(const ValueKey('dock-menu-sponsor'));
    expect(entry, findsOneWidget);
    expect(
      find.descendant(of: entry, matching: find.text(l10n.supportChipLabel)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('thanks mode shows the thank-you label', (tester) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.thanks));
    await tester.pump();
    await openMehr(tester);
    expect(find.text(l10n.supportChipThanksLabel), findsOneWidget);
    expect(find.text(l10n.supportChipLabel), findsNothing);
  });

  testWidgets('selecting the entry forwards to onSupportTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _bar(mode: WpSupportChipMode.sponsor, onTap: () => taps++),
    );
    await tester.pump();
    await openMehr(tester);
    await tester.tap(find.byKey(const ValueKey('dock-menu-sponsor')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('the sponsor entry is the only sponsor row in Mehr', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.thanks));
    await tester.pump();
    await openMehr(tester);
    expect(find.byKey(const ValueKey('dock-menu-sponsor')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-menu-sponsor-hide')), findsNothing);
  });
}
