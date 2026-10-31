/// Resolves the real, layout-correct key for a physical key the Windows
/// hotkey recorder captured (issue #108).
///
/// Root cause: Windows keyboard layout drivers reassign the VK_OEM_* virtual
/// keys to different physical positions per layout. E.g. on the German
/// (QWERTZ) driver, the physical key that prints `#` (hardware scan code
/// 0x2B) is VK_OEM_2 — not VK_OEM_5, which is what the US layout (and
/// Flutter's static, US-based `PhysicalKeyboardKey → virtual-key` table used
/// internally by `hotkey_manager`) assumes for that physical position.
/// `RegisterHotKey` matches on the live virtual-key the ACTIVE layout
/// produces, so a hotkey recorded from the static assumption silently binds
/// to the wrong physical key (reported: pressing `#` registers as `^`).
///
/// The fix asks the OS — not a hardcoded per-layout table — what virtual key
/// the CURRENTLY ACTIVE layout actually assigns to the pressed key's scan
/// code (`MapVirtualKeyEx`), so this is correct for any keyboard layout, not
/// just German.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('com.whispaste.keyboard_monitor');

/// Hardware (PS/2 Set 1) scan codes for the punctuation physical keys whose
/// Windows virtual-key assignment varies by keyboard layout. Scan codes are
/// layout-independent — the same physical key always reports the same scan
/// code — unlike the VK_OEM_* codes, which each layout driver assigns to
/// different physical positions. Mirrors the punctuation keys recordable via
/// `hotkey_key_resolver`'s `_physicalToLogical`/`_punctuationKeys` tables.
final Map<PhysicalKeyboardKey, int> _scanCodeByPhysicalKey = {
  PhysicalKeyboardKey.backquote: 0x29,
  PhysicalKeyboardKey.minus: 0x0C,
  PhysicalKeyboardKey.equal: 0x0D,
  PhysicalKeyboardKey.bracketLeft: 0x1A,
  PhysicalKeyboardKey.bracketRight: 0x1B,
  PhysicalKeyboardKey.backslash: 0x2B,
  PhysicalKeyboardKey.semicolon: 0x27,
  PhysicalKeyboardKey.quote: 0x28,
  PhysicalKeyboardKey.comma: 0x33,
  PhysicalKeyboardKey.period: 0x34,
  PhysicalKeyboardKey.slash: 0x35,
};

/// Canonical Logical → Physical correspondence for the same key set (the
/// naming that Flutter's own `kWindowsToLogicalKey` and `hotkey_manager`'s
/// Windows conversion agree on). Used to translate the live virtual-key back
/// into the [PhysicalKeyboardKey] that will round-trip to that same virtual
/// key when `hotkey_manager` registers it.
final Map<LogicalKeyboardKey, PhysicalKeyboardKey> _physicalByCanonicalLogical =
    {
      LogicalKeyboardKey.backquote: PhysicalKeyboardKey.backquote,
      LogicalKeyboardKey.minus: PhysicalKeyboardKey.minus,
      LogicalKeyboardKey.equal: PhysicalKeyboardKey.equal,
      LogicalKeyboardKey.bracketLeft: PhysicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.bracketRight: PhysicalKeyboardKey.bracketRight,
      LogicalKeyboardKey.backslash: PhysicalKeyboardKey.backslash,
      LogicalKeyboardKey.semicolon: PhysicalKeyboardKey.semicolon,
      LogicalKeyboardKey.quote: PhysicalKeyboardKey.quote,
      LogicalKeyboardKey.comma: PhysicalKeyboardKey.comma,
      LogicalKeyboardKey.period: PhysicalKeyboardKey.period,
      LogicalKeyboardKey.slash: PhysicalKeyboardKey.slash,
    };

/// Result of resolving a pressed physical key against the active Windows
/// keyboard layout.
class WindowsKeyResolution {
  const WindowsKeyResolution({required this.physicalKey, this.displayLabel});

  /// The physical key that should actually be persisted/registered so the
  /// eventual `RegisterHotKey` call binds the key the user physically
  /// pressed. Equal to the input when no correction was needed or possible.
  final PhysicalKeyboardKey physicalKey;

  /// The real character the active layout prints for the key (e.g. `#` on a
  /// German layout), or `null` when unavailable.
  final String? displayLabel;
}

/// Resolves [pressed] against the ACTIVE Windows keyboard layout.
///
/// No-ops (returns [pressed] unchanged, no [WindowsKeyResolution.displayLabel])
/// off Windows, for keys whose physical position isn't layout-sensitive
/// (letters, digits, arrows, named keys — already layout-invariant), or when
/// the native lookup fails.
Future<WindowsKeyResolution> resolveWindowsKey(
  PhysicalKeyboardKey pressed,
) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return WindowsKeyResolution(physicalKey: pressed);
  }
  final scanCode = _scanCodeByPhysicalKey[pressed];
  if (scanCode == null) return WindowsKeyResolution(physicalKey: pressed);
  try {
    final liveVk = await _channel.invokeMethod<int>('resolveLiveVirtualKey', {
      'scanCode': scanCode,
    });
    if (liveVk == null || liveVk == 0) {
      return WindowsKeyResolution(physicalKey: pressed);
    }
    final logical = kWindowsToLogicalKey[liveVk];
    final corrected = logical == null
        ? null
        : _physicalByCanonicalLogical[logical];
    final label = await _channel.invokeMethod<String>('resolveLayoutLabel', {
      'vk': liveVk,
    });
    return WindowsKeyResolution(
      physicalKey: corrected ?? pressed,
      displayLabel: (label == null || label.isEmpty)
          ? null
          : label.toUpperCase(),
    );
  } on Object {
    // Channel/plugin error → fall back to the key as originally pressed.
    return WindowsKeyResolution(physicalKey: pressed);
  }
}
