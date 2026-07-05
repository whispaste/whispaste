/// Tests confirming:
/// - [shouldMinimize] is a pure decision function extracted from
///   `_initDesktopWindow()` (Block A, Slice 01) covering every combination of
///   autostart setting, minimize setting, the `--autostart` CLI argument, and
///   the (not-yet-wired, Slice 03) macOS Login-Item signal.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/main.dart' hide main;

void main() {
  AppSettings settingsWith({
    required bool launchAtStartup,
    required bool startMinimized,
  }) {
    return AppSettings(
      interface_: InterfaceSettings(
        launchAtStartup: launchAtStartup,
        startMinimized: startMinimized,
      ),
    );
  }

  group('shouldMinimize', () {
    // AC: table-driven coverage of every combination of
    // launchAtStartup / startMinimized / --autostart arg / macOS Login-Item
    // signal (true/false/unknown=null).
    final cases =
        <
          ({
            String description,
            bool launchAtStartup,
            bool startMinimized,
            bool autostartArg,
            bool? macosLoginItemSignal,
            bool expected,
          })
        >[
          // ── Baseline: no autostart signal at all → never minimize, regardless
          // of settings. ─────────────────────────────────────────────────────
          (
            description: 'no settings, no args, no macOS signal',
            launchAtStartup: false,
            startMinimized: false,
            autostartArg: false,
            macosLoginItemSignal: null,
            expected: false,
          ),
          (
            description: 'both settings on, but no autostart signal at all',
            launchAtStartup: true,
            startMinimized: true,
            autostartArg: false,
            macosLoginItemSignal: null,
            expected: false,
          ),
          (
            description: 'both settings on, macOS signal explicitly false',
            launchAtStartup: true,
            startMinimized: true,
            autostartArg: false,
            macosLoginItemSignal: false,
            expected: false,
          ),

          // ── --autostart CLI arg present (Windows/Linux path) ───────────────
          (
            description: '--autostart present, both settings on → minimize',
            launchAtStartup: true,
            startMinimized: true,
            autostartArg: true,
            macosLoginItemSignal: null,
            expected: true,
          ),
          (
            description:
                '--autostart present, launchAtStartup off → no minimize',
            launchAtStartup: false,
            startMinimized: true,
            autostartArg: true,
            macosLoginItemSignal: null,
            expected: false,
          ),
          (
            description:
                '--autostart present, startMinimized off → no minimize',
            launchAtStartup: true,
            startMinimized: false,
            autostartArg: true,
            macosLoginItemSignal: null,
            expected: false,
          ),
          (
            description: '--autostart present, both settings off → no minimize',
            launchAtStartup: false,
            startMinimized: false,
            autostartArg: true,
            macosLoginItemSignal: null,
            expected: false,
          ),

          // ── macOS Login-Item signal present (future Slice 03 path) ─────────
          (
            description:
                'macOS signal true (no --autostart arg), both settings on '
                '→ minimize',
            launchAtStartup: true,
            startMinimized: true,
            autostartArg: false,
            macosLoginItemSignal: true,
            expected: true,
          ),
          (
            description: 'macOS signal true, launchAtStartup off → no minimize',
            launchAtStartup: false,
            startMinimized: true,
            autostartArg: false,
            macosLoginItemSignal: true,
            expected: false,
          ),
          (
            description: 'macOS signal true, startMinimized off → no minimize',
            launchAtStartup: true,
            startMinimized: false,
            autostartArg: false,
            macosLoginItemSignal: true,
            expected: false,
          ),
          (
            description: 'macOS signal true, both settings off → no minimize',
            launchAtStartup: false,
            startMinimized: false,
            autostartArg: false,
            macosLoginItemSignal: true,
            expected: false,
          ),

          // ── Both signals present simultaneously → still just an OR ─────────
          (
            description:
                '--autostart present AND macOS signal true, both settings on '
                '→ minimize',
            launchAtStartup: true,
            startMinimized: true,
            autostartArg: true,
            macosLoginItemSignal: true,
            expected: true,
          ),
          (
            description:
                '--autostart present AND macOS signal false, both settings on '
                '→ minimize (arg alone is sufficient)',
            launchAtStartup: true,
            startMinimized: true,
            autostartArg: true,
            macosLoginItemSignal: false,
            expected: true,
          ),
        ];

    for (final c in cases) {
      test('AC: ${c.description}', () {
        final settings = settingsWith(
          launchAtStartup: c.launchAtStartup,
          startMinimized: c.startMinimized,
        );
        final args = c.autostartArg ? const ['--autostart'] : const <String>[];

        final result = shouldMinimize(
          args: args,
          settings: settings,
          macosLoginItemSignal: c.macosLoginItemSignal,
        );

        expect(result, c.expected);
      });
    }

    // AC: macOS Login-Item signal parameter defaults to null (unknown) when
    // omitted, so existing non-macOS call sites don't need to pass it.
    test('AC: macosLoginItemSignal defaults to null/unknown when omitted', () {
      final settings = settingsWith(
        launchAtStartup: true,
        startMinimized: true,
      );

      final result = shouldMinimize(
        args: const ['--autostart'],
        settings: settings,
      );

      expect(result, isTrue);
    });
  });
}
