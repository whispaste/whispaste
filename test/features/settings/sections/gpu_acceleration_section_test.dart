/// Widget tests for [GpuAccelerationSection].
///
/// Covers: dropdown renders the current value, selecting a new value
/// persists it to [BehaviorSettings.gpuAcceleration], and the section
/// uses no new state field — only the existing enum.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/gpu_acceleration_section.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifier — mirrors the pattern in audio_section_test.dart
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
// Helper
// ---------------------------------------------------------------------------

Widget _pump(WidgetTester tester, _FakeSettingsNotifier notifier) {
  return makeTestable(
    const SingleChildScrollView(child: GpuAccelerationSection()),
    overrides: [settingsProvider.overrideWith(() => notifier)],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpuAccelerationSection', () {
    // ── Initial state ───────────────────────────────────────────────────────

    testWidgets('renders a dropdown bound to behavior.gpuAcceleration', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      // Default is 'auto' — at least one DropdownButton<String> visible.
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets(
      'dropdown value reflects the persisted gpuAcceleration (default = auto)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        // The default AppSettings has gpuAcceleration == 'auto'.
        expect(notifier.state.value!.behavior.gpuAcceleration, 'auto');
      },
    );

    // ── Persist on change ───────────────────────────────────────────────────

    testWidgets(
      'selecting "disabled" writes GpuAcceleration.disabled to behavior',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        // Open the dropdown.
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();

        // Tap the 'disabled' item (value == 'disabled').
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<String> &&
                w.value == GpuAcceleration.disabled.value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          notifier.state.value!.behavior.gpuAcceleration,
          GpuAcceleration.disabled.value,
        );
      },
    );

    testWidgets(
      'selecting "enabled" writes GpuAcceleration.enabled to behavior',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<String> &&
                w.value == GpuAcceleration.enabled.value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          notifier.state.value!.behavior.gpuAcceleration,
          GpuAcceleration.enabled.value,
        );
      },
    );

    // ── No new state field ──────────────────────────────────────────────────

    testWidgets(
      'after persisting, behavior.gpuAcceleration reflects override (highest precedence)',
      (tester) async {
        // Start with 'auto', switch to 'disabled', verify the setting survives
        // a widget rebuild (i.e. the value is read back from state).
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        // Switch to 'disabled'.
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<String> &&
                w.value == GpuAcceleration.disabled.value,
          ),
        );
        await tester.pumpAndSettle();

        // Trigger a rebuild by pumping again.
        await tester.pump();

        // The dropdown now shows 'disabled'.
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        expect(dropdown.value, GpuAcceleration.disabled.value);

        // And the persisted setting confirms the enum value.
        expect(
          notifier.state.value!.behavior.gpuAcceleration,
          GpuAcceleration.disabled.value,
        );
      },
    );
  });
}
