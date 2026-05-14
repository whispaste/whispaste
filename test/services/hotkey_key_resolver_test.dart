/// Tests for [resolveKey], [labelForKey] and [resolveModifiers].
///
/// Covers all four arrow keys, letter samples, F-keys, named keys,
/// modifier combos, round-trips and the ArgumentError error path.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/services/hotkey_key_resolver.dart';

void main() {
  group('resolveKey — arrow keys', () {
    // Symbol forms (stored by HotkeyRecorderDialog.keyLabel)
    test('← resolves to arrowLeft', () {
      expect(resolveKey('←'), LogicalKeyboardKey.arrowLeft);
    });

    test('↑ resolves to arrowUp', () {
      expect(resolveKey('↑'), LogicalKeyboardKey.arrowUp);
    });

    test('↓ resolves to arrowDown', () {
      expect(resolveKey('↓'), LogicalKeyboardKey.arrowDown);
    });

    test('→ resolves to arrowRight', () {
      expect(resolveKey('→'), LogicalKeyboardKey.arrowRight);
    });

    // ARROWXXX word forms
    test('ARROWLEFT resolves to arrowLeft', () {
      expect(resolveKey('ARROWLEFT'), LogicalKeyboardKey.arrowLeft);
    });

    test('arrowleft (lower) resolves to arrowLeft', () {
      expect(resolveKey('arrowleft'), LogicalKeyboardKey.arrowLeft);
    });

    test('ARROWUP resolves to arrowUp', () {
      expect(resolveKey('ARROWUP'), LogicalKeyboardKey.arrowUp);
    });

    test('ARROWDOWN resolves to arrowDown', () {
      expect(resolveKey('ARROWDOWN'), LogicalKeyboardKey.arrowDown);
    });

    test('ARROWRIGHT resolves to arrowRight', () {
      expect(resolveKey('ARROWRIGHT'), LogicalKeyboardKey.arrowRight);
    });

    // SHORT word forms
    test('LEFT resolves to arrowLeft', () {
      expect(resolveKey('LEFT'), LogicalKeyboardKey.arrowLeft);
    });

    test('UP resolves to arrowUp', () {
      expect(resolveKey('UP'), LogicalKeyboardKey.arrowUp);
    });

    test('DOWN resolves to arrowDown', () {
      expect(resolveKey('DOWN'), LogicalKeyboardKey.arrowDown);
    });

    test('RIGHT resolves to arrowRight', () {
      expect(resolveKey('RIGHT'), LogicalKeyboardKey.arrowRight);
    });
  });

  group('resolveKey — letters A–Z (samples)', () {
    test('A resolves to keyA', () {
      expect(resolveKey('A'), LogicalKeyboardKey.keyA);
    });

    test('a (lower) resolves to keyA', () {
      expect(resolveKey('a'), LogicalKeyboardKey.keyA);
    });

    test('D resolves to keyD', () {
      expect(resolveKey('D'), LogicalKeyboardKey.keyD);
    });

    test('M resolves to keyM', () {
      expect(resolveKey('M'), LogicalKeyboardKey.keyM);
    });

    test('Z resolves to keyZ', () {
      expect(resolveKey('Z'), LogicalKeyboardKey.keyZ);
    });
  });

  group('resolveKey — function keys F1–F12', () {
    for (var n = 1; n <= 12; n++) {
      final label = 'F$n';
      final expected = LogicalKeyboardKey(0x00100000070 + n - 1);
      test('$label resolves correctly', () {
        expect(resolveKey(label), expected);
      });
    }
  });

  group('resolveKey — named keys', () {
    test('SPACE', () => expect(resolveKey('SPACE'), LogicalKeyboardKey.space));
    test('ENTER', () => expect(resolveKey('ENTER'), LogicalKeyboardKey.enter));
    test('TAB', () => expect(resolveKey('TAB'), LogicalKeyboardKey.tab));
    test(
      'ESCAPE',
      () => expect(resolveKey('ESCAPE'), LogicalKeyboardKey.escape),
    );
    test('ESC', () => expect(resolveKey('ESC'), LogicalKeyboardKey.escape));
    test(
      'BACKSPACE',
      () => expect(resolveKey('BACKSPACE'), LogicalKeyboardKey.backspace),
    );
    test(
      'DELETE',
      () => expect(resolveKey('DELETE'), LogicalKeyboardKey.delete),
    );
    test(
      'INSERT',
      () => expect(resolveKey('INSERT'), LogicalKeyboardKey.insert),
    );
    test('HOME', () => expect(resolveKey('HOME'), LogicalKeyboardKey.home));
    test('END', () => expect(resolveKey('END'), LogicalKeyboardKey.end));
    test(
      'PAGEUP',
      () => expect(resolveKey('PAGEUP'), LogicalKeyboardKey.pageUp),
    );
    test(
      'PAGEDOWN',
      () => expect(resolveKey('PAGEDOWN'), LogicalKeyboardKey.pageDown),
    );
  });

  group('resolveKey — error path', () {
    test('unknown label throws ArgumentError', () {
      expect(() => resolveKey('FOOBAR'), throwsArgumentError);
    });

    test('empty string throws ArgumentError', () {
      expect(() => resolveKey(''), throwsArgumentError);
    });

    test('digit string throws ArgumentError', () {
      expect(() => resolveKey('1'), throwsArgumentError);
    });
  });

  group('labelForKey — round-trips', () {
    // For every key that resolveKey accepts (by its canonical label),
    // labelForKey should produce the same label back.
    final roundTripCases = <String>[
      // Arrow key symbols
      '←', '↑', '↓', '→',
      // Letters
      'A', 'D', 'M', 'Z',
      // Function keys
      'F1', 'F6', 'F12',
      // Named keys (using their labelForKey output)
      'Space', 'Enter', 'Tab', 'Esc', 'Backspace', 'Delete',
      'Insert', 'Home', 'End', 'PageUp', 'PageDown',
    ];

    for (final label in roundTripCases) {
      test('round-trip for "$label"', () {
        final key = resolveKey(label);
        final back = labelForKey(key);
        // resolveKey(labelForKey(k)) must equal k
        expect(back, isNotNull, reason: 'labelForKey returned null for $label');
        expect(
          resolveKey(back!),
          key,
          reason: 'round-trip failed for label "$label"',
        );
      });
    }
  });

  group('labelForKey — arrow keys produce symbols', () {
    test('arrowLeft → ←', () {
      expect(labelForKey(LogicalKeyboardKey.arrowLeft), '←');
    });

    test('arrowUp → ↑', () {
      expect(labelForKey(LogicalKeyboardKey.arrowUp), '↑');
    });

    test('arrowDown → ↓', () {
      expect(labelForKey(LogicalKeyboardKey.arrowDown), '↓');
    });

    test('arrowRight → →', () {
      expect(labelForKey(LogicalKeyboardKey.arrowRight), '→');
    });
  });

  group('labelForKey — named keys', () {
    test('space → Space', () {
      expect(labelForKey(LogicalKeyboardKey.space), 'Space');
    });

    test('escape → Esc', () {
      expect(labelForKey(LogicalKeyboardKey.escape), 'Esc');
    });

    test('pageUp → PageUp', () {
      expect(labelForKey(LogicalKeyboardKey.pageUp), 'PageUp');
    });

    test('pageDown → PageDown', () {
      expect(labelForKey(LogicalKeyboardKey.pageDown), 'PageDown');
    });
  });

  group('labelForKey — unknown key returns null', () {
    test('mediaPlayPause returns null', () {
      expect(labelForKey(LogicalKeyboardKey.mediaPlayPause), isNull);
    });
  });

  group('serializeModifiers — single source of truth for storage format', () {
    test('empty set → empty string', () {
      expect(serializeModifiers(const <LogicalKeyboardKey>{}), '');
    });

    test('alt alone → "alt" (the reporter\'s case)', () {
      expect(serializeModifiers({LogicalKeyboardKey.altLeft}), 'alt');
    });

    test('right-hand modifier is equivalent to left-hand', () {
      expect(serializeModifiers({LogicalKeyboardKey.controlRight}), 'ctrl');
      expect(serializeModifiers({LogicalKeyboardKey.shiftRight}), 'shift');
      expect(serializeModifiers({LogicalKeyboardKey.altRight}), 'alt');
      expect(serializeModifiers({LogicalKeyboardKey.metaRight}), 'meta');
    });

    test(
      'ctrl + shift → "ctrl+shift" (canonical order ctrl-shift-alt-meta)',
      () {
        expect(
          serializeModifiers({
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.controlLeft,
          }),
          'ctrl+shift',
          reason: 'token order is canonical, not insertion order',
        );
      },
    );

    test('all four modifiers → "ctrl+shift+alt+meta"', () {
      expect(
        serializeModifiers({
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.controlLeft,
        }),
        'ctrl+shift+alt+meta',
      );
    });

    test('non-modifier keys in the set are ignored', () {
      // Defensive: callers may pass a mixed set; only the four canonical
      // modifier pairs are inspected.
      expect(
        serializeModifiers({
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.arrowLeft,
        }),
        'alt',
      );
    });
  });

  group('resolveModifiers', () {
    test('ctrl maps to control', () {
      expect(resolveModifiers('ctrl'), [HotKeyModifier.control]);
    });

    test('control maps to control', () {
      expect(resolveModifiers('control'), [HotKeyModifier.control]);
    });

    test('shift maps to shift', () {
      expect(resolveModifiers('shift'), [HotKeyModifier.shift]);
    });

    test('alt maps to alt', () {
      expect(resolveModifiers('alt'), [HotKeyModifier.alt]);
    });

    test('meta maps to meta', () {
      expect(resolveModifiers('meta'), [HotKeyModifier.meta]);
    });

    test('cmd maps to meta', () {
      expect(resolveModifiers('cmd'), [HotKeyModifier.meta]);
    });

    test('win maps to meta', () {
      expect(resolveModifiers('win'), [HotKeyModifier.meta]);
    });

    test('super maps to meta', () {
      expect(resolveModifiers('super'), [HotKeyModifier.meta]);
    });

    test('ctrl+shift maps to [control, shift]', () {
      expect(resolveModifiers('ctrl+shift'), [
        HotKeyModifier.control,
        HotKeyModifier.shift,
      ]);
    });

    test('meta+alt maps to [meta, alt]', () {
      expect(resolveModifiers('meta+alt'), [
        HotKeyModifier.meta,
        HotKeyModifier.alt,
      ]);
    });

    test('empty string returns empty list', () {
      expect(resolveModifiers(''), isEmpty);
    });

    test('unknown modifier token is skipped', () {
      expect(resolveModifiers('ctrl+UNKNOWN'), [HotKeyModifier.control]);
    });
  });

  group('serializeModifiers ↔ resolveModifiers roundtrip invariant', () {
    // Each modifier-pair → expected HotKeyModifier value.
    const pairs = <_ModifierPair>[
      _ModifierPair(LogicalKeyboardKey.controlLeft, HotKeyModifier.control),
      _ModifierPair(LogicalKeyboardKey.shiftLeft, HotKeyModifier.shift),
      _ModifierPair(LogicalKeyboardKey.altLeft, HotKeyModifier.alt),
      _ModifierPair(LogicalKeyboardKey.metaLeft, HotKeyModifier.meta),
    ];

    // Iterate all 16 subsets of the 4 modifier-pairs.
    for (var bitmask = 0; bitmask < 16; bitmask++) {
      final inputKeys = <LogicalKeyboardKey>{};
      final expectedMods = <HotKeyModifier>{};
      for (var i = 0; i < pairs.length; i++) {
        if ((bitmask & (1 << i)) != 0) {
          inputKeys.add(pairs[i].key);
          expectedMods.add(pairs[i].modifier);
        }
      }

      test('roundtrip for $inputKeys', () {
        final serialized = serializeModifiers(inputKeys);
        final resolved = resolveModifiers(serialized);
        expect(
          resolved.toSet(),
          expectedMods,
          reason: 'serialize($inputKeys) = "$serialized" → resolve = $resolved',
        );
      });
    }
  });
}

class _ModifierPair {
  const _ModifierPair(this.key, this.modifier);
  final LogicalKeyboardKey key;
  final HotKeyModifier modifier;
}
