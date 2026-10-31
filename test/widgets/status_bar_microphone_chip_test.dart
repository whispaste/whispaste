/// Widget tests for the `WpStatusBar` microphone quick-switch chip.
///
/// The chip mirrors the tray submenu: visible only when real devices were
/// enumerated, system-default entry first, and selection routed through the
/// host callback (which wires it to `MicrophoneSelectionService`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/microphone_selection_service.dart';
import 'package:whispaste/widgets/status_bar.dart';

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
          WpStatusBar(
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
      L10n.of(tester.element(find.byType(WpStatusBar)));

  testWidgets('shows the localized system-default label when selected', (
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

    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    expect(find.text(l10nOf(tester).settingsMicSystemDefault), findsOneWidget);
  });

  testWidgets('shows the raw device name when a device is selected', (
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

    expect(find.text('Razer Seiren Mini'), findsOneWidget);
  });

  testWidgets('hides the chip when the host passes no options', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(
        microphoneLabel: micDefaultLabel,
        microphoneOptions: null,
        onChanged: (_) {},
      ),
    );
    await tester.pump();

    expect(find.byIcon(LucideIcons.mic), findsNothing);
  });

  testWidgets('opening the popup lists every option and reports onOpened', (
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

    await tester.tap(find.text(l10nOf(tester).settingsMicSystemDefault));
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

    await tester.tap(find.text(l10nOf(tester).settingsMicSystemDefault));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Razer Seiren Mini'));
    await tester.pumpAndSettle();

    expect(selections, ['Razer Seiren Mini']);
  });
}
