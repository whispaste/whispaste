/// The one path on which the "next favorite language" hotkey is re-assigned
/// and switched on or off. Same shape as `snippet_picker_hotkey_flow.dart`:
/// the settings section and any other entry point both call these functions,
/// so there is one stored state.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'hotkey_flow.dart';

/// Opens the recording dialog for the language-cycle hotkey and stores the
/// result when the combination is free.
Future<HotkeyRecordResult> recordLanguageCycleHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
}) {
  final stt = settings.stt;
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: 'languageCycle',
    initialKey: stt.languageCycleHotkeyKey,
    initialDisplayKey: stt.languageCycleHotkeyKeyDisplay,
    initialModifiers: stt.languageCycleHotkeyModifiers,
    apply: (s, result) => s.copyWithSections(
      stt: s.stt.copyWith(
        languageCycleHotkeyKey: result.key,
        languageCycleHotkeyKeyDisplay: result.displayKey,
        languageCycleHotkeyModifiers: result.modifiers,
      ),
    ),
  );
}

/// Switches the language-cycle hotkey on or off.
Future<void> setLanguageCycleHotkeyEnabled(
  WidgetRef ref, {
  required bool enabled,
}) {
  return ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          stt: s.stt.copyWith(languageCycleHotkeyEnabled: enabled),
        ),
      );
}
