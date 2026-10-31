/// Pure builders for the microphone submenu in the tray context menu.
///
/// Kept free of tray/platform state so the radio-selection logic and the
/// label↔menu-key mapping stay unit-testable.
library;

import 'package:tray_manager/tray_manager.dart';

import 'microphone_selection_service.dart';

export 'microphone_selection_service.dart' show micDefaultLabel;

/// Key namespace for microphone entries in the tray context menu.
const micMenuKeyPrefix = 'mic:';

/// Encodes a microphone label as a tray menu-item key.
String micMenuKey(String label) => '$micMenuKeyPrefix$label';

/// Returns the microphone label encoded in [key], or `null` when the key
/// does not belong to the microphone namespace.
String? micLabelFromMenuKey(String key) => key.startsWith(micMenuKeyPrefix)
    ? key.substring(micMenuKeyPrefix.length)
    : null;

/// Builds the microphone submenu: the system-default entry first, then a
/// separator and the enumerated devices.
///
/// Exactly one entry is checked (radio behavior). Option filtering and
/// ordering are shared with the status-bar chip via
/// [buildMicrophoneOptions] — a selected-but-absent device (e.g. unplugged
/// while undocked) is appended so the checkmark never silently disappears.
List<MenuItem> buildMicrophoneMenuItems({
  required List<String> deviceLabels,
  required String selectedLabel,
  required String systemDefaultLabel,
}) {
  final devices = buildMicrophoneOptions(
    deviceLabels: deviceLabels,
    selectedLabel: selectedLabel,
  ).sublist(1);
  return [
    MenuItem.checkbox(
      key: micMenuKey(micDefaultLabel),
      label: systemDefaultLabel,
      checked: selectedLabel == micDefaultLabel,
    ),
    if (devices.isNotEmpty) MenuItem.separator(),
    for (final label in devices)
      MenuItem.checkbox(
        key: micMenuKey(label),
        label: label,
        checked: label == selectedLabel,
      ),
  ];
}
