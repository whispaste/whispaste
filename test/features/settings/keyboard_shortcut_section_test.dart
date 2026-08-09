import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('KeyboardShortcutSection', () {
    testWidgets('renders Hold to Record toggle inside the hotkey block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const KeyboardShortcutSection(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsOneWidget);
    });

    testWidgets('the Hold to Record row announces its toggled state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeTestable(
          const KeyboardShortcutSection(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettings(
                const AppSettings(
                  audioInput: AudioInputSettings(pushToTalk: true),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Every other toggle row in Settings carries hasToggledState; this one
      // was the exception until the audit. Skipped where the platform cannot
      // do key-up at all, because then the row genuinely has no state.
      final supportsKeyUp = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(hotkeyServiceProvider.notifier).supportsKeyUp;
      final row = tester.getSemantics(
        find.ancestor(
          of: find.text(l10n.settingsHoldToRecord),
          matching: find.byType(SettingRow),
        ),
      );
      // Both branches are asserted on purpose: a bare `if (supportsKeyUp)`
      // would pass having checked nothing on a host without key-up support,
      // which is the same hollow shape this audit twice had to repair.
      if (supportsKeyUp) {
        expect(
          row,
          matchesSemantics(
            label: l10n.settingsHoldToRecord,
            hint: l10n.onboardingTriggerModeHoldHint,
            hasToggledState: true,
            isToggled: true,
          ),
        );
      } else {
        // No key-up means no push-to-talk, so the row must claim no state
        // rather than a state its disabled switch would never accept.
        expect(
          row,
          matchesSemantics(
            label: l10n.settingsHoldToRecord,
            hint: l10n.onboardingTriggerModeToggleHint,
          ),
        );
      }
      handle.dispose();
    });

    testWidgets('a disabled hotkey takes the Change-hotkey button out of the '
        'tab order, not just out of the mouse\'s reach', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const KeyboardShortcutSection(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettings(
                const AppSettings(hotkey: HotkeySettings(hotkeyEnabled: false)),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The row is still rendered (dimmed to 40%), so finding it is not the
      // test — reaching it with the keyboard is.
      final button = find.text(l10n.settingsChangeHotkey);
      expect(button, findsOneWidget);

      // Behavioural, not structural: ExcludeFocus leaves the descendant Focus
      // widgets' own canRequestFocus untouched and blocks them from the node
      // tree instead, so asking the node to take focus is the only probe that
      // actually answers the question.
      final node = Focus.of(tester.element(button));
      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'Tab must not land on a control for a switched-off hotkey',
      );
    });
  });

  group('AudioSection', () {
    testWidgets('does NOT render Hold to Record toggle in audio block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const AudioSection(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsNothing);
    });
  });
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}
