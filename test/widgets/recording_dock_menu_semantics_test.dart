/// The options of a dock menu are radio buttons with their checked state
/// (#1916): the desktop embedders take the role from the flags, and a button
/// role dropped the state, so assistive tech never heard the current choice.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/dock_choice_fixtures.dart';
import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('menu options are radio buttons, the current one checked', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1224, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 1224,
            child: WpRecordingDock(
              sttModeLabel: 'Whisper · small',
              smartMode: dockTestSmartMode(label: 'Aus'),
              microphoneLabel: 'Built-in',
              microphoneOptions: const ['Built-in'],
              onMicrophoneChanged: (_) {},
              afterActionLabel: 'Copy',
              afterAction: null,
            ),
          ),
        ),
        size: const Size(1224, 800),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
    await tester.pumpAndSettle();

    // The row's merged node, reached from its label inside the row.
    SemanticsData row(String id, String label) => tester
        .getSemantics(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.text(label),
          ),
        )
        .getSemanticsData();

    final current = row('dock-menu-smart-mode-off', 'Aus');
    final other = row('dock-menu-smart-mode-cleanup', 'Bereinigen');
    for (final data in [current, other]) {
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }
    expect(current.flagsCollection.isChecked, ui.CheckedState.isTrue);
    expect(other.flagsCollection.isChecked, ui.CheckedState.isFalse);
    handle.dispose();
  });
}
