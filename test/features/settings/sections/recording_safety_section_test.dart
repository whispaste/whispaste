/// Round-trip widget tests for [RecordingSafetySection].
///
/// Covers: dead-mic timeout slider, auto-stop-silence slider,
/// and max-record-duration slider — all three round-trips through
/// [settingsProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingSafetySection', () {
    testWidgets('renders three sliders', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: RecordingSafetySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNWidgets(3));
    });

    // ── Dead mic timeout ────────────────────────────────────────────────────

    testWidgets(
      'dead-mic timeout slider round-trip updates recordingSafety.deadMicTimeout',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            recordingSafety: const RecordingSafetySettings(
              deadMicTimeout: 3.0,
              autoStopSilence: 0.0,
            ),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: RecordingSafetySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        final initial = notifier.state.value!.recordingSafety.deadMicTimeout;

        // Slider 0 = deadMicTimeout. Range 0–10, width 180 px.
        // Center (90 px) + 60 px = 150 px → 150/180*10 = 8.33 → div-1 = 8.0 ≠ 3.0.
        await tester.drag(find.byType(Slider).at(0), const Offset(60, 0));
        await tester.pump();

        expect(
          notifier.state.value!.recordingSafety.deadMicTimeout,
          isNot(initial),
        );
      },
    );

    // ── Auto stop silence ───────────────────────────────────────────────────

    testWidgets(
      'auto-stop-silence slider round-trip updates recordingSafety.autoStopSilence',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        // Default autoStopSilence = 0.0
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: RecordingSafetySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        // Slider 1 = autoStopSilence. Center + 60 px → value ≈ 8.0 > 0.0.
        await tester.drag(find.byType(Slider).at(1), const Offset(60, 0));
        await tester.pump();

        expect(
          notifier.state.value!.recordingSafety.autoStopSilence,
          greaterThan(0.0),
        );
      },
    );

    // ── Max record duration ─────────────────────────────────────────────────

    testWidgets(
      'max-record-duration slider round-trip updates behavior.maxRecordDuration',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        // Default maxRecordDuration = 120
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: RecordingSafetySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
          ),
        );
        await tester.pumpAndSettle();

        final initial = notifier.state.value!.behavior.maxRecordDuration;

        // Slider 2 = maxRecordDuration. Range 0–600, div 20 (step 30).
        // Center 90 px + 60 px = 150 px → 150/180*600 = 500 → div-30 = 510 ≠ 120.
        await tester.drag(find.byType(Slider).at(2), const Offset(60, 0));
        await tester.pump();

        expect(
          notifier.state.value!.behavior.maxRecordDuration,
          isNot(initial),
        );
      },
    );
  });
}
