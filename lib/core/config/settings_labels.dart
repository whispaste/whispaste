/// Shared presentation helpers for settings-driven UI labels.
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../l10n/generated/app_localizations.dart';
import '../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelId;
import '../recording/recording_helpers.dart' show displayNameForModel;
import 'settings_enums.dart';
import 'settings_provider.dart';
import 'whisper_languages.dart';

/// Immutable presentation snapshot for the bottom status bar.
///
/// Only carries essential **runtime** info — static config (overlay mode,
/// hotkey, after-action) belongs in Settings, not the status bar.
class StatusBarModel {
  const StatusBarModel({required this.sttModeLabel});

  /// Active speech-to-text mode, e.g. "Whisper · small" or "OpenAI".
  final String sttModeLabel;
}

/// Builds a consistent [StatusBarModel] from the current [settings].
StatusBarModel buildStatusBarModel({
  required AppSettings settings,
  required L10n l10n,
}) {
  return StatusBarModel(sttModeLabel: sttEngineModelLabel(settings, l10n));
}

/// The speech group's value on the dock (spec §2): the model's display name,
/// such as "Whisper · Balanced" or "Parakeet". A cloud provider shows its own
/// name. Never the raw model ID (UIA-NAM-02).
String sttEngineModelLabel(AppSettings settings, L10n l10n) {
  if (!settings.sttProviderType.isLocal) return settings.sttProvider;
  if (settings.onDeviceEngine == OnDeviceEngine.parakeet) {
    return displayNameForModel(parakeetModelId, l10n);
  }
  return displayNameForModel(settings.stt.model, l10n);
}

/// The language group's value on the dock (XP-5-14): the recognition
/// language's name, or a short "Auto" while the engine detects it — always
/// with Parakeet, which has no language setting. [nameOf] gives a language
/// code's name in the app language (CLDR); without one the catalog's
/// English name is used.
String sttLanguageDockLabel(
  AppSettings settings,
  L10n l10n, {
  String? Function(String code)? nameOf,
}) {
  final code = settings.sttLanguageCode;
  if (code == 'auto' ||
      (settings.sttProviderType.isLocal &&
          settings.onDeviceEngine == OnDeviceEngine.parakeet)) {
    return l10n.dockLanguageAuto;
  }
  return nameOf?.call(code) ?? whisperLanguages[code] ?? code;
}

/// macOS modifier glyphs with the names that map to them, in the canonical
/// macOS order ⌃⌥⇧⌘ (whatever order the shortcut was stored in).
const _macModifierGlyphs = <(Set<String>, String)>[
  ({'ctrl', 'control'}, '⌃'),
  ({'alt'}, '⌥'),
  ({'shift'}, '⇧'),
  ({'meta', 'cmd', 'win', 'super'}, '⌘'),
];

/// Returns display labels for the modifier portion of a shortcut.
///
/// On macOS the known modifiers become glyphs in the canonical order ⌃⌥⇧⌘
/// (the keycap style of the dock and Settings). Any modifier without a glyph
/// (AltGr) keeps its word after them. Windows and Linux show localized words
/// (e.g. "Strg" for German); `meta` is "Win" there, and on macOS a word
/// fallback reads "Cmd"/"Option".
///
/// [isMacOS] defaults to the running platform (`defaultTargetPlatform`, so
/// widget tests can pin it with `debugDefaultTargetPlatformOverride`).
List<String> hotkeyModifierLabels(
  String modifiers, {
  L10n? l10n,
  bool? isMacOS,
}) {
  if (modifiers.isEmpty) return const [];
  final mac = isMacOS ?? _isMacOS;
  final parts = modifiers
      .split('+')
      .map((modifier) => modifier.trim())
      .where((modifier) => modifier.isNotEmpty)
      .toList();
  if (!mac) {
    return [for (final part in parts) _modifierWord(part, l10n, mac: false)];
  }
  final lowered = [for (final part in parts) part.toLowerCase()];
  return [
    for (final (names, glyph) in _macModifierGlyphs)
      if (lowered.any(names.contains)) glyph,
    for (final part in parts)
      if (_macGlyphFor(part.toLowerCase()) == null)
        _modifierWord(part, l10n, mac: true),
  ];
}

