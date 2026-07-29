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
import 'package:whispaste/services/paste/paster.dart';

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
///
/// [requestGrant] is overridden (not left to fall through to the real
/// base-class implementation) so tests can assert the auto-trigger fired
/// without arming real timers or hitting the `url_launcher` channel.
class _FakePasteCapabilityNotifier extends PasteCapabilityNotifier {
  _FakePasteCapabilityNotifier({this.initialCapability});

  final PasteCapability? initialCapability;
  int requestGrantCalls = 0;

  @override
  PasteCapabilityState build() =>
      PasteCapabilityState(capability: initialCapability);

  @override
  Future<void> check({bool prompt = false}) async {}

  @override
  Future<void> requestGrant({
    Duration pollInterval = const Duration(seconds: 1),
    Duration pollTimeout = const Duration(seconds: 30),
  }) async {
    requestGrantCalls++;
  }
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

    // ── Activation-triggered permission request ─────────────────────────────
    // Selecting a paste-requiring option must request the OS permission
    // immediately (PasteCapabilityNotifier.requestGrant) instead of leaving
    // the user to notice and tap the indicator's own "Grant" button below.

    testWidgets(
      'selecting Auto-Paste requests the permission grant when not yet ready',
      (tester) async {
        final settings = _FakeSettingsNotifier(
          _settingsWithAction(AfterTranscriptionAction.clipboard),
        );
        final capability = _FakePasteCapabilityNotifier(
          initialCapability: const PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: AfterTranscriptionSection()),
            overrides: [
              settingsProvider.overrideWith(() => settings),
              pasteCapabilityNotifierProvider.overrideWith(() => capability),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.settingsAfterTranscriptionPaste).last);
        await tester.pumpAndSettle();

        expect(capability.requestGrantCalls, 1);
      },
    );

    testWidgets(
      'selecting Auto-Paste does not re-request the grant when already ready',
      (tester) async {
        final settings = _FakeSettingsNotifier(
          _settingsWithAction(AfterTranscriptionAction.clipboard),
        );
        final capability = _FakePasteCapabilityNotifier(
          initialCapability: const PasteCapability(
            status: PasteCapabilityStatus.ready,
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: AfterTranscriptionSection()),
            overrides: [
              settingsProvider.overrideWith(() => settings),
              pasteCapabilityNotifierProvider.overrideWith(() => capability),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.settingsAfterTranscriptionPaste).last);
        await tester.pumpAndSettle();

        expect(capability.requestGrantCalls, 0);
      },
    );

    // ── autoPasteDelay fixed at default ─────────────────────────────────────
    // Even though the slider is gone, the model field must still hold the
    // default 200 ms value (it was not dropped from the model).

    test('behavior.autoPasteDelay default is 200 ms', () {
      expect(AppSettings.defaults.behavior.autoPasteDelay, 200);
    });

    // ── Mac App Store gating ─────────────────────────────────────────────────
    // When auto-paste isn't supported (Mac App Store build), the paste-based
    // options don't exist as choices at all — greying them out with a
    // tooltip would look like a bug to users who don't know they're running
    // a store build. See docs/store-release.md.

    testWidgets(
      'paste/clipboardAndPaste options are absent when autoPasteSupported is false',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          _settingsWithAction(AfterTranscriptionAction.clipboard),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(
              child: AfterTranscriptionSection(autoPasteSupported: false),
            ),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsAfterTranscriptionPaste), findsNothing);
        expect(find.text(l10n.settingsAfterTranscriptionBoth), findsNothing);
        expect(
          find.text(l10n.settingsAfterTranscriptionClipboard),
          findsWidgets,
        );
        expect(find.text(l10n.settingsAfterTranscriptionNothing), findsWidgets);
      },
    );

    testWidgets(
      'a persisted paste preference displays as clipboard when autoPasteSupported is false',
      (tester) async {
        // Simulates a setting carried over from a non-MAS install (or a
        // pre-fix default) — the runtime already downgrades this to
        // clipboard behavior (paste_policy.dart); the dropdown must show
        // the same resolved value rather than pointing at an option that
        // isn't in the list.
        final notifier = _FakeSettingsNotifier(
          _settingsWithAction(AfterTranscriptionAction.paste),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(
              child: AfterTranscriptionSection(autoPasteSupported: false),
            ),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>).first,
        );
        expect(dropdown.value, AfterTranscriptionAction.clipboard.value);
      },
    );

    testWidgets(
      'paste/clipboardAndPaste options are present when autoPasteSupported is true',
      (tester) async {
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

        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();

        final pasteItem = tester.widget<DropdownMenuItem<String>>(
          find.ancestor(
            of: find.text(l10n.settingsAfterTranscriptionPaste).last,
            matching: find.byType(DropdownMenuItem<String>),
          ),
        );

        expect(pasteItem.enabled, isTrue);
      },
    );
  });
}
