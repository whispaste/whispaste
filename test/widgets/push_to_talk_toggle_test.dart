/// Widget tests for the Push-to-Talk toggle in KeyboardShortcutSection.
///
/// Verifies AC5: when [HotkeyService.supportsKeyUp] is false, the toggle
/// is disabled and a tooltip with [L10n.pushToTalkUnavailableTooltip] is shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/services/hotkey_service.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake registrar that controls supportsKeyUp
// ---------------------------------------------------------------------------

class _FakeRegistrar implements HotKeyRegistrar {
  _FakeRegistrar({required this.supportsKeyUp});

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [HotkeyService] with [supportsKeyUp] faked.
HotkeyService _fakeHotkeyService({required bool supportsKeyUp}) {
  final svc = HotkeyService();
  svc.injectRegistrar(_FakeRegistrar(supportsKeyUp: supportsKeyUp));
  return svc;
}

Widget _makeSection({required bool supportsKeyUp}) {
  final fakeSvc = _fakeHotkeyService(supportsKeyUp: supportsKeyUp);

  return makeTestable(
    const KeyboardShortcutSection(),
    overrides: [hotkeyServiceProvider.overrideWith(() => fakeSvc)],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Push-to-Talk toggle — platform support (AC5)', () {
    testWidgets('supportsKeyUp=false: Switch is disabled (onChanged=null)', (
      tester,
    ) async {
      await tester.pumpWidget(_makeSection(supportsKeyUp: false));
      await tester.pump();

      final switchWidget = tester
          .widgetList<Switch>(find.byType(Switch))
          .firstWhere(
            (s) => s.onChanged == null,
            orElse: () => throw TestFailure(
              'Expected at least one disabled Switch (onChanged == null)',
            ),
          );

      expect(
        switchWidget.onChanged,
        isNull,
        reason: 'Toggle must be disabled when supportsKeyUp=false',
      );
    });

    testWidgets(
      'supportsKeyUp=false: Tooltip with unavailable message is present',
      (tester) async {
        await tester.pumpWidget(_makeSection(supportsKeyUp: false));
        await tester.pump();

        // Find tooltip with the correct message.
        final tooltips = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .where(
              (t) =>
                  t.message != null &&
                  t.message!.contains('Not available on this platform'),
            )
            .toList();

        expect(
          tooltips,
          isNotEmpty,
          reason: 'A Tooltip with "Not available on this platform" must exist',
        );
      },
    );

    testWidgets('supportsKeyUp=true: Switch is enabled (onChanged is set)', (
      tester,
    ) async {
      await tester.pumpWidget(_makeSection(supportsKeyUp: true));
      await tester.pump();

      // There should be no disabled Switch for the PTT row specifically.
      // We just verify the section renders without a null-onChanged Switch
      // for that toggle.
      final allSwitches = tester.widgetList<Switch>(find.byType(Switch));
      // At least the PTT switch should exist and have a non-null callback.
      expect(
        allSwitches.any((s) => s.onChanged != null),
        isTrue,
        reason:
            'At least one enabled Switch must exist when supportsKeyUp=true',
      );
    });
  });
}
