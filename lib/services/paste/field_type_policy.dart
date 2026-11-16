import '../desktop_paste/desktop_paste_controller_interface.dart';

/// What the paster does with the transcript for a [FocusedFieldType] (#948).
///
/// Shared by every platform: Windows reports the type today, macOS (#949) and
/// Linux (#950) will report it through the same channel contract.
enum FieldTypeVerdict {
  /// Auto-paste as before.
  paste,

  /// No auto-paste: the transcript goes to the clipboard (and stays in the
  /// history) and the user is told to paste it by hand.
  manualPaste,
}

/// Only a confirmed password or PIN field stops the auto-paste. No
/// information keeps the previous behaviour, so a slow or failing probe
/// never costs the user a paste.
FieldTypeVerdict fieldTypeVerdict(FocusedFieldType type) => switch (type) {
  FocusedFieldType.password => FieldTypeVerdict.manualPaste,
  FocusedFieldType.normal || FocusedFieldType.unknown => FieldTypeVerdict.paste,
};
