/// Contract tests for the ticket app shell: the rail's navigation order, the
/// recording dock's Dictate button, the hotkey keycap, the status truth of the
/// dock's "Local ready" wording, and layout under RTL and large text.
///
/// Each of these is behaviour a user relies on, so each is pinned here rather
/// than in a golden: a golden shows what the shell looks like, not what it
/// does.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/app.dart'
    show wpHelpNavItem, wpNavDividerAfterIds, wpNavItems, wpSettingsNavItem;
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/wp_status_dot.dart';

import '../fixtures/test_helpers.dart';

/// Counts Dictate presses without starting a recording. `build()` is a no-op,
/// so no audio service or STT engine is wired up by mounting it.
class _FakeOrchestrator extends RecordingOrchestrator {
  int toggles = 0;

  @override
  void build() {}

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
    String? languageOverride,
    double? silenceTimeoutOverride,
  }) async => toggles++;
}

Widget _dock({
  String sttModeLabel = 'On device',
  SttServerState sttState = SttServerState.ready,
  bool localProcessing = false,
  String? hotkeyLabel,
}) {
  return Align(
    alignment: Alignment.bottomCenter,
    child: WpRecordingDock(
      sttModeLabel: sttModeLabel,
      sttState: sttState,
      localProcessing: localProcessing,
      hotkeyLabel: hotkeyLabel,
    ),
  );
}

void main() {
  // The dock's group widths depend on glyph widths, so measure with the bundled
  // fonts, as the goldens do, not the test engine's Ahem blocks.
  setUpAll(loadAppFonts);

  final en = lookupL10n(const Locale('en'));

  group('navigation order', () {
    test(
      'rail shows nine areas: seven pages, then Help and Settings at the foot',
      () {
        final main = wpNavItems(en).map((item) => item.id).toList();
        final bottom = [wpHelpNavItem(en).id, wpSettingsNavItem(en).id];

        expect(main, [
          'overview',
          'snippets',
          'notes',
          'history',
          'smartMode',
          'replacements',
          'analytics',
        ]);
        expect(bottom, ['help', 'settings']);
        expect(main.length + bottom.length, 9);
      },
    );

    test('the group break sits after history and after replacements', () {
      expect(wpNavDividerAfterIds, {'history', 'replacements'});
    });
  });

  group('dock Dictate button', () {
    testWidgets('a press calls the recording orchestrator once', (
      tester,
    ) async {
      final orchestrator = _FakeOrchestrator();
      await tester.pumpWidget(
        makeTestable(
          _dock(),
          size: const Size(1100, 800),
          locale: const Locale('en'),
          overrides: [
            recordingOrchestratorProvider.overrideWith(() => orchestrator),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('dock-dictate')));
      await tester.pump();

      expect(orchestrator.toggles, 1);
    });
  });

  group('hotkey keycap', () {
    testWidgets('shows the configured hotkey in the platform\'s own names', (
      tester,
    ) async {
      // macOS spells modifiers as glyphs, the other platforms as words, so the
      // expected string follows the host OS.
      final expected = Platform.isMacOS ? '⌃⌥ Space' : 'Ctrl+Alt+Space';
      final label = formatHotkeyKeycap(
        'ctrl+alt',
        'space',
        l10n: en,
        isMacOS: Platform.isMacOS,
      );
      expect(label, expected);

      await tester.pumpWidget(
        makeTestable(
          _dock(hotkeyLabel: label),
          size: const Size(1100, 800),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();

      final keycap = find.byKey(const ValueKey('dock-dictate-keycap'));
      expect(keycap, findsOneWidget);
      expect(
        find.descendant(of: keycap, matching: find.text(expected)),
        findsOneWidget,
      );
    });
  });

  group('status truth', () {
    testWidgets(
      'says "Ready · Local" only when dictation provably runs locally',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _dock(localProcessing: true),
            size: const Size(1100, 800),
            locale: const Locale('en'),
          ),
        );
        await tester.pump();
        expect(
          find.text('${en.statusReady} · ${en.statusLocal}'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a ready engine that is not provably local says plain "Ready"',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _dock(localProcessing: false),
            size: const Size(1100, 800),
            locale: const Locale('en'),
          ),
        );
        await tester.pump();
        expect(find.text(en.statusReady), findsOneWidget);
        expect(find.textContaining(' · '), findsNothing);
      },
    );
  });

  group('status dot tone', () {
    // Spec §2 (mockup): the green dot appears only with "Lokal bereit", i.e.
    // when the local engine is loaded and really ready. Every other state keeps
    // its own tone, so green stays a rare, earned signal.
    WpStatusTone toneOf(WidgetTester tester) =>
        tester.widget<WpStatusDot>(find.byType(WpStatusDot)).tone;

    testWidgets('green (success) only when the local engine is really ready', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          _dock(localProcessing: true),
          size: const Size(1100, 800),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      expect(toneOf(tester), WpStatusTone.success);
    });

    testWidgets('ready but not provably local stays neutral, not green', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          _dock(localProcessing: false),
          size: const Size(1100, 800),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      expect(toneOf(tester), WpStatusTone.idle);
    });

    testWidgets('stopped engine is neutral, never green', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          _dock(sttState: SttServerState.stopped, localProcessing: true),
          size: const Size(1100, 800),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      expect(toneOf(tester), isNot(WpStatusTone.success));
    });
  });
}
