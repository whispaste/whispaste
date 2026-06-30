/// Resolves the real, layout-correct character for a key the Windows hotkey
/// recorder captured as a US-canonical key (issue #39).
///
/// When a Ctrl (or AltGr, which is Ctrl+RightAlt) modifier is held, Windows
/// suppresses the layout translation and Flutter reports the canonical US
/// logical key (e.g. `;` for the German `Ö` key) with no character. The recorder
/// stores that canonical key (correct — it keeps the binding layout-stable) but
/// would otherwise *display* the US label. This helper asks the native side
/// (ToUnicodeEx on the active layout) what the key really is, so the cap can
/// read `Ö`/`Ä`/`Ü` instead of `;`/`'`/`[`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('com.whispaste.keyboard_monitor');

/// Canonical (US) [LogicalKeyboardKey] keyId → Windows virtual-key, for the
/// keys whose printed character differs between the US layout Flutter reports
/// under a modifier and the user's actual layout. Letters/digits look the same
/// on every Latin layout, so only the OEM/punctuation keys need an entry.
final Map<int, int> _vkByCanonicalKeyId = {
  LogicalKeyboardKey.semicolon.keyId: 0xBA, // VK_OEM_1   → DE ö
  LogicalKeyboardKey.quote.keyId: 0xDE, // VK_OEM_7   → DE ä
  LogicalKeyboardKey.bracketLeft.keyId: 0xDB, // VK_OEM_4   → DE ü
  LogicalKeyboardKey.bracketRight.keyId: 0xDD, // VK_OEM_6   → DE +
  LogicalKeyboardKey.backslash.keyId: 0xDC, // VK_OEM_5   → DE #
  LogicalKeyboardKey.backquote.keyId: 0xC0, // VK_OEM_3   → DE ^
  LogicalKeyboardKey.minus.keyId: 0xBD, // VK_OEM_MINUS → DE ß
  LogicalKeyboardKey.equal.keyId: 0xBB, // VK_OEM_PLUS  → DE ´
  LogicalKeyboardKey.comma.keyId: 0xBC, // VK_OEM_COMMA → DE ,
  LogicalKeyboardKey.period.keyId: 0xBE, // VK_OEM_PERIOD → DE .
  LogicalKeyboardKey.slash.keyId: 0xBF, // VK_OEM_2   → DE -
  LogicalKeyboardKey.intlBackslash.keyId: 0xE2, // VK_OEM_102 → DE <
};

/// Returns the active-layout label for [canonical] (e.g. `Ö` for the US `;`
/// key on a German layout), or `null` off Windows, for non-layout-sensitive
/// keys, or when the native lookup yields nothing.
Future<String?> resolveWindowsLayoutLabel(LogicalKeyboardKey canonical) async {
  if (kIsWeb || !Platform.isWindows) return null;
  final vk = _vkByCanonicalKeyId[canonical.keyId];
  if (vk == null) return null;
  try {
    final label = await _channel.invokeMethod<String>('resolveLayoutLabel', {
      'vk': vk,
    });
    if (label == null || label.isEmpty) return null;
    return label.toUpperCase();
  } on Object {
    // Channel/plugin error → fall back to the canonical label silently.
    return null;
  }
}
