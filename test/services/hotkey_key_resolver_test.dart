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

    test('non-digit special character throws ArgumentError', () {
      expect(() => resolveKey('Ö'), throwsArgumentError);
    });
  });

  group('resolveKey — digits 0–9', () {
    test('0 resolves to digit0', () {
      expect(resolveKey('0'), LogicalKeyboardKey.digit0);
    });

    test('5 resolves to digit5', () {
      expect(resolveKey('5'), LogicalKeyboardKey.digit5);
    });

    test('9 resolves to digit9', () {
      expect(resolveKey('9'), LogicalKeyboardKey.digit9);
    });

    test('all digits 0–9 round-trip via labelForKey', () {
      for (var n = 0; n <= 9; n++) {
        final label = '$n';
        final key = resolveKey(label);
        expect(labelForKey(key), label, reason: 'round-trip failed for $label');
      }
    });
  });

  group('labelForKey — digits', () {
    test('digit3 → "3"', () {
      expect(labelForKey(LogicalKeyboardKey.digit3), '3');
    });

    test('digit0 → "0"', () {
      expect(labelForKey(LogicalKeyboardKey.digit0), '0');
    });

    test('digit9 → "9"', () {
      expect(labelForKey(LogicalKeyboardKey.digit9), '9');
    });
  });

  group('isRecordableKey', () {
    test('letter keyA → true', () {
      expect(isRecordableKey(LogicalKeyboardKey.keyA), isTrue);
    });

    test('digit0 → true', () {
      expect(isRecordableKey(LogicalKeyboardKey.digit0), isTrue);
    });

    test('digit5 → true', () {
      expect(isRecordableKey(LogicalKeyboardKey.digit5), isTrue);
    });

    test('digit9 → true', () {
      expect(isRecordableKey(LogicalKeyboardKey.digit9), isTrue);
    });

    test('all F1–F12 → true', () {
      for (var n = 1; n <= 12; n++) {
        final key = LogicalKeyboardKey(0x00100000070 + n - 1);
        expect(isRecordableKey(key), isTrue, reason: 'F$n must be recordable');
      }
    });

    test('arrow keys → true', () {
      expect(isRecordableKey(LogicalKeyboardKey.arrowLeft), isTrue);
      expect(isRecordableKey(LogicalKeyboardKey.arrowUp), isTrue);
      expect(isRecordableKey(LogicalKeyboardKey.arrowDown), isTrue);
      expect(isRecordableKey(LogicalKeyboardKey.arrowRight), isTrue);
    });

    test('space → true', () {
      expect(isRecordableKey(LogicalKeyboardKey.space), isTrue);
    });

    test('Unicode ö (0xF6) → false', () {
      expect(isRecordableKey(const LogicalKeyboardKey(0xF6)), isFalse);
    });

    test('Unicode ä (0xE4) → false', () {
      expect(isRecordableKey(const LogicalKeyboardKey(0xE4)), isFalse);
    });

    test('semicolon → true (US-layout punctuation)', () {
      expect(isRecordableKey(LogicalKeyboardKey.semicolon), isTrue);
    });

    test('quote → true (US-layout punctuation)', () {
      expect(isRecordableKey(LogicalKeyboardKey.quote), isTrue);
    });

    test('numLock → false (non-recordable system key)', () {
      expect(isRecordableKey(LogicalKeyboardKey.numLock), isFalse);
    });

    test('mediaPlayPause → true (in singleKeyWhitelist via labelForKey '
        'whitelist or explicit accept)', () {
      // mediaPlayPause has no labelForKey entry, but is part of the
      // singleKeyWhitelist of accepted no-modifier keys. isRecordableKey
      // must accept it so the recorder's whitelisted-single-key path works.
      expect(isRecordableKey(LogicalKeyboardKey.mediaPlayPause), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // resolveKey — punctuation tokens (US-layout canonical)
  // ---------------------------------------------------------------------------

  group('resolveKey — punctuation', () {
    final cases = <String, LogicalKeyboardKey>{
      ';': LogicalKeyboardKey.semicolon,
      "'": LogicalKeyboardKey.quote,
      '`': LogicalKeyboardKey.backquote,
      ',': LogicalKeyboardKey.comma,
      '-': LogicalKeyboardKey.minus,
      '.': LogicalKeyboardKey.period,
      '/': LogicalKeyboardKey.slash,
      '=': LogicalKeyboardKey.equal,
      '[': LogicalKeyboardKey.bracketLeft,
      ']': LogicalKeyboardKey.bracketRight,
      '\\': LogicalKeyboardKey.backslash,
    };

    cases.forEach((token, expected) {
      test('"$token" → ${expected.debugName}', () {
        expect(resolveKey(token), expected);
      });

      test('labelForKey(${expected.debugName}) round-trips to "$token"', () {
        expect(labelForKey(expected), token);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // canonicalRecordableKey — physical-key fallback for layout-dependent chars
  // ---------------------------------------------------------------------------

  group('canonicalRecordableKey', () {
    test('Ö (0xF6) at semicolon physical position → semicolon', () {
      // What Flutter surfaces for a DE-layout user pressing the Ö key.
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.semicolon,
        logicalKey: LogicalKeyboardKey(0xF6),
        timeStamp: Duration.zero,
        character: 'ö',
      );
      expect(canonicalRecordableKey(event), LogicalKeyboardKey.semicolon);
    });

    test('Ä (0xE4) at quote physical position → quote', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.quote,
        logicalKey: LogicalKeyboardKey(0xE4),
        timeStamp: Duration.zero,
        character: 'ä',
      );
      expect(canonicalRecordableKey(event), LogicalKeyboardKey.quote);
    });

    test('canonical key returns itself (semicolon → semicolon)', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.semicolon,
        logicalKey: LogicalKeyboardKey.semicolon,
        timeStamp: Duration.zero,
      );
      expect(canonicalRecordableKey(event), LogicalKeyboardKey.semicolon);
    });

    test('keyA on a non-Latin layout (logical = e.g. キ) still resolves '
        'via physical position', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey(0x30AD),
        timeStamp: Duration.zero,
        character: 'キ',
      );
      expect(canonicalRecordableKey(event), LogicalKeyboardKey.keyA);
    });

    test('non-recordable physical key (numLock) → null', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.numLock,
        logicalKey: LogicalKeyboardKey.numLock,
        timeStamp: Duration.zero,
      );
      expect(canonicalRecordableKey(event), isNull);
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

  group('resolveModifiers — self-healing aliases (display-label tokens)', () {
    // These aliases exist so DBs corrupted by the pre-fix recorder
    // (which wrote display labels as storage strings) self-heal on next
    // app launch — without forcing the user to rebind their hotkey.

    test('"option" → [alt] (macOS display label, EN+DE)', () {
      expect(resolveModifiers('option'), [HotKeyModifier.alt]);
    });

    test('"wahltaste" → [alt] (DE-alternative for option/alt)', () {
      expect(resolveModifiers('wahltaste'), [HotKeyModifier.alt]);
    });

    test('"strg" → [control] (DE for ctrl)', () {
      expect(resolveModifiers('strg'), [HotKeyModifier.control]);
    });

    test('"umschalt" → [shift] (DE for shift)', () {
      expect(resolveModifiers('umschalt'), [HotKeyModifier.shift]);
    });

    test('"befehl" → [meta] (DE for cmd)', () {
      expect(resolveModifiers('befehl'), [HotKeyModifier.meta]);
    });

    test('combined DE "strg+umschalt" → [control, shift]', () {
      expect(resolveModifiers('strg+umschalt'), [
        HotKeyModifier.control,
        HotKeyModifier.shift,
      ]);
    });

    test('mixed-language "option+shift" → [alt, shift]', () {
      expect(resolveModifiers('option+shift'), [
        HotKeyModifier.alt,
        HotKeyModifier.shift,
      ]);
    });

    test('case-insensitive: "OPTION", "Option", "option" all → [alt]', () {
      expect(resolveModifiers('OPTION'), [HotKeyModifier.alt]);
      expect(resolveModifiers('Option'), [HotKeyModifier.alt]);
      expect(resolveModifiers('option'), [HotKeyModifier.alt]);
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
