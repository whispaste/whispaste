import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'floating_button/floating_button_support.dart';
import 'modifier_key_monitor.dart';

/// What starts one action. Every action has exactly one trigger, and every
/// trigger belongs to exactly one action (maintainer decision 2026-10-25).
///
/// A single key held on its own is not a trigger; only a key combination or a
/// double tap of one single key is.
sealed class HotkeyTrigger {
  const HotkeyTrigger();

  /// Canonical identity. Two triggers with the same signature collide.
  String get signature;
}

/// A key combination such as Ctrl+Shift+D. A short tap starts or stops
/// dictation; holding it longer turns it into push-to-talk.
final class HotkeyComboTrigger extends HotkeyTrigger {
  const HotkeyComboTrigger({required this.key, this.modifiers = const {}});

  final LogicalKeyboardKey key;
  final Set<HotKeyModifier> modifiers;

  @override
  String get signature {
    final names = modifiers.map((m) => m.name).toList()..sort();
    return 'combo:${names.join('+')}+${key.keyId}';
  }
}

/// A double tap of one single key, e.g. Fn Fn. Two quick taps run the action.
final class HotkeyDoubleTapTrigger extends HotkeyTrigger {
  const HotkeyDoubleTapTrigger(this.key);

  final ModifierHotkey key;

  @override
  String get signature => 'doubletap:${key.name}';
}

/// Several actions share one trigger signature. Never saved, only reported.
class HotkeyTriggerConflict {
  const HotkeyTriggerConflict(this.trigger, this.actionIds);

  final HotkeyTrigger trigger;
  final List<String> actionIds;
}

/// Every trigger that more than one action holds. [assignments] maps an action
/// id to its trigger; unassigned actions are simply absent. An empty result
/// means every trigger belongs to exactly one action.
List<HotkeyTriggerConflict> findTriggerConflicts(
  Map<String, HotkeyTrigger> assignments,
) {
  final holders = <String, List<String>>{};
  final triggers = <String, HotkeyTrigger>{};
  for (final entry in assignments.entries) {
    final signature = entry.value.signature;
    triggers[signature] = entry.value;
    holders.putIfAbsent(signature, () => []).add(entry.key);
  }
  return [
    for (final signature in holders.keys)
      if (holders[signature]!.length > 1)
        HotkeyTriggerConflict(triggers[signature]!, holders[signature]!),
  ];
}

/// The other action that already holds [candidate], or null when it is free
/// for [forAction]. Used for the live check in the trigger dialog, so an
/// action never conflicts with its own current trigger.
String? triggerHolder(
  HotkeyTrigger candidate, {
  required String forAction,
  required Map<String, HotkeyTrigger> assignments,
}) {
  final signature = candidate.signature;
  for (final entry in assignments.entries) {
    if (entry.key == forAction) continue;
    if (entry.value.signature == signature) return entry.key;
  }
  return null;
}

/// Whether a double tap of [key] can be observed on this platform. Fn exists
/// on macOS only. Wayland delivers no key-up for a single key, so a double tap
/// cannot be detected there and the dialog must say so instead of offering it.
bool doubleTapSupported(
  ModifierHotkey key, {
  required bool isMacOS,
  required bool isWayland,
}) => !isWayland && modifierHotkeySupported(key, isMacOS: isMacOS);

/// [doubleTapSupported] on the running platform for a stored key name
/// (`ModifierHotkey.name`). An unknown name is never supported.
bool doubleTapSupportedHere(String keyName) {
  final matches = ModifierHotkey.values.where((k) => k.name == keyName);
  if (matches.isEmpty) return false;
  final isWayland =
      Platform.isLinux &&
      linuxSessionTypeFrom(Platform.environment) == LinuxSessionType.wayland;
  return doubleTapSupported(
    matches.first,
    isMacOS: Platform.isMacOS,
    isWayland: isWayland,
  );
}