String? _macGlyphFor(String lowerName) {
  for (final (names, glyph) in _macModifierGlyphs) {
    if (names.contains(lowerName)) return glyph;
  }
  return null;
}

String _modifierWord(String modifier, L10n? l10n, {required bool mac}) {
  return switch (modifier.toLowerCase()) {
    'ctrl' || 'control' => l10n?.modifierCtrl ?? 'Ctrl',
    'shift' => l10n?.modifierShift ?? 'Shift',
    'alt' =>
      mac ? (l10n?.modifierOption ?? 'Option') : (l10n?.modifierAlt ?? 'Alt'),
    'meta' || 'win' || 'super' =>
      mac ? (l10n?.modifierCmd ?? 'Cmd') : (l10n?.modifierWin ?? 'Win'),
    'cmd' => l10n?.modifierCmd ?? 'Cmd',
    // AltGr (Windows): stored distinctly so it survives a save and shows
    // as "AltGr"; registers as Ctrl+Alt (see resolveModifiers) (#39).
    'altgr' => l10n?.modifierAltGr ?? 'AltGr',
    _ => modifier,
  };
}

/// Platform check for the shortcut spelling. `defaultTargetPlatform` follows
/// the host in production and honors `debugDefaultTargetPlatformOverride` in
/// tests.
bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

/// Whether hotkeys are spelled with macOS glyphs on this platform. Keycap
/// rows use it to drop the textual "+" between key caps.
bool get hotkeyUsesMacGlyphs => _isMacOS;

/// The paste key as copy spells it: ⌘V on macOS, the Ctrl chord (localized,
/// "Strg+V" in German) on Windows and Linux.
String pasteShortcutLabel({L10n? l10n, bool? isMacOS}) {
  final mac = isMacOS ?? _isMacOS;
  return mac
      ? '⌘V'
      : formatHotkeyShortcut('ctrl', 'v', l10n: l10n, isMacOS: false);
}

/// Tooltip for the disabled push-to-talk switch when the platform reports no
/// key-up. On Linux the desktop can still trigger recording through the
/// `whispaste --toggle` CLI (handy-catchup/23), so point there instead of
/// the generic "not available" hint.
String pushToTalkUnavailableMessage(L10n l10n, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return os == 'linux'
      ? l10n.pushToTalkUnavailableLinuxTooltip
      : l10n.pushToTalkUnavailableTooltip;
}

/// Notice under the hotkey row while a saved double tap cannot be observed and
/// the key combination listens instead. Each OS names its own reason: macOS the
/// missing Input Monitoring permission, Windows the refused key observation,
/// Linux the session that reports no key release. Other systems keep the
/// generic wording.
String doubleTapFallbackNotice(
  L10n l10n, {
  bool? isMacOS,
  bool? isWindows,
  bool? isLinux,
}) => _byOperatingSystem(
  isMacOS: isMacOS,
  isWindows: isWindows,
  isLinux: isLinux,
  macOS: l10n.settingsDoubleTapFallbackNoticeMac,
  windows: l10n.settingsDoubleTapFallbackNoticeWindows,
  linux: l10n.settingsDoubleTapFallbackNoticeLinux,
  generic: l10n.settingsDoubleTapFallbackNotice,
);

/// Onboarding counterpart of [doubleTapFallbackNotice], with the same reasons.
String onboardingDoubleTapFallbackHint(
  L10n l10n, {
  bool? isMacOS,
  bool? isWindows,
  bool? isLinux,
}) => _byOperatingSystem(
  isMacOS: isMacOS,
  isWindows: isWindows,
  isLinux: isLinux,
  macOS: l10n.onboardingTriggerDoubleTapFallbackHintMac,
  windows: l10n.onboardingTriggerDoubleTapFallbackHintWindows,
  linux: l10n.onboardingTriggerDoubleTapFallbackHintLinux,
  generic: l10n.onboardingTriggerDoubleTapFallbackHint,
);

