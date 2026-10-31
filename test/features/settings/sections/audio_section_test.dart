/// Round-trip widget tests for [AudioSection].
///
/// Covers: microphone selector visibility (real vs. default-only devices),
/// gain slider round-trip, clipping banner show/hide/dismiss.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/recording/clipping_state.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';
import 'package:whispaste/services/audio_service.dart';

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

class _FakeClippingNotifier extends ClippingStateNotifier {
  _FakeClippingNotifier(this._initial);
  final ClippingState _initial;

  @override
  ClippingState build() => _initial;
  // dismiss() from base class mutates state correctly — no override needed.
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Object> _overrides({
  required _FakeSettingsNotifier settings,
  List<String> devices = const ['Default'],
  ClippingState clipping = const ClippingState(),
}) {
  return [
    settingsProvider.overrideWith(() => settings),
    audioInputDevicesProvider.overrideWith((ref) async => devices),
    clippingStateProvider.overrideWith(() => _FakeClippingNotifier(clipping)),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioSection', () {
    // ── Microphone selector ─────────────────────────────────────────────────

    testWidgets(
      'shows static system-default label when only one device available',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: AudioSection()),
            overrides: _overrides(settings: notifier, devices: ['Default']),
          ),
        );
        await tester.pumpAndSettle();

        // Only one device → dropdown is suppressed, no DropdownButton in tree.
        expect(find.byType(DropdownButton<String>), findsNothing);
      },
    );

    testWidgets('shows microphone dropdown when real devices are enumerated', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AudioSection()),
          overrides: _overrides(
            settings: notifier,
            devices: ['Default', 'Built-in Microphone'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    // ── Gain slider ─────────────────────────────────────────────────────────

    testWidgets('gain slider round-trip updates audioInput.inputGain', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AudioSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      final initialGain = notifier.state.value!.audioInput.inputGain;

      // Slider range 0–300 (values) / 180 px wide. Center = 90 px = 150 units.
      // Dragging +60 px → 150 px → 150/180*300 = 250 → nearest div-5 = 250.
      // 250 ≠ 100 (default), so inputGain = 2.5 ≠ 1.0.
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pump();

      expect(notifier.state.value!.audioInput.inputGain, isNot(initialGain));
    });

    // ── Clipping banner ─────────────────────────────────────────────────────

    testWidgets(
      'clipping banner hidden when no clipping occurred (count = 0)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: AudioSection()),
            overrides: _overrides(
              settings: notifier,
              clipping: const ClippingState(count: 0),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // alertTriangle icon lives only in the clipping banner.
        expect(find.byIcon(LucideIcons.alertTriangle), findsNothing);
      },
    );

    testWidgets('clipping banner visible when clipping occurred (count > 0)', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AudioSection()),
          overrides: _overrides(
            settings: notifier,
            clipping: ClippingState(
              count: 42,
              recordingFinishedAt: DateTime.now(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.alertTriangle), findsOneWidget);
    });

    testWidgets('clipping banner disappears after tapping dismiss', (
      tester,
    ) async {
      final clippingNotifier = _FakeClippingNotifier(
        ClippingState(count: 10, recordingFinishedAt: DateTime.now()),
      );
      final settingsNotifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AudioSection()),
          overrides: [
            settingsProvider.overrideWith(() => settingsNotifier),
            audioInputDevicesProvider.overrideWith((ref) async => ['Default']),
            clippingStateProvider.overrideWith(() => clippingNotifier),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Confirm banner is visible.
      expect(find.byIcon(LucideIcons.alertTriangle), findsOneWidget);

      // Tap dismiss (×).
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();

      // Banner gone — count reset to 0.
      expect(find.byIcon(LucideIcons.alertTriangle), findsNothing);
    });
  });
}
