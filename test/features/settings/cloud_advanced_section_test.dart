/// Regression tests confirming that CloudProvidersSection has been removed
/// and that API-key fields are not duplicated anywhere in the settings UI.
/// Also confirms that the auto-paste blocklist field is present in AdvancedSection
/// (moved here from AfterTranscriptionSection).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
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

    // ── Blocklist moved here from AfterTranscriptionSection ─────────────────

    testWidgets('blocklist TextField is visible in AdvancedSection', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SingleChildScrollView(child: AdvancedSection())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('blocklist TextField round-trip updates autoPasteBlocklist', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AdvancedSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'com.example.blocked');
      // Wait for the debounce timer.
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        notifier.state.value!.behavior.autoPasteBlocklist,
        'com.example.blocked',
      );
    });

    // ── Settings portability (export/import) entry ──────────────────────
    //
    // Only structural/render coverage lives here — tapping either button
    // resolves a real Downloads/Documents directory via `path_provider`,
    // which hangs in `flutter_test` without a platform-channel mock. The
    // actual export/import/round-trip behaviour is covered by
    // `test/services/settings_portability_controller_test.dart` and
    // `test/services/settings_portability_service_test.dart` against
    // injected fakes, per this issue's testing guidance.

    testWidgets(
      'renders the Export/Import Settings entry with both action buttons',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: AdvancedSection()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Export / Import Settings'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Export'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Import'), findsOneWidget);
      },
    );
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
// Fake settings notifiers for override
// ---------------------------------------------------------------------------

/// Read-only fake — used by SpeechRecognitionSection tests.
class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier(this._value);

  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// Mutable fake — used by AdvancedSection round-trip tests.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}