/// Picks the text for the running OS; the `is…` overrides exist for tests.
/// Systems other than the three desktop OSes get [generic].
String _byOperatingSystem({
  bool? isMacOS,
  bool? isWindows,
  bool? isLinux,
  required String macOS,
  required String windows,
  required String linux,
  required String generic,
}) {
  if (isMacOS ?? Platform.isMacOS) return macOS;
  if (isWindows ?? Platform.isWindows) return windows;
  if (isLinux ?? Platform.isLinux) return linux;
  return generic;
}

/// Subtitle of the Hold-to-record switch, shared by onboarding and Settings.
/// With key-up it explains both states in one fixed line: a subtitle that
/// followed the live value read as contradicting the title whenever the
/// switch was off (UIA-XP-7-12). Without key-up the switch is locked to
/// press-to-start, so the subtitle says that plus why.
String holdToRecordSubtitle(
  L10n l10n, {
  required bool supportsKeyUp,
  String? operatingSystem,
}) => supportsKeyUp
    ? l10n.holdToRecordExplained
    : '${l10n.onboardingTriggerModeToggleHint}\n'
          '${pushToTalkUnavailableMessage(l10n, operatingSystem: operatingSystem)}';

/// Whether hold mode is in effect: push-to-talk is on, the platform delivers
/// key-up, and no double-tap trigger replaces the hotkey (one trigger per
/// action, the recording handler checks the same). Otherwise the recording
/// runs as toggle, so the switch, the explanations and the practice texts
/// follow this value, not the stored setting alone (a fresh install stores
/// hold mode).
bool holdModeInEffect(AppSettings settings, {required bool supportsKeyUp}) =>
    settings.audioInput.pushToTalk &&
    supportsKeyUp &&
    settings.hotkey.hotkeyDoubleTapKey.isEmpty;

/// Returns a localized label for the primary key portion of a shortcut.
///
/// When [displayOverride] is non-empty (e.g. `'Ö'` captured by the recorder
/// for a DE-layout user pressing the physical `semicolon` position), it is
/// preferred over the canonical [key] token (`';'`). Single non-empty
/// override characters are returned upper-cased to match the recorder's
/// own key-cap rendering.
String hotkeyKeyLabel(String key, {L10n? l10n, String? displayOverride}) {
  final override = displayOverride?.trim() ?? '';
  if (override.isNotEmpty) {
    return override.length == 1 ? override.toUpperCase() : override;
  }
  final trimmed = key.trim();
  if (trimmed.isEmpty) return '';

  final normalized = trimmed.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  return switch (normalized) {
    'space' => l10n?.shortcutKeySpace ?? 'Space',
    'enter' => l10n?.shortcutKeyEnter ?? 'Enter',
    'escape' || 'esc' => l10n?.shortcutKeyEscape ?? 'Esc',
    'backspace' => l10n?.shortcutKeyBackspace ?? 'Backspace',
    'tab' => l10n?.shortcutKeyTab ?? 'Tab',
    'delete' || 'del' => l10n?.shortcutKeyDelete ?? 'Del',
    'insert' || 'ins' => l10n?.shortcutKeyInsert ?? 'Insert',
    'home' => l10n?.shortcutKeyHome ?? 'Home',
    'end' => l10n?.shortcutKeyEnd ?? 'End',
    'pageup' || 'pgup' => l10n?.shortcutKeyPageUp ?? 'Page Up',
    'pagedown' || 'pgdn' => l10n?.shortcutKeyPageDown ?? 'Page Down',
    'arrowup' || 'up' => '↑',
    'arrowdown' || 'down' => '↓',
    'arrowleft' || 'left' => '←',
    'arrowright' || 'right' => '→',
    _ => trimmed.toUpperCase(),
  };
}

/// Returns shortcut display parts ordered as modifier chips + primary key.
List<String> hotkeyDisplayParts(
  String modifiers,
  String key, {
  L10n? l10n,
  String? displayOverride,
  bool? isMacOS,
}) {
  return [
    ...hotkeyModifierLabels(modifiers, l10n: l10n, isMacOS: isMacOS),
    if (key.trim().isNotEmpty || (displayOverride?.trim().isNotEmpty ?? false))
      hotkeyKeyLabel(key, l10n: l10n, displayOverride: displayOverride),
  ];
}

