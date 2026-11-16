import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/command_shortcut.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

void main() {
  group(
    'command shortcut: binding and label come from one platform choice',
    () {
      for (final mac in [true, false]) {
        for (final shift in [false, true]) {
          test('macOS=$mac shift=$shift', () async {
            final de = await L10n.delegate.load(const Locale('de'));
            final activator = commandActivator(
              LogicalKeyboardKey.keyS,
              shift: shift,
              isMacOS: mac,
            );
            final label = commandShortcutLabel(
              'S',
              shift: shift,
              isMacOS: mac,
              l10n: de,
            );
            expect(activator.meta, mac);
            expect(activator.control, !mac);
            expect(activator.shift, shift);
            // The label names the modifier the binding listens to, spelled
            // by the app language.
            expect(label.contains('⌘'), activator.meta);
            expect(label.contains(de.modifierCtrl), activator.control);
            expect(
              label.contains('⇧') || label.contains(de.modifierShift),
              shift,
            );
          });
        }
      }
    },
  );

  test(
    'Return is the key cap on macOS and the localized word elsewhere',
    () async {
      final de = await L10n.delegate.load(const Locale('de'));
      expect(
        commandShortcutLabel(enterKey, isMacOS: true, l10n: de),
        contains(enterKey),
      );
      final other = commandShortcutLabel(enterKey, isMacOS: false, l10n: de);
      expect(other, contains(de.shortcutKeyEnter));
      expect(other, isNot(contains(enterKey)));
    },
  );

  test('a binding follows the platform it is asked on, as one instance', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final mac = commandActivator(LogicalKeyboardKey.keyL, shift: true);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final linux = commandActivator(LogicalKeyboardKey.keyL, shift: true);
    debugDefaultTargetPlatformOverride = null;

    expect(mac.meta && !mac.control, isTrue, reason: 'Cmd on macOS');
    expect(linux.control && !linux.meta, isTrue, reason: 'Ctrl on Linux');
    // Shortcut maps look the binding up by key, and SingleActivator compares
    // by identity: the same combination must give the same object.
    expect(
      commandActivator(LogicalKeyboardKey.keyL, shift: true, isMacOS: false),
      same(linux),
    );
  });
}
