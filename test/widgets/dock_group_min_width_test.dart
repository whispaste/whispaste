/// Layout tests for the dock row under a realistic state: a model that is
/// still loading, status chips visible, a long model name and a long
/// microphone name. The row must never overflow and the chip area must keep
/// at least one chip, at the widths the app really produces (the sidebar
/// takes 72 px below 960 px window width and 232 px above).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';
import '../fixtures/dock_choice_fixtures.dart';

const _longModel = 'whisper-large-v3-turbo';
const _longMic = 'Razer Seiren Mini 2 USB Ultra';

Widget _dock({
  required double contentWidth,
  bool withChips = true,
  double textScale = 1,
}) {
  return makeTestable(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: contentWidth,
            child: WpRecordingDock(
              sttModeLabel: _longModel,
              sttState: SttServerState.starting,
              sttStartingSince: DateTime.now(),
              smartMode: dockTestSmartMode(label: 'Smart Mode · Aus'),
              hotkeyLabel: 'Ctrl+Shift+D',
              microphoneLabel: _longMic,
              microphoneOptions: const [_longMic],
              onMicrophoneChanged: (_) {},
              language: dockTestLanguage(label: 'DE'),
              updateVersion: withChips ? '9.9.9' : null,
              backendKind: withChips ? 'cuda' : null,
              showAutoPasteOffHint: withChips,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The content width the app gives the dock at a window width.
double _contentWidthFor(double windowWidth) =>
    windowWidth - (windowWidth < 960 ? 72 : 232);

void _setWindow(WidgetTester tester, double width) {
  final view = tester.view;
  view.devicePixelRatio = 1.0;
  view.physicalSize = Size(width, 600);
  addTearDown(view.resetPhysicalSize);
  addTearDown(view.resetDevicePixelRatio);
}

/// No overflow, and every row child ends inside the row (the status follows it).
void _expectRowFits(WidgetTester tester) {
  expect(tester.takeException(), isNull, reason: 'the dock must not overflow');
  final surface = tester.getRect(find.byKey(const ValueKey('dock-surface')));
  final dictate = tester.getRect(find.byKey(const ValueKey('dock-dictate')));
  final status = tester.getRect(find.byKey(const ValueKey('dock-status')));
  expect(dictate.left, greaterThanOrEqualTo(surface.left - 0.5));
  expect(
    status.right,
    lessThanOrEqualTo(surface.right + 0.5),
    reason:
        'the status reaches past the dock by ${(status.right - surface.right).toStringAsFixed(1)} px',
  );
}

void main() {
  group('with bundled fonts', () {
    setUpAll(loadAppFonts);

    for (final window in [800.0, 960.0, 1100.0, 1440.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('no overflow, chips kept, at ${window.toInt()} px window, '
            'text scale $scale', (tester) async {
          _setWindow(tester, window);
          await tester.pumpWidget(
            _dock(contentWidth: _contentWidthFor(window), textScale: scale),
          );
          await tester.pump();
          _expectRowFits(tester);
          expect(
            tester.getSize(find.byKey(const ValueKey('dock-status'))).width,
            greaterThan(0),
            reason: 'the status keeps room to read',
          );
        });
      }
    }

    // 728 px is the narrowest dock the tight density still has to fit.
    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow at a 728 px dock, text scale $scale', (
        tester,
      ) async {
        _setWindow(tester, 800);
        await tester.pumpWidget(_dock(contentWidth: 728, textScale: scale));
        await tester.pump();
        _expectRowFits(tester);
      });
    }
  });

  group('first frame, system fallback font', () {
    for (final window in [800.0, 1440.0]) {
      testWidgets('no overflow at ${window.toInt()} px window', (tester) async {
        _setWindow(tester, window);
        await tester.pumpWidget(_dock(contentWidth: _contentWidthFor(window)));
        await tester.pump();
        _expectRowFits(tester);
      });
    }
  });
}
