/// The one way the "edit selection" hotkey gets rebound
/// (`.scratch/voice-selection-edit/`).
///
/// Twin of `smart_mode_hotkey_flow.dart`: the flow itself — open dialog →
/// check collisions → only then save — lives in `hotkey_flow.dart`; this
/// file only says which settings section is read and written.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'hotkey_flow.dart';

/// Opens the recorder dialog for the edit-selection hotkey and saves the
/// result — only if the combination is free.
Future<HotkeyRecordResult> recordSelectionEditHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  // loam-ignore: code-duplicates – twin of `recordSmartModeHotkey`, see its doc comment
}) {
  final hotkey = settings.selectionEditHotkey;
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: 'selectionEdit',
    initialKey: hotkey.selectionEditHotkeyKey,
    initialDisplayKey: hotkey.selectionEditHotkeyKeyDisplay,
    initialModifiers: hotkey.selectionEditHotkeyModifiers,
    apply: (s, result) => s.copyWithSections(
      selectionEditHotkey: s.selectionEditHotkey.copyWith(
        selectionEditHotkeyKey: result.key,
        selectionEditHotkeyKeyDisplay: result.displayKey,
        selectionEditHotkeyModifiers: result.modifiers,
      ),
    ),
  );
}

/// Turns the edit-selection hotkey on or off.
Future<void> setSelectionEditHotkeyEnabled(
  WidgetRef ref, {
  required bool enabled,
}) {
  return ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          selectionEditHotkey: s.selectionEditHotkey.copyWith(
            selectionEditHotkeyEnabled: enabled,
          ),
        ),
      );
}