/// The three example shortcuts quoted in the recorder hint, spelled for the
/// running platform (UX-018): keycap glyphs on macOS, localized modifier words
/// on Windows and Linux, so the hint never shows English names in German.
List<String> hotkeyRecorderExamples({L10n? l10n, bool? isMacOS}) => [
  for (final (modifiers, key) in const [
    ('alt', 'space'),
    ('ctrl+alt', 'v'),
    ('ctrl+alt+shift', 'r'),
  ])
    formatHotkeyShortcut(modifiers, key, l10n: l10n, isMacOS: isMacOS),
];

/// Formats a shortcut for display, with one spelling per platform used by
/// every hotkey display (Settings, Snippets, onboarding, dock, tooltips).
///
/// Windows and Linux: the words joined by [separator], e.g. `Ctrl+Shift+D`.
/// macOS: the keycap form, e.g. `⇧⌘ D` (glyphs in canonical order, a space,
/// then the key). [separator] only applies on the word form.
///
/// [isMacOS] defaults to the running platform.
String formatHotkeyShortcut(
  String modifiers,
  String key, {
  String separator = '+',
  L10n? l10n,
  String? displayOverride,
  bool? isMacOS,
}) {
  final mac = isMacOS ?? _isMacOS;
  if (!mac || !_onlyGlyphModifiers(modifiers)) {
    return hotkeyDisplayParts(
      modifiers,
      key,
      l10n: l10n,
      displayOverride: displayOverride,
      isMacOS: mac,
    ).join(separator);
  }
  final prefix = hotkeyModifierLabels(
    modifiers,
    l10n: l10n,
    isMacOS: true,
  ).join();
  final keyLabel = hotkeyKeyLabel(
    key,
    l10n: l10n,
    displayOverride: displayOverride,
  );
  if (prefix.isEmpty) return keyLabel;
  if (keyLabel.isEmpty) return prefix;
  return '$prefix $keyLabel';
}

/// Whether every modifier of [modifiers] has a macOS glyph. A modifier
/// without one (AltGr) keeps the whole shortcut in the word form.
bool _onlyGlyphModifiers(String modifiers) => modifiers
    .split('+')
    .map((modifier) => modifier.trim().toLowerCase())
    .where((modifier) => modifier.isNotEmpty)
    .every((modifier) => _macGlyphFor(modifier) != null);

/// Keycap spelling of a shortcut (spec §2, the mockup's "⌘ Ö"). Same as
/// [formatHotkeyShortcut], which is the single place that decides the
/// platform form; kept as the name the dock's call site uses.
String formatHotkeyKeycap(
  String modifiers,
  String key, {
  L10n? l10n,
  String? displayOverride,
  bool? isMacOS,
}) => formatHotkeyShortcut(
  modifiers,
  key,
  l10n: l10n,
  displayOverride: displayOverride,
  isMacOS: isMacOS,
);

/// Both label flavors for [action] in one pass — the status bar's compact
/// "After: X" form and the Settings dropdown's full descriptive form — so
/// the two only need a single switch between them (see
/// [afterTranscriptionStatusLabel] / [afterTranscriptionSettingsLabel]).
({String status, String settings}) _afterTranscriptionLabels(
  AfterTranscriptionAction action,
  L10n l10n,
) {
  return switch (action) {
    AfterTranscriptionAction.clipboard => (
      status: l10n.statusBarAfterCopy,
      settings: l10n.settingsAfterTranscriptionClipboard,
    ),
    AfterTranscriptionAction.paste => (
      status: l10n.statusBarAfterPaste,
      settings: l10n.settingsAfterTranscriptionPaste,
    ),
    AfterTranscriptionAction.clipboardAndPaste => (
      status: l10n.statusBarAfterBoth,
      settings: l10n.settingsAfterTranscriptionBoth,
    ),
    AfterTranscriptionAction.nothing => (
      status: l10n.statusBarAfterNothing,
      settings: l10n.settingsAfterTranscriptionNothing,
    ),
  };
}

