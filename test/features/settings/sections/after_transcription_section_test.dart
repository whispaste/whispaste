/// Round-trip widget tests for [AfterTranscriptionSection].
///
/// Covers: dropdown round-trip (action → provider), and confirms that
/// the auto-paste delay slider and blocklist field are NOT rendered in
/// this section (slider removed; blocklist moved to AdvancedSection).
///
/// [PasteCapabilityNotifier] is faked to prevent OS-level paste-capability
/// probes when the section renders in paste mode.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

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

/// No-op paste capability notifier — prevents platform-channel calls in tests.
class _FakePasteCapabilityNotifier extends PasteCapabilityNotifier {
  @override
  PasteCapabilityState build() => const PasteCapabilityState();

  @override
  Future<void> check({bool prompt = false}) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

late L10n l10n;

AppSettings _settingsWithAction(AfterTranscriptionAction action) =>
    AppSettings.defaults.copyWithSections(
      afterTranscriptionSection: AfterTranscriptionSettings(
        afterTranscription: action.value,
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('AfterTranscriptionSection', () {
    // ── Slider removed ──────────────────────────────────────────────────────
    // The auto-paste delay slider was removed from this section (delay is
    // now fixed at 200 ms). It must not appear in ANY action mode.

    testWidgets('auto-paste delay slider never shown — clipboard mode', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        _settingsWithAction(AfterTranscriptionAction.clipboard),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('auto-paste delay slider never shown — nothing mode', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        _settingsWithAction(AfterTranscriptionAction.nothing),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('auto-paste delay slider never shown — paste mode', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        _settingsWithAction(AfterTranscriptionAction.paste),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [
            settingsProvider.overrideWith(() => notifier),
            pasteCapabilityNotifierProvider.overrideWith(
              () => _FakePasteCapabilityNotifier(),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets(
      'auto-paste delay slider never shown — clipboardAndPaste mode',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          _settingsWithAction(AfterTranscriptionAction.clipboardAndPaste),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: AfterTranscriptionSection()),
            overrides: [
              settingsProvider.overrideWith(() => notifier),
              pasteCapabilityNotifierProvider.overrideWith(
                () => _FakePasteCapabilityNotifier(),
              ),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Slider), findsNothing);
      },
    );

    // ── Blocklist removed from this section ─────────────────────────────────
    // The blocklist TextField was moved to AdvancedSection. It must not appear
    // in AfterTranscriptionSection even when paste mode is active.

    testWidgets('blocklist TextField not in this section — paste mode', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        _settingsWithAction(AfterTranscriptionAction.paste),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [
            settingsProvider.overrideWith(() => notifier),
            pasteCapabilityNotifierProvider.overrideWith(
              () => _FakePasteCapabilityNotifier(),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });

    // ── Dropdown round-trips ────────────────────────────────────────────────

    testWidgets('dropdown round-trip switches afterTranscription to paste', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        _settingsWithAction(AfterTranscriptionAction.clipboard),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [
            settingsProvider.overrideWith(() => notifier),
            // Mock needed because paste mode renders PasteCapabilityIndicator.
            pasteCapabilityNotifierProvider.overrideWith(
              () => _FakePasteCapabilityNotifier(),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();

      // "Auto-Paste at Cursor" = settingsAfterTranscriptionPaste
      await tester.tap(find.text(l10n.settingsAfterTranscriptionPaste).last);
      await tester.pumpAndSettle();

      expect(
        notifier.state.value!.afterTranscriptionSection.afterTranscription,
        AfterTranscriptionAction.paste.value,
      );
    });

    testWidgets('dropdown round-trip switches afterTranscription to nothing', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsAfterTranscriptionNothing).last);
      await tester.pumpAndSettle();

      expect(
        notifier.state.value!.afterTranscriptionSection.afterTranscription,
        AfterTranscriptionAction.nothing.value,
      );
    });

    // ── autoPasteDelay fixed at default ─────────────────────────────────────
    // Even though the slider is gone, the model field must still hold the
    // default 200 ms value (it was not dropped from the model).

    test('behavior.autoPasteDelay default is 200 ms', () {
      expect(AppSettings.defaults.behavior.autoPasteDelay, 200);
    });
  });
}
