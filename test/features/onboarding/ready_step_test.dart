/// Widget tests for [ReadyStep] (onboarding step 4) — specifically the
/// step-3 wording, which must react to the user's Auto-Paste decision.
///
/// External behaviour only: we seed `AfterTranscriptionSettings` through a
/// fake [SettingsNotifier] and assert the rendered step-3 text. The shared
/// hotkey display and other UI bits are not exercised here — they already
/// have coverage upstream.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/steps/ready_step.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

void _noop() {}

Future<void> _pumpStep(
  WidgetTester tester, {
  required _FakeSettingsNotifier settings,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(
        child: ReadyStep(onComplete: _noop, onBack: _noop),
      ),
      size: const Size(1280, 980),
      overrides: [settingsProvider.overrideWith(() => settings)],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadyStep — step 3 wording reacts to Auto-Paste setting', () {
    testWidgets(
      'Auto-Paste on (afterTranscription == paste) → step 3 shows Auto-Paste wording, '
      'NOT the Copy-Only / ⌘V hint',
      (tester) async {
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
          ),
        );

        await _pumpStep(tester, settings: settings);

        expect(
          find.textContaining('Text flows straight into the active app'),
          findsOneWidget,
          reason:
              'Auto-Paste users must see the active-app wording, not the '
              'clipboard fallback hint.',
        );
        expect(
          find.textContaining('Ctrl+V'),
          findsNothing,
          reason:
              'When Auto-Paste fires automatically, the manual ⌘V / Ctrl+V '
              'hint must not appear.',
        );
      },
    );

    testWidgets(
      'Auto-Paste off (afterTranscription == clipboard) → step 3 shows '
      'Copy-Only wording with the ⌘V / Ctrl+V hint',
      (tester) async {
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'clipboard',
            ),
          ),
        );

        await _pumpStep(tester, settings: settings);

        expect(
          find.textContaining('Text is in your clipboard'),
          findsOneWidget,
          reason:
              'Skip-Auto-Paste users must see the clipboard wording so they '
              'know the transcript is parked there.',
        );
        expect(
          find.textContaining('Ctrl+V'),
          findsOneWidget,
          reason:
              'Copy-Only wording must include the manual paste hint so users '
              'know how to retrieve the transcript.',
        );
        expect(
          find.textContaining('Text flows straight into the active app'),
          findsNothing,
          reason:
              'The Auto-Paste wording must not appear when Auto-Paste is off.',
        );
      },
    );

    testWidgets(
      'Auto-Paste on via clipboard_and_paste → step 3 also shows Auto-Paste wording',
      (tester) async {
        // The `clipboard_and_paste` mode still injects keystrokes, so the
        // step-3 hint must match the `paste` case rather than the Copy-Only
        // fallback.
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'clipboard_and_paste',
            ),
          ),
        );

        await _pumpStep(tester, settings: settings);

        expect(
          find.textContaining('Text flows straight into the active app'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Auto-Paste off via nothing → step 3 shows Copy-Only wording', (
      tester,
    ) async {
      // `nothing` leaves the transcript on the clipboard too (the app
      // never auto-pastes), so Copy-Only wording with the ⌘V hint is the
      // right fallback even though no copy fires automatically — the
      // wording matches the actionable user step.
      final settings = _FakeSettingsNotifier(
        const AppSettings(
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
        ),
      );

      await _pumpStep(tester, settings: settings);

      expect(find.textContaining('Text is in your clipboard'), findsOneWidget);
      expect(find.textContaining('Ctrl+V'), findsOneWidget);
    });
  });
}
