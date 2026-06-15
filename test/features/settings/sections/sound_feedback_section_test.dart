/// Round-trip widget tests for [SoundFeedbackSection].
///
/// Covers: a single "Sounds" master toggle (replaces the four individual
/// sound toggles) plus the volume slider (only visible when master is ON).
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
    // ── Master toggle visibility ─────────────────────────────────────────────

    testWidgets(
      'single "Sounds" master toggle is visible (four individual toggles are not)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        // Only one Switch should be visible (master + volume slider which is a Slider, not Switch).
        expect(find.byType(Switch), findsOneWidget);
      },
    );

    // ── Toggle OFF → all four false ──────────────────────────────────────────

    testWidgets(
      'tapping master toggle OFF sets all four sound fields to false',
      (tester) async {
        // Start with all sounds enabled (defaults).
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        // Master is ON (all four defaults = true). Tap to turn OFF.
        await tester.tap(find.byType(Switch).first);
        await tester.pump();

        final sound = notifier.state.value!.sound;
        expect(sound.recordStartSound, isFalse);
        expect(sound.recordStopSound, isFalse);
        expect(sound.transcriptionCompleteSound, isFalse);
        expect(sound.durationWarningSound, isFalse);
      },
    );

    // ── Toggle ON → all four true ────────────────────────────────────────────

    testWidgets('tapping master toggle ON sets all four sound fields to true', (
      tester,
    ) async {
      // Start with all sounds disabled.
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          sound: const SoundSettings(
            recordStartSound: false,
            recordStopSound: false,
            transcriptionCompleteSound: false,
            durationWarningSound: false,
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

      // Master is OFF. Tap to turn ON.
      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      final sound = notifier.state.value!.sound;
      expect(sound.recordStartSound, isTrue);
      expect(sound.recordStopSound, isTrue);
      expect(sound.transcriptionCompleteSound, isTrue);
      expect(sound.durationWarningSound, isTrue);
    });

    // ── Derived initial state: mixed config with ≥1 active → master ON ───────

    testWidgets(
      'master derives ON when at least one sound field is true (mixed config)',
      (tester) async {
        // Only one sound enabled — master should show as ON.
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            sound: const SoundSettings(
              recordStartSound: true,
              recordStopSound: false,
              transcriptionCompleteSound: false,
              durationWarningSound: false,
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

        final masterSwitch = tester.widget<Switch>(find.byType(Switch).first);
        expect(masterSwitch.value, isTrue);
      },
    );

    // ── Volume control visibility ────────────────────────────────────────────

    testWidgets('volume slider is visible when master is ON', (tester) async {
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

    testWidgets('volume slider is hidden when master is OFF', (tester) async {
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          sound: const SoundSettings(
            recordStartSound: false,
            recordStopSound: false,
            transcriptionCompleteSound: false,
            durationWarningSound: false,
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

      expect(find.byType(Slider), findsNothing);
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
