/// Regression tests confirming that CloudProvidersSection has been removed
/// and that API-key fields are not duplicated anywhere in the settings UI.
/// Also confirms that the auto-paste blocklist field is present in AdvancedSection
/// (moved here from AfterTranscriptionSection).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show BehaviorSettings;
import 'package:whispaste/core/config/secure_key_store.dart'
    show SecureKeysNotRemovedException;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/cloud_advanced_section.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';
import 'package:whispaste/features/settings/widgets/auto_paste_blocklist_field.dart';

import '../../fixtures/test_helpers.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

/// Renders the blocklist field with an explicit detection capability, so each
/// platform variant can be checked on every host (AUF-1).
Widget _blocklistField({
  required bool detection,
  required String blocklist,
  bool copy = true,
  bool macOS = true,
}) {
  return makeTestable(
    SingleChildScrollView(
      child: AutoPasteBlocklistField(
        settings: AppSettings(
          behavior: BehaviorSettings(
            autoPasteBlocklist: blocklist,
            copyBlockedToClipboard: copy,
          ),
        ),
        targetDetectionAvailable: detection,
        isMacOS: macOS,
      ),
    ),
  );
}

void main() {
  group('copy-to-clipboard switch (maintainer 4a+c)', () {
    testWidgets(
      'the switch shows the stored value and carries its identifier',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _blocklistField(detection: true, blocklist: '', copy: false),
          );
          await tester.pumpAndSettle();
          final toggle = tester.widget<Switch>(
            find.byKey(const Key('text-auto-paste-blocklist-copy-toggle')),
          );
          expect(toggle.value, isFalse);
          expect(
            find.bySemanticsIdentifier('text-auto-paste-blocklist-copy-toggle'),
            findsOneWidget,
          );
        } finally {
          handle.dispose();
        }
      },
    );

    test('defaults to on and round-trips through storage', () {
      expect(const BehaviorSettings().copyBlockedToClipboard, isTrue);
      final restored = BehaviorSettings.fromMap(
        const BehaviorSettings(copyBlockedToClipboard: false).toMap(),
      );
      expect(restored.copyBlockedToClipboard, isFalse);
    });
  });

  group('auto-paste blocklist hint per platform variant (AUF-1)', () {
    const hintId = 'text-auto-paste-blocklist-no-detection-hint';
    const warningKey = Key('text-auto-paste-blocklist-short-prefix-warning');

    // Windows and Linux today, and Wayland later: no target detection yet.
    testWidgets('without detection the hint is shown and no warning', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _blocklistField(detection: false, blocklist: ''),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(hintId), findsOneWidget);
        expect(find.byKey(warningKey), findsNothing);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('without detection the hint stays with a short entry', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _blocklistField(detection: false, blocklist: 'Safari'),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(hintId), findsOneWidget);
        expect(find.byKey(warningKey), findsNothing);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('with detection (macOS) the hint disappears', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _blocklistField(detection: true, blocklist: 'com.apple.Terminal'),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(hintId), findsNothing);
        expect(find.byKey(warningKey), findsNothing);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('with detection a short macOS entry shows the warning', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _blocklistField(detection: true, blocklist: 'Safari'),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(hintId), findsNothing);
        expect(find.byKey(warningKey), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
      'with detection on Windows or Linux a short name is no warning',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _blocklistField(detection: true, blocklist: 'Safari', macOS: false),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(warningKey), findsNothing);
        } finally {
          handle.dispose();
        }
      },
    );
  });

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

    testWidgets('blocklist TextField moved out of AdvancedSection (spec #69)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SingleChildScrollView(child: AdvancedSection())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });
  });

  group('AdvancedSection — reset to defaults reports API keys', () {
    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

    Future<void> pumpAndConfirmReset(
      WidgetTester tester,
      SettingsNotifier notifier,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AdvancedSection()),
          locale: const Locale('en'),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();
      // First match is the row trigger, the last one the dialog's confirm.
      await tester.tap(find.text(l10n.settingsResetConfirm).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsResetConfirm).last);
      await tester.pumpAndSettle();
    }

    testWidgets('partial key failure shows the error toast', (tester) async {
      await pumpAndConfirmReset(
        tester,
        _ResetNotifier(
          failure: const SecureKeysNotRemovedException(['openaiApiKey']),
        ),
      );

      expect(find.text(l10n.settingsSecureKeysNotRemoved), findsOneWidget);
      expect(find.text(l10n.settingsResetSuccess), findsNothing);
      // Let the 8 s error toast expire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('complete reset stays silent about keys', (tester) async {
      await pumpAndConfirmReset(tester, _ResetNotifier());

      expect(find.text(l10n.settingsSecureKeysNotRemoved), findsNothing);
      expect(find.text(l10n.settingsResetSuccess), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
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

      final keyRows = tester
          .widgetList<WpSettingsRow>(find.byType(WpSettingsRow))
          .where(
            (r) =>
                r.rowId == 'speech-openai-key' ||
                r.rowId == 'speech-deepgram-key' ||
                r.rowId == 'text-smart-mode-key',
          )
          .toList();
      expect(keyRows.length, 1, reason: 'Exactly one key field for OpenAI');
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

      final keyRows = tester
          .widgetList<WpSettingsRow>(find.byType(WpSettingsRow))
          .where(
            (r) =>
                r.rowId == 'speech-openai-key' ||
                r.rowId == 'speech-deepgram-key' ||
                r.rowId == 'text-smart-mode-key',
          )
          .toList();
      expect(keyRows.length, 1, reason: 'Exactly one key field for Deepgram');
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

/// Notifier whose reset either succeeds or fails with a partial key failure.
class _ResetNotifier extends SettingsNotifier {
  _ResetNotifier({this.failure});

  final SecureKeysNotRemovedException? failure;

  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> resetToDefaults() async {
    final error = failure;
    if (error != null) throw error;
  }
}

/// Read-only fake — used by SpeechRecognitionSection tests.
class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier(this._value);

  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}
