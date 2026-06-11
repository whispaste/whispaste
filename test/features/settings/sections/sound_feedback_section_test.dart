/// Round-trip widget tests for [SoundFeedbackSection].
///
/// Covers: record-start, record-stop, transcription-complete, and
/// duration-warning sound toggles plus the volume slider.
///
/// [SoundFeedbackService] is faked out to prevent real audio engine
/// initialisation in headless test environments.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
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
    // ── Toggle: record start ────────────────────────────────────────────────

    testWidgets(
      'record-start sound toggle round-trip flips sound.recordStartSound',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        // Default = true; Switch at index 0 = recordStartSound.
        expect(notifier.state.value!.sound.recordStartSound, isTrue);
        await tester.tap(find.byType(Switch).at(0));
        await tester.pump();
        expect(notifier.state.value!.sound.recordStartSound, isFalse);
      },
    );

    // ── Toggle: record stop ─────────────────────────────────────────────────

    testWidgets(
      'record-stop sound toggle round-trip flips sound.recordStopSound',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(notifier.state.value!.sound.recordStopSound, isTrue);
        await tester.tap(find.byType(Switch).at(1));
        await tester.pump();
        expect(notifier.state.value!.sound.recordStopSound, isFalse);
      },
    );

    // ── Toggle: transcription complete ──────────────────────────────────────

    testWidgets(
      'transcription-complete toggle round-trip flips sound.transcriptionCompleteSound',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(notifier.state.value!.sound.transcriptionCompleteSound, isTrue);
        await tester.tap(find.byType(Switch).at(2));
        await tester.pump();
        expect(notifier.state.value!.sound.transcriptionCompleteSound, isFalse);
      },
    );

    // ── Toggle: duration warning ────────────────────────────────────────────

    testWidgets(
      'duration-warning sound toggle round-trip flips sound.durationWarningSound',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SoundFeedbackSection()),
            overrides: buildOverrides(notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(notifier.state.value!.sound.durationWarningSound, isTrue);
        await tester.tap(find.byType(Switch).at(3));
        await tester.pump();
        expect(notifier.state.value!.sound.durationWarningSound, isFalse);
      },
    );

    // ── Volume slider ───────────────────────────────────────────────────────

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
