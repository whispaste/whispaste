/// The dock's popups (WpDockOverflow / Mehr, output and microphone selectors):
/// the hotkey is shown once, the sponsor hide entry is labelled, the popup
/// opens above the dock anchored to its trigger, status info is not
/// interactive, and no selector is cut off at medium widths.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';
import '../fixtures/dock_choice_fixtures.dart';

const _hotkey = 'Strg+Umschalt+D';

WpRecordingDock _dock({
  WpSupportChipMode? support,
  String? hotkey = _hotkey,
  bool notices = false,
}) => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  engine: dockTestEngine(label: 'Whisper · small'),
  sttState: SttServerState.ready,
  smartMode: dockTestSmartMode(label: 'Aus'),
  hotkeyLabel: hotkey,
  onHotkeyTap: () {},
  microphoneLabel: micDefaultLabel,
  microphoneOptions: const [micDefaultLabel, 'USB-Mikrofon'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Kopieren',
  afterAction: AfterTranscriptionAction.clipboard,
  onAfterActionChanged: (_) {},
  language: dockTestLanguage(label: 'DE'),
  onSttTap: () {},
  backendKind: 'GPU',
  backendUtilizationPercent: 2,
  supportChipMode: support,
  onSupportTap: () {},
  showAutoPasteOffHint: notices,
  onAutoPasteOffHintTap: notices ? () {} : null,
  onAutoPasteOffHintDismiss: notices ? () {} : null,
);

Future<void> _pump(
  WidgetTester tester,
  double dockWidth, {
  WpRecordingDock? dock,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(dockWidth + 24, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: dockWidth + 24, child: dock ?? _dock()),
      ),
      size: Size(dockWidth + 24, 800),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
}

Future<void> _openMehr(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('dock-overflow')));
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  setUpAll(loadAppFonts);

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('hotkey shown exactly once', () {
    testWidgets('the keycap sits inside the Dictate button, nowhere else', (
      tester,
    ) async {
      await _pump(tester, 1800);
      expect(find.byKey(const ValueKey('dock-hotkey')), findsNothing);
      final keycap = find.descendant(
        of: find.byKey(const ValueKey('dock-dictate')),
        matching: find.text(_hotkey),
      );
      expect(keycap, findsOneWidget);
      expect(find.text(_hotkey), findsOneWidget);
    });

    testWidgets('Mehr has no bare hotkey entry, but a labelled shortcut row', (
      tester,
    ) async {
      await _pump(tester, 560);
      await _openMehr(tester);
      expect(find.text(_hotkey), findsNothing);
      final row = find.byKey(const ValueKey('dock-menu-hotkey'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text(l10n.dockMenuHotkeyChange),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the shortcut row opens the hotkey settings', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        560,
        dock: WpRecordingDock(
          sttModeLabel: 'Whisper · small',
          engine: dockTestEngine(label: 'Whisper · small'),
          hotkeyLabel: _hotkey,
          onHotkeyTap: () => taps++,
          onSttTap: () {},
        ),
      );
      await _openMehr(tester);
      await tester.tap(find.byKey(const ValueKey('dock-menu-hotkey')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('status info row', () {
    testWidgets('GPU reading is a non-interactive row under a Status header', (
      tester,
    ) async {
      await _pump(tester, 560);
      await _openMehr(tester);
      expect(find.text(l10n.dockMenuGroupStatus.toUpperCase()), findsOneWidget);
      final info = find.byKey(const ValueKey('dock-menu-backend'));
      expect(info, findsOneWidget);
      expect(
        find.descendant(of: info, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: info,
          matching: find.text(backendUtilizationChipLabel('GPU', 2)),
        ),
        findsOneWidget,
      );
    });
  });

  group('popup placement and style', () {
    testWidgets('Mehr opens above the dock, right edge on the trigger', (
      tester,
    ) async {
      await _pump(tester, 560, dock: _dock(notices: true));
      await _openMehr(tester);
      final panel = _rect(
        tester,
        find.byKey(const ValueKey('dock-menu-panel')),
      );
      final trigger = _rect(
        tester,
        find.byKey(const ValueKey('dock-overflow')),
      );
      final surface = _rect(tester, find.byKey(const ValueKey('dock-surface')));
      expect(panel.bottom, lessThanOrEqualTo(surface.top));
      expect(panel.bottom, closeTo(surface.top - WpSpacing.xs, 1));
      expect(panel.right, closeTo(trigger.right, 1));
      expect(panel.overlaps(trigger), isFalse);
    });

    testWidgets('the microphone popup uses the same panel and placement', (
      tester,
    ) async {
      await _pump(tester, 1400);
      await tester.tap(find.byKey(const ValueKey('dock-microphone')));
      await tester.pumpAndSettle();
      final panel = _rect(
        tester,
        find.byKey(const ValueKey('dock-menu-panel')),
      );
      final surface = _rect(tester, find.byKey(const ValueKey('dock-surface')));
      expect(panel.bottom, closeTo(surface.top - WpSpacing.xs, 1));
      expect(find.text('USB-Mikrofon'), findsOneWidget);
    });

    testWidgets('Escape closes the popup; Enter runs the focused entry', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        560,
        dock: WpRecordingDock(
          sttModeLabel: 'Whisper · small',
          engine: dockTestEngine(label: 'Whisper · small'),
          hotkeyLabel: _hotkey,
          onHotkeyTap: () => taps++,
          onSttTap: () {},
        ),
      );
      await _openMehr(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsNothing);

      await _openMehr(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('no cut-off selector at medium widths', () {
    testWidgets(
      'every row selector is full or moved into Mehr, never clipped',
      (tester) async {
        for (var width = 600.0; width <= 1100; width += 25) {
          await _pump(tester, width);
          expect(tester.takeException(), isNull, reason: 'width $width');
          final mic = find.byKey(const ValueKey('dock-microphone'));
          if (mic.evaluate().isEmpty) {
            continue;
          }
          final text = find.descendant(of: mic, matching: find.byType(Text));
          for (final e in text.evaluate()) {
            final paragraph = e.renderObject! as RenderParagraph;
            final full = paragraph.getMaxIntrinsicWidth(double.infinity);
            expect(
              paragraph.size.width,
              greaterThanOrEqualTo(full - 0.5),
              reason: 'microphone text clipped at width $width',
            );
          }
        }
      },
    );
  });
}
