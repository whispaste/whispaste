/// The dock's dropdowns for Smart Mode, language and speech recognition: they
/// show the settings value, write the choice back through their callbacks,
/// follow the settings as they change, and move into Mehr as submenus when the
/// row is narrow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/dock_choice_fixtures.dart';
import '../fixtures/test_helpers.dart';

WpRecordingDock _dock({
  WpDockChoiceSet? smartMode,
  WpDockChoiceSet? language,
  WpDockChoiceSet? engine,
  RecordingPhase recordingPhase = RecordingPhase.idle,
}) => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  smartMode: smartMode,
  language: language,
  engine: engine,
  recordingPhase: recordingPhase,
  microphoneLabel: 'Built-in',
  microphoneOptions: const ['Built-in'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Copy',
  afterAction: null,
);

Future<void> _pump(
  WidgetTester tester,
  WpRecordingDock dock, {
  double width = 1200,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width + 24, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: width + 24, child: dock),
      ),
      size: Size(width + 24, 800),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
}

Finder _menuRow(String id) => find.byKey(ValueKey(id));

void main() {
  group('dropdown in the row', () {
    testWidgets('opens its options and marks the current one', (tester) async {
      await _pump(tester, _dock(smartMode: dockTestSmartMode(label: 'Aus')));
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dock-menu-panel')), findsOneWidget);
      expect(_menuRow('dock-menu-smart-mode-off'), findsOneWidget);
      expect(_menuRow('dock-menu-smart-mode-cleanup'), findsOneWidget);
      expect(
        find.descendant(
          of: _menuRow('dock-menu-smart-mode-off'),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _menuRow('dock-menu-smart-mode-cleanup'),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsNothing,
      );
    });

    testWidgets('picking an option writes it and closes the menu', (
      tester,
    ) async {
      String? picked;
      await _pump(
        tester,
        _dock(
          smartMode: dockTestSmartMode(
            label: 'Aus',
            onChanged: (value) => picked = value,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();
      await tester.tap(_menuRow('dock-menu-smart-mode-cleanup'));
      await tester.pumpAndSettle();

      expect(picked, 'cleanup');
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsNothing);
    });

    testWidgets('follows the settings: the new value shows at once', (
      tester,
    ) async {
      await _pump(tester, _dock(smartMode: dockTestSmartMode(label: 'Aus')));
      expect(find.text('Aus'), findsWidgets);

      await _pump(
        tester,
        _dock(
          smartMode: dockTestSmartMode(label: 'Bereinigen', current: 'cleanup'),
        ),
      );
      expect(find.text('Bereinigen'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _menuRow('dock-menu-smart-mode-cleanup'),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the footer link runs its action', (tester) async {
      var footerTaps = 0;
      final set = WpDockChoiceSet(
        id: 'smart-mode',
        menuId: 'smart-mode',
        overline: 'Smart Mode',
        icon: LucideIcons.sparkles,
        choices: const [WpDockChoice(value: 'off', label: 'Aus')],
        current: 'off',
        currentLabel: 'Aus',
        onChanged: (_) {},
        searchHint: 'Search…',
        noMatchesLabel: 'No matches',
        footerLabel: 'Smart-Mode-Einstellungen…',
        onFooterTap: () => footerTaps++,
      );
      await _pump(tester, _dock(smartMode: set));
      await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
      await tester.pumpAndSettle();
      await tester.tap(_menuRow('dock-menu-smart-mode-footer'));
      await tester.pumpAndSettle();

      expect(footerTaps, 1);
    });

    testWidgets('the speech-recognition options are grouped by engine', (
      tester,
    ) async {
      await _pump(tester, _dock(engine: dockTestEngine()));
      await tester.tap(find.byKey(const ValueKey('dock-engine')));
      await tester.pumpAndSettle();

      expect(find.text('ON DEVICE'), findsOneWidget);
      expect(find.text('CLOUD'), findsOneWidget);
      expect(_menuRow('dock-menu-stt-openAI'), findsOneWidget);
    });

    testWidgets(
      'speech recognition is locked while a dictation runs, with the reason',
      (tester) async {
        var changed = false;
        await _pump(
          tester,
          _dock(
            engine: dockTestEngine(
              lockedWhileBusy: true,
              onChanged: (_) => changed = true,
              lockedReason: 'Locked during a recording',
            ),
            recordingPhase: RecordingPhase.recording,
          ),
        );
        // The recording indicator animates, so the tree never settles here.
        await tester.tap(find.byKey(const ValueKey('dock-engine')));
        await tester.pump();

        expect(find.byKey(const ValueKey('dock-menu-panel')), findsOneWidget);
        expect(find.text('Locked during a recording'), findsOneWidget);
        await tester.tap(_menuRow('dock-menu-stt-parakeet'));
        await tester.pump();
        expect(changed, isFalse);
      },
    );

    testWidgets(
      'the menu shows the note that a change applies from the next recording',
      (tester) async {
        await _pump(
          tester,
          _dock(
            smartMode: dockTestSmartMode(
              label: 'Aus',
              note: 'Applies from the next recording',
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
        await tester.pumpAndSettle();

        expect(find.text('Applies from the next recording'), findsOneWidget);
      },
    );

    testWidgets('a missing language dropdown leaves no language chip', (
      tester,
    ) async {
      await _pump(tester, _dock(language: null));
      expect(find.byKey(const ValueKey('dock-language')), findsNothing);
    });
  });

  group('Mehr when the row is narrow', () {
    testWidgets(
      'a dropdown moves into Mehr as a submenu that expands in place',
      (tester) async {
        String? picked;
        await _pump(
          tester,
          _dock(
            language: dockTestLanguage(
              label: 'DE',
              onChanged: (value) => picked = value,
            ),
          ),
          width: 420,
        );
        await tester.tap(find.byKey(const ValueKey('dock-overflow')));
        await tester.pumpAndSettle();

        expect(_menuRow('dock-menu-language-en'), findsNothing);
        await tester.tap(_menuRow('dock-menu-language'));
        await tester.pumpAndSettle();
        expect(_menuRow('dock-menu-language-en'), findsOneWidget);

        await tester.tap(_menuRow('dock-menu-language-en'));
        await tester.pumpAndSettle();
        expect(picked, 'en');
      },
    );
  });
}