/// Returns a short, localized label for the post-transcription action — the
/// compact "After: X" form used in the status bar chip and its menu items.
String afterTranscriptionStatusLabel(
  AfterTranscriptionAction action,
  L10n l10n,
) => _afterTranscriptionLabels(action, l10n).status;

/// Returns the full, localized label for the post-transcription action — the
/// descriptive form used in the Settings dropdown (e.g. "Auto-Paste at
/// Cursor" rather than the status bar's short "After: Paste").
String afterTranscriptionSettingsLabel(
  AfterTranscriptionAction action,
  L10n l10n,
) => _afterTranscriptionLabels(action, l10n).settings;

/// The bare action for the dock's output selector, without the "After:" or
/// "Danach:" prefix: the overline already names the step.
String afterTranscriptionDockLabel(
  AfterTranscriptionAction action,
  L10n l10n,
) => switch (action) {
  AfterTranscriptionAction.clipboard => l10n.dockOutputCopy,
  AfterTranscriptionAction.paste => l10n.dockOutputPaste,
  AfterTranscriptionAction.clipboardAndPaste => l10n.dockOutputBoth,
  AfterTranscriptionAction.nothing => l10n.dockOutputNothing,
};

/// Name of the right Command, Windows or Super key on this platform. Each
/// system calls it something else, so the label names only that key (PAR-054).
String rightMetaLabel(L10n l10n) => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => l10n.settingsModifierRightMetaMac,
  TargetPlatform.windows => l10n.settingsModifierRightMetaWindows,
  _ => l10n.settingsModifierRightMetaLinux,
};

/// Name of the left Command, Windows or Super key on this platform.
String leftMetaLabel(L10n l10n) => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => l10n.settingsModifierLeftMetaMac,
  TargetPlatform.windows => l10n.settingsModifierLeftMetaWindows,
  _ => l10n.settingsModifierLeftMetaLinux,
};

/// Display name of a single-key choice; the empty name means off.
String modifierOnlyLabel(L10n l10n, String name) => switch (name) {
  'leftShift' => l10n.settingsModifierLeftShift,
  'rightShift' => l10n.settingsModifierRightShift,
  'leftControl' => l10n.settingsModifierLeftControl,
  'rightControl' => l10n.settingsModifierRightControl,
  'leftAlt' => l10n.settingsModifierLeftAlt,
  'rightAlt' => l10n.settingsModifierRightAlt,
  'leftMeta' => leftMetaLabel(l10n),
  'rightMeta' => rightMetaLabel(l10n),
  'fn' => l10n.settingsModifierFn,
  _ => l10n.settingsModifierOnlyNone,
};

/// The key cap of a single dictation key: the symbol or word printed on the
/// key ("⌘", "Strg", "fn") and which side of the keyboard it sits on, so the
/// recorder and the onboarding page draw a key instead of a sentence.
({String cap, String? side}) singleKeyCap(
  L10n l10n,
  String name, {
  bool? isMacOS,
}) {
  if (name == 'fn') return (cap: 'fn', side: null);
  final (modifier, left) = switch (name) {
    'leftShift' => ('shift', true),
    'rightShift' => ('shift', false),
    'leftControl' => ('ctrl', true),
    'rightControl' => ('ctrl', false),
    'leftAlt' => ('alt', true),
    'rightAlt' => ('alt', false),
    'leftMeta' => ('meta', true),
    _ => ('meta', false),
  };
  return (
    cap: hotkeyModifierLabels(modifier, l10n: l10n, isMacOS: isMacOS).first,
    side: left ? l10n.hotkeyKeySideLeft : l10n.hotkeyKeySideRight,
  );
}

/// The single key suggested on this platform: right Command on macOS (a tap
/// on Fn opens the emoji picker by default, so its double tap collides), right
/// Control elsewhere, because right Alt is AltGr on many European Windows and
/// Linux layouts.
String modifierOnlySuggestion({required bool isMacOS}) =>
    isMacOS ? 'rightMeta' : 'rightControl';
