/// Round-trip widget tests for [SoundFeedbackSection].
///
/// Covers: volume slider always visible; `soundVolume == 0` is the off-state
/// (slider shows "Aus" / "Off"); `soundVolume > 0` is the on-state.
/// The "Sounds enabled" master toggle has been removed — volume alone controls
/// whether sounds play.
///
/// [SoundFeedbackService] is faked out to prevent real audio engine
/// initialisation in headless test environments.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/services/sound_feedback_service.dart';

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

/// No-op sound service — skips SoLoud engine init in tests.
class _FakeSoundFeedbackService extends SoundFeedbackService {
  @override
  void build() {}

  @override
  Future<void> playVolumePreview(double volume) async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Object> buildOverrides(_FakeSettingsNotifier notifier) => [
    settingsProvider.overrideWith(() => notifier),
    soundFeedbackProvider.overrideWith(() => _FakeSoundFeedbackService()),
  ];

  group('SoundFeedbackSection', () {
    // ── No master toggle ─────────────────────────────────────────────────────

    testWidgets(
      'no "Sounds enabled" master toggle — no Switch widget rendered',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Switch), findsNothing);
      },
    );

    // ── Slider always visible ────────────────────────────────────────────────

    testWidgets('volume slider is visible at default settings (volume 80)', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SoundFeedbackSection()),
          overrides: buildOverrides(notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets(
      'volume slider is visible even when soundVolume is 0 (off state)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            sound: const SoundSettings(soundVolume: 0),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Slider), findsOneWidget);
      },
    );

    testWidgets(
      'volume slider is visible when all four sound bools are false',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            sound: const SoundSettings(
              recordStartSound: false,
              recordStopSound: false,
              transcriptionCompleteSound: false,
              durationWarningSound: false,
              soundVolume: 0,
            ),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Slider), findsOneWidget);
      },
    );

    // ── "Aus" / "Off" label at volume 0 ─────────────────────────────────────

    testWidgets(
      'slider value label shows "Aus" (de) or "Off" (en) at volume 0',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            sound: const SoundSettings(soundVolume: 0),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        // The test locale in makeTestable is 'en', so expect "Off".
        expect(find.text('Off'), findsOneWidget);
      },
    );

    testWidgets('slider value label shows percentage at volume > 0', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults); // volume 80
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SoundFeedbackSection()),
          overrides: buildOverrides(notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('80%'), findsOneWidget);
      expect(find.text('Off'), findsNothing);
    });

    // ── Volume slider round-trip ─────────────────────────────────────────────

    testWidgets('volume slider round-trip updates sound.soundVolume', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SoundFeedbackSection()),
          overrides: buildOverrides(notifier),
        ),
      );
      await tester.pumpAndSettle();

      final initialVolume = notifier.state.value!.sound.soundVolume;
      // Default = 80. Range 0–100, div 20 (step 5), slider 180 px wide.
      // Drag left: center (90 px) − 60 px = 30 px → 30/180*100 ≈ 16.7 → 15.
      // 15 ≠ 80, so state must change.
      await tester.drag(find.byType(Slider).first, const Offset(-60, 0));
      await tester.pump();

      expect(notifier.state.value!.sound.soundVolume, isNot(initialVolume));
    });
  });
}
