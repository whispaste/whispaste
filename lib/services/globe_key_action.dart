/// macOS system setting "Press 🌐 key to" (#778).
///
/// When Fn is the hotkey, macOS still runs this action on every Fn press
/// (emoji picker, input source switch, system dictation). WhisPaste only
/// reads the setting and points the user to System Settings → Keyboard; it
/// never changes it. Whether swallowing Fn in an active event tap alone
/// would suppress the action is deliberately untested (maintainer decision
/// 2026-11-10, no physical Fn probe).
///
/// Source: `com.apple.HIToolbox` / `AppleFnUsageType`, read by the native
/// host on the `com.whispaste.modifier_monitor` channel. The read works
/// inside the App Sandbox (Mac App Store build); when it fails anyway the
/// app falls back to the generic Fn warning ([GlobeKeyAction.unknown]).
library;

enum GlobeKeyAction {
  /// "Do Nothing": Fn reaches only WhisPaste.
  none,

  /// "Change Input Source".
  inputSource,

  /// "Show Emoji & Symbols".
  emoji,

  /// "Start Dictation".
  dictation,

  /// Key absent: the system default applies, which is never "Do Nothing".
  systemDefault,

  /// Unreadable or an unknown value: treated as a possible conflict.
  unknown,
}

/// Maps the raw `AppleFnUsageType` value from the native host.
GlobeKeyAction globeKeyActionFromRaw(Object? raw) => switch (raw) {
  null => GlobeKeyAction.systemDefault,
  0 => GlobeKeyAction.none,
  1 => GlobeKeyAction.inputSource,
  2 => GlobeKeyAction.emoji,
  3 => GlobeKeyAction.dictation,
  _ => GlobeKeyAction.unknown,
};

/// Whether Fn as hotkey collides with the system action.
bool globeKeyConflicts(GlobeKeyAction action) => action != GlobeKeyAction.none;

/// System Settings → Keyboard. The legacy pane id still opens the Keyboard
/// page on macOS 13+; [keyboardSettingsFallbackUrl] is the newer id.
const keyboardSettingsUrl =
    'x-apple.systempreferences:com.apple.preference.keyboard';
const keyboardSettingsFallbackUrl =
    'x-apple.systempreferences:com.apple.Keyboard-Settings.extension';
