/// The dock's Smart Mode dropdown without a usable text model (UIA-XP-7-05):
/// the presets other than "Aus" cannot be picked, the menu says why, and the
/// footer leads to the place where the model is loaded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';

const _reason = 'No text model set up – only Off can be picked.';

WpDockChoiceSet _smartMode({
  ValueChanged<String>? onChanged,
  VoidCallback? onFooterTap,
  bool withoutTextModel = true,
}) => WpDockChoiceSet(
  id: 'smart-mode',
  menuId: 'smart-mode',
  overline: 'Smart Mode',
  icon: LucideIcons.sparkles,
  choices: [
    const WpDockChoice(value: 'off', label: 'Off'),
    WpDockChoice(
      value: 'cleanup',
      label: 'Cleanup',
      unavailableReason: withoutTextModel ? _reason : null,
    ),
  ],
  current: 'off',
  currentLabel: 'Off',
  onChanged: onChanged ?? (_) {},
  searchHint: 'Search…',
  noMatchesLabel: 'No matches',
  footerLabel: 'No text model – load now',
  onFooterTap: onFooterTap ?? () {},
);

WpRecordingDock _dock(WpDockChoiceSet smartMode) => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  smartMode: smartMode,
  recordingPhase: RecordingPhase.idle,
  microphoneLabel: 'Built-in',
  microphoneOptions: const ['Built-in'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Copy',
  afterAction: null,
);

Future<void> _pump(WidgetTester tester, WpRecordingDock dock) async {
  const width = 1200.0;
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(width + 24, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: width + 24, child: dock),
      ),
      size: const Size(width + 24, 800),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
}

Finder _menuRow(String id) => find.byKey(ValueKey(id));

void main() {
  group('Smart Mode without a text model', () {
    testWidgets('a preset other than Off cannot be picked', (tester) async {
      String? picked;
      await _pump(
        tester,
        _dock(_smartMode(onChanged: (value) => picked = value)),
      );
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();

      await tester.tap(_menuRow('dock-menu-smart-mode-cleanup'));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      // The menu stays open: a disabled entry does not act like a choice.
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsOneWidget);
    });

    testWidgets('Off stays pickable', (tester) async {
      String? picked;
      await _pump(
        tester,
        _dock(_smartMode(onChanged: (value) => picked = value)),
      );
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();

      await tester.tap(_menuRow('dock-menu-smart-mode-off'));
      await tester.pumpAndSettle();

      expect(picked, 'off');
    });

    testWidgets('the menu says why the presets are locked', (tester) async {
      await _pump(tester, _dock(_smartMode()));
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();

      expect(find.text(_reason), findsOneWidget);
    });

    testWidgets('the footer leads to loading the text model', (tester) async {
      var footerTaps = 0;
      await _pump(tester, _dock(_smartMode(onFooterTap: () => footerTaps++)));
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('No text model – load now'));
      await tester.pumpAndSettle();

      expect(footerTaps, 1);
    });

    testWidgets('with a text model every preset is pickable', (tester) async {
      String? picked;
      await _pump(
        tester,
        _dock(
          _smartMode(
            withoutTextModel: false,
            onChanged: (value) => picked = value,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();

      expect(find.text(_reason), findsNothing);
      await tester.tap(_menuRow('dock-menu-smart-mode-cleanup'));
      await tester.pumpAndSettle();

      expect(picked, 'cleanup');
    });
  });
}
