/// Regression tests confirming that CloudProvidersSection has been removed
/// and that API-key fields are not duplicated anywhere in the settings UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/cloud_advanced_section.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('AdvancedSection', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(makeTestable(const AdvancedSection()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not contain any API-key fields', (tester) async {
      await tester.pumpWidget(makeTestable(const AdvancedSection()));
      await tester.pumpAndSettle();

      // No keyRound icon should appear in AdvancedSection.
      final icons = tester.widgetList<Icon>(find.byType(Icon));
      final hasKeyIcon = icons.any((i) => i.icon == LucideIcons.keyRound);
      expect(hasKeyIcon, isFalse);
    });
  });

  group('SpeechRecognitionSection — cloud mode shows exactly one API key', () {
    // Helper: wrap in a scrollable to prevent overflow in test scaffold.
    Widget scrollable(Widget child) => SingleChildScrollView(child: child);

    testWidgets('OpenAI selected → only one key field visible', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          scrollable(const SpeechRecognitionSection()),
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                AppSettings.defaults.copyWith(
                  sttProvider: SttProviderType.openAI.value,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final keyIcons = tester
          .widgetList<Icon>(find.byType(Icon))
          .where((i) => i.icon == LucideIcons.keyRound)
          .toList();
      expect(keyIcons.length, 1, reason: 'Exactly one key field for OpenAI');
    });

    testWidgets('Deepgram selected → only one key field visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          scrollable(const SpeechRecognitionSection()),
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                AppSettings.defaults.copyWith(
                  sttProvider: SttProviderType.deepgram.value,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final keyIcons = tester
          .widgetList<Icon>(find.byType(Icon))
          .where((i) => i.icon == LucideIcons.keyRound)
          .toList();
      expect(keyIcons.length, 1, reason: 'Exactly one key field for Deepgram');
    });

    testWidgets('On-device selected → no API key field shown', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          scrollable(const SpeechRecognitionSection()),
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                AppSettings.defaults.copyWith(
                  sttProvider: SttProviderType.onDevice.value,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final keyIcons = tester
          .widgetList<Icon>(find.byType(Icon))
          .where((i) => i.icon == LucideIcons.keyRound)
          .toList();
      expect(keyIcons, isEmpty, reason: 'No key field in local mode');
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal fake settings notifier for override
// ---------------------------------------------------------------------------

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier(this._value);

  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}
