/// Widget tests for the `WpRecordingDock` microphone choice, which lives in
/// the Mehr menu (#374).
///
/// It mirrors the tray submenu: visible only when real devices were
/// enumerated, system-default entry first, the submenu names the current
/// device, and selection is routed through the host callback (which wires it
/// to `MicrophoneSelectionService`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/microphone_selection_service.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';

void main() {
  const options = [
    micDefaultLabel,
    'MacBook Pro Microphone',
    'Razer Seiren Mini',
  ];

  Widget buildStatusBar({
    String? microphoneLabel,
    List<String>? microphoneOptions,
    ValueChanged<String>? onChanged,
    VoidCallback? onOpened,
  }) {
    return makeTestable(
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          WpRecordingDock(
            sttModeLabel: 'On device',
            sttState: SttServerState.ready,
            microphoneLabel: microphoneLabel,
            microphoneOptions: microphoneOptions,
            onMicrophoneChanged: onChanged,
            onMicrophoneMenuOpened: onOpened,
          ),
        ],
      ),
    );
  }

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

  L10n l10nOf(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(WpRecordingDock)));

  Finder mehrEntry() => find.byKey(const ValueKey('dock-menu-microphone'));

  Future<void> openMehr(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dock-overflow')));
    await tester.pumpAndSettle();
  }

  testWidgets('the row has no microphone selector; Mehr has the submenu', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: micDefaultLabel,
        microphoneOptions: options,
        onChanged: (_) {},
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('dock-microphone')), findsNothing);
    await openMehr(tester);
    expect(mehrEntry(), findsOneWidget);
  });

  testWidgets('the submenu names the localized system default', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: micDefaultLabel,
        microphoneOptions: options,
        onChanged: (_) {},
      ),
    );
    await tester.pump();
    await openMehr(tester);

    final l10n = l10nOf(tester);
    expect(find.textContaining(l10n.settingsMicSystemDefault), findsOneWidget);
  });

  testWidgets('the submenu names the raw device when one is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: 'Razer Seiren Mini',
        microphoneOptions: options,
        onChanged: (_) {},
      ),
    );
    await tester.pump();
    await openMehr(tester);

    expect(find.textContaining('Razer Seiren Mini'), findsOneWidget);
  });

  testWidgets('no microphone entry when the host passes no options', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: micDefaultLabel,
        microphoneOptions: null,
        onChanged: (_) {},
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
    expect(mehrEntry(), findsNothing);
  });

  testWidgets('opening Mehr reports onOpened and the submenu lists options', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: micDefaultLabel,
        microphoneOptions: options,
        onChanged: (_) {},
        onOpened: () => opened++,
      ),
    );
    await tester.pump();
    await openMehr(tester);
    await tester.tap(mehrEntry());
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.text('MacBook Pro Microphone'), findsOneWidget);
    expect(find.text('Razer Seiren Mini'), findsOneWidget);
  });

  testWidgets('selecting a device fires onMicrophoneChanged with raw label', (
    tester,
  ) async {
    final selections = <String>[];
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: micDefaultLabel,
        microphoneOptions: options,
        onChanged: selections.add,
      ),
    );
    await tester.pump();
    await openMehr(tester);
    await tester.tap(mehrEntry());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dock-menu-microphone-2')));
    await tester.pumpAndSettle();

    expect(selections, ['Razer Seiren Mini']);
  });
}
