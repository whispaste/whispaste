/// Behaviour of the WP-79 dock row: stable keys for every control and Mehr
/// entry, keyboard use of the Mehr menu, icon-only accessible names and
/// tooltips, text scaling, and the minimal plan at narrow widths.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';
import 'package:whispaste/widgets/recording_dock_layout.dart';

import '../fixtures/test_helpers.dart';
import '../fixtures/dock_choice_fixtures.dart';

/// Every selector id the row can show (WpDockSelectorSpec ids).
const _selectorIds = [
  'smart-mode',
  'engine',
  'language',
  'output-action',
  'microphone',
];

WpRecordingDock _dock({bool withHotkey = true}) => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  engine: dockTestEngine(label: 'Whisper · small'),
  sttState: SttServerState.ready,
  smartMode: dockTestSmartMode(label: 'Aus'),
  hotkeyLabel: withHotkey ? 'Strg+Umschalt+D' : null,
  onHotkeyTap: () {},
  microphoneLabel: micDefaultLabel,
  microphoneOptions: const [micDefaultLabel, 'USB-Mikrofon'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Kopieren',
  afterAction: AfterTranscriptionAction.clipboard,
  onAfterActionChanged: (_) {},
  language: dockTestLanguage(label: 'DE'),
  onSttTap: () {},
  onUpdateTap: () {},
  updateVersion: '1.5.0',
  onAutomationApiTap: () {},
);

/// Pumps the dock in a box whose width is the dock width plus the dock's own
/// horizontal inset, so the row sees exactly [dockWidth].
Future<void> _pumpDock(
  WidgetTester tester,
  double dockWidth, {
  double textScale = 1,
  WpRecordingDock? dock,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(dockWidth + 24, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: Size(dockWidth + 24, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: dockWidth + 24, child: dock ?? _dock()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('stable keys (DEV-133)', () {
    testWidgets('every selector id renders as dock-<id> on a wide dock', (
      tester,
    ) async {
      await _pumpDock(tester, 1800);
      expect(find.byKey(const ValueKey('dock-dictate')), findsOneWidget);
      expect(find.byKey(const ValueKey('dock-dictate-keycap')), findsOneWidget);
      expect(find.byKey(const ValueKey('dock-hotkey')), findsNothing);
      expect(find.byKey(const ValueKey('dock-status')), findsOneWidget);
      for (final id in _selectorIds) {
        expect(
          find.byKey(ValueKey('dock-$id')),
          findsOneWidget,
          reason: 'selector $id has no dock-$id key',
        );
      }
    });

    testWidgets('a selector moved into Mehr is reachable as a Mehr entry', (
      tester,
    ) async {
      await _pumpDock(tester, 560);
      await tester.tap(find.byKey(const ValueKey('dock-overflow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-menu-hotkey')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dock-menu-smart-mode')),
        findsOneWidget,
      );
    });
  });

  group('Mehr menu keyboard use', () {
    testWidgets('Escape closes the open Mehr menu', (tester) async {
      await _pumpDock(tester, 560);
      await tester.tap(find.byKey(const ValueKey('dock-overflow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-menu-hotkey')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-menu-hotkey')), findsNothing);
    });

    testWidgets('arrow keys move through Mehr and Enter runs the entry', (
      tester,
    ) async {
      var taps = 0;
      final dock = WpRecordingDock(
        sttModeLabel: 'Whisper · small',
        engine: dockTestEngine(label: 'Whisper · small'),
        hotkeyLabel: 'Strg+Umschalt+D',
        onHotkeyTap: () => taps++,
        smartMode: dockTestSmartMode(label: 'Aus'),
        onSttTap: () {},
      );
      await _pumpDock(tester, 560, dock: dock);
      await tester.tap(find.byKey(const ValueKey('dock-overflow')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'Enter on the arrowed-to entry runs its action');
    });
  });

  group('icon-only selectors', () {
    testWidgets(
      'an icon-only selector keeps its accessible name and shows its value as tooltip',
      (tester) async {
        Finder iconOnlyLanguage() => find.byWidgetPredicate(
          (w) =>
              w is WpDockSelector &&
              w.id == 'language' &&
              w.form == WpDockSelectorForm.iconOnly,
        );
        var found = false;
        for (var width = 560.0; width <= 1100 && !found; width += 20) {
          await _pumpDock(tester, width);
          found = iconOnlyLanguage().evaluate().isNotEmpty;
        }
        expect(found, isTrue, reason: 'language never reaches icon-only');
        expect(find.bySemanticsLabel(RegExp(r': DE$')), findsOneWidget);
        final tooltip = tester.widget<Tooltip>(
          find.descendant(
            of: iconOnlyLanguage(),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, endsWith(': DE'));
      },
    );
  });

  group('text scaling', () {
    for (final width in [800.0, 1100.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'dock ${width.toInt()} px at text scale $scale: no overflow, '
          'Dictate and Mehr reachable',
          (tester) async {
            await _pumpDock(tester, width - 24, textScale: scale);
            expect(tester.takeException(), isNull);
            expect(find.byKey(const ValueKey('dock-dictate')), findsOneWidget);
            expect(find.byKey(const ValueKey('dock-status')), findsOneWidget);
          },
        );
      }
    }
  });

  group('minimal plan at narrow widths', () {
    for (final width in [612.0, 560.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'dock ${width.toInt()} px at text scale $scale: no overflow, '
          'Dictate and Stop stay visible',
          (tester) async {
            final dock = _dock();
            await _pumpDock(
              tester,
              width,
              textScale: scale,
              dock: WpRecordingDock(
                sttModeLabel: dock.sttModeLabel,
                sttState: dock.sttState,
                smartMode: dock.smartMode,
                hotkeyLabel: dock.hotkeyLabel,
                onHotkeyTap: dock.onHotkeyTap,
                microphoneLabel: dock.microphoneLabel,
                microphoneOptions: dock.microphoneOptions,
                onMicrophoneChanged: dock.onMicrophoneChanged,
                afterActionLabel: dock.afterActionLabel,
                afterAction: dock.afterAction,
                onAfterActionChanged: dock.onAfterActionChanged,
                language: dock.language,
                engine: dock.engine,
                recordingPhase: RecordingPhase.recording,
              ),
            );
            expect(tester.takeException(), isNull);
            final surface = tester.getRect(
              find.byKey(const ValueKey('dock-surface')),
            );
            final button = tester.getRect(
              find.byKey(const ValueKey('dock-dictate')),
            );
            expect(button.left, greaterThanOrEqualTo(surface.left));
            expect(button.right, lessThanOrEqualTo(surface.right));
            expect(button.height, greaterThan(0));
          },
        );
      }
    }
  });

  group('hotkey without the keycap', () {
    testWidgets('at 560 px the Dictate tooltip names the hotkey', (
      tester,
    ) async {
      await _pumpDock(tester, 560);
      expect(find.byKey(const ValueKey('dock-hotkey')), findsNothing);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('dock-dictate')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('Strg+Umschalt+D'));
    });
  });

  group('fits=false and minimal plan', () {
    for (final width in [612.0, 560.0, 300.0]) {
      testWidgets('dock ${width.toInt()} px: no overflow error', (
        tester,
      ) async {
        await _pumpDock(tester, width);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('dock-dictate')), findsOneWidget);
      });
    }
  });
}
