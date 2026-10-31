/// The one path on which a one-shot extra hotkey ("next favorite language",
/// "paste the last dictation again") is re-assigned and switched on or off.
/// Same shape as `snippet_picker_hotkey_flow.dart`: the settings section and
/// any other entry point both call these functions, so there is one stored
/// state.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../widgets/hotkey_recorder.dart' show WpHotkeyResult;
import 'hotkey_flow.dart';

/// Where one one-shot hotkey keeps its settings. [actionId] must match the
/// action id in `HotkeyService` and in [activeHotkeyBindings].
class OneShotHotkey {
  const OneShotHotkey({
    required this.actionId,
    required this.read,
    required this.apply,
    required this.enable,
  });

  final String actionId;

  /// The stored state: enabled, key token, key label and modifiers.
  final ({bool enabled, String key, String display, String modifiers}) Function(
    AppSettings s,
  )
  read;

  /// Stores a newly recorded combination.
  final AppSettings Function(AppSettings s, WpHotkeyResult result) apply;

  /// Switches the hotkey on or off.
  final AppSettings Function(AppSettings s, bool enabled) enable;
}

const languageCycleHotkey = OneShotHotkey(
  actionId: 'languageCycle',
  read: _readLanguageCycle,
  apply: _applyLanguageCycle,
  enable: _enableLanguageCycle,
);

const repasteHotkey = OneShotHotkey(
  actionId: 'repaste',
  read: _readRepaste,
  apply: _applyRepaste,
  enable: _enableRepaste,
);

/// Opens the recording dialog for [hotkey] and stores the result when the
/// combination is free.
Future<HotkeyRecordResult> recordOneShotHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required AppSettings settings,
  required OneShotHotkey hotkey,
}) {
  final current = hotkey.read(settings);
  return recordHotkey(
    context: context,
    ref: ref,
    settings: settings,
    actionId: hotkey.actionId,
    initialKey: current.key,
    initialDisplayKey: current.display,
    initialModifiers: current.modifiers,
    apply: hotkey.apply,
  );
}

/// Switches [hotkey] on or off.
Future<void> setOneShotHotkeyEnabled(
  WidgetRef ref,
  OneShotHotkey hotkey, {
  required bool enabled,
}) => ref
    .read(settingsProvider.notifier)
    .updateSettings((s) => hotkey.enable(s, enabled));

({bool enabled, String key, String display, String modifiers})
_readLanguageCycle(AppSettings s) => (
  enabled: s.stt.languageCycleHotkeyEnabled,
  key: s.stt.languageCycleHotkeyKey,
  display: s.stt.languageCycleHotkeyKeyDisplay,
  modifiers: s.stt.languageCycleHotkeyModifiers,
);

AppSettings _applyLanguageCycle(AppSettings s, WpHotkeyResult r) =>
    s.copyWithSections(
      stt: s.stt.copyWith(
        languageCycleHotkeyKey: r.key,
        languageCycleHotkeyKeyDisplay: r.displayKey,
        languageCycleHotkeyModifiers: r.modifiers,
      ),
    );

AppSettings _enableLanguageCycle(AppSettings s, bool enabled) => s
    .copyWithSections(stt: s.stt.copyWith(languageCycleHotkeyEnabled: enabled));

({bool enabled, String key, String display, String modifiers}) _readRepaste(
  AppSettings s,
) => (
  enabled: s.behavior.repasteHotkeyEnabled,
  key: s.behavior.repasteHotkeyKey,
  display: s.behavior.repasteHotkeyKeyDisplay,
  modifiers: s.behavior.repasteHotkeyModifiers,
);

AppSettings _applyRepaste(AppSettings s, WpHotkeyResult r) =>
    s.copyWithSections(
      behavior: s.behavior.copyWith(
        repasteHotkeyKey: r.key,
        repasteHotkeyKeyDisplay: r.displayKey,
        repasteHotkeyModifiers: r.modifiers,
      ),
    );

AppSettings _enableRepaste(AppSettings s, bool enabled) => s.copyWithSections(
  behavior: s.behavior.copyWith(repasteHotkeyEnabled: enabled),
);
