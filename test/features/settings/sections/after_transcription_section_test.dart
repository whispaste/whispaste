/// Round-trip widget tests for [AfterTranscriptionSection].
///
/// Covers: dropdown round-trip (action → provider), conditional visibility
/// of the auto-paste delay slider (only shown for paste / clipboard_and_paste),
/// and the delay slider round-trip.
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
    // ── Conditional visibility ──────────────────────────────────────────────

    testWidgets('auto-paste delay slider hidden for clipboard mode', (
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

      // No Slider visible in clipboard-only mode.
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('auto-paste delay slider hidden for nothing mode', (
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

    testWidgets('auto-paste delay slider visible for paste mode', (
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

      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('auto-paste delay slider visible for clipboardAndPaste mode', (
      tester,
    ) async {
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

      expect(find.byType(Slider), findsOneWidget);
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

    // ── Delay slider ────────────────────────────────────────────────────────

    testWidgets(
      'auto-paste delay slider round-trip updates behavior.autoPasteDelay',
      (tester) async {
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

        final initialDelay = notifier.state.value!.behavior.autoPasteDelay;

        // Slider range 0–2000, div 20 (step 100), width 180 px.
        // Center (90 px) + 60 px = 150 px → 150/180*2000 = 1667 → 1700 ≠ 200.
        await tester.drag(find.byType(Slider).first, const Offset(60, 0));
        await tester.pump();

        expect(
          notifier.state.value!.behavior.autoPasteDelay,
          isNot(initialDelay),
        );
      },
    );
  });
}
