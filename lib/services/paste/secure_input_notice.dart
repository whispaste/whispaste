/// The wording for macOS secure input (F35-8, #775, #1617): an auto-paste it
/// skipped, and the hotkey notice while it is on.
///
/// Kept apart from `paste_result_notice.dart` so the widget layer can use it
/// without pulling in the notice reporter.
library;

import 'package:flutter/widgets.dart' show StringCharacters;

import '../../core/l10n/generated/app_localizations.dart';
import '../desktop_paste/desktop_paste_controller_interface.dart';

/// Who holds secure input, as far as the wording is concerned (#1617).
enum SecureInputHolderKind {
  /// A password or login prompt of macOS itself (SecurityAgent for an admin
  /// password, keychain or Touch ID prompt; loginwindow for the lock or login
  /// screen). It is no app the user can quit: the way out is to answer or
  /// close the prompt.
  systemPrompt,

  /// Terminal, whose menu has the "Secure Keyboard Entry" switch.
  terminal,

  /// iTerm2, whose app menu has the "Secure Keyboard Entry" switch.
  iterm,

  /// Any other app the system names.
  app,

  /// Nothing known about the holder.
  unknown,
}

const _terminalBundleId = 'com.apple.Terminal';
const _itermBundleId = 'com.googlecode.iterm2';

/// The macOS processes behind a password or login prompt, by bundle id and
/// by process name (the name alone arrives when the bundle id is missing).
const _systemPromptBundleIds = {
  'com.apple.SecurityAgent',
  'com.apple.loginwindow',
};
const _systemPromptNames = {'securityagent', 'loginwindow'};

/// Sorts [holder] for the wording. The bundle id wins over the name; a holder
/// with neither is [SecureInputHolderKind.unknown].
SecureInputHolderKind classifySecureInputHolder(SecureInputHolder? holder) {
  final bundleId = holder?.bundleId;
  final name = holder?.name?.trim();
  if (_systemPromptBundleIds.contains(bundleId) ||
      _systemPromptNames.contains(name?.toLowerCase())) {
    return SecureInputHolderKind.systemPrompt;
  }
  if (bundleId == _terminalBundleId) return SecureInputHolderKind.terminal;
  if (bundleId == _itermBundleId) return SecureInputHolderKind.iterm;
  if (name != null && name.isNotEmpty) return SecureInputHolderKind.app;
  return SecureInputHolderKind.unknown;
}

/// Longest app name the texts quote whole. A longer one is cut with an
/// ellipsis, so the overlay card keeps room for the clipboard sentence
/// (#1617, guard test `overlay_secure_input_card_fit_test.dart`).
const kSecureInputAppNameMax = 20;

/// [name] as the secure-input texts quote it: trimmed, and cut to
/// [kSecureInputAppNameMax] characters (ellipsis included).
String secureInputAppLabel(String name) {
  final trimmed = name.trim();
  final chars = trimmed.characters;
  if (chars.length <= kSecureInputAppNameMax) return trimmed;
  return '${chars.take(kSecureInputAppNameMax - 1).toString().trimRight()}…';
}

/// What holds the keyboard and the way out, in plain words: the first part of
/// every secure-input text. Never "quit SecurityAgent": a system prompt is
/// answered or closed.
String secureInputCause(L10n l10n, SecureInputHolder? holder) {
  return switch (classifySecureInputHolder(holder)) {
    SecureInputHolderKind.systemPrompt => l10n.pasteSecureInputSystem,
    SecureInputHolderKind.terminal => l10n.pasteSecureInputTerminal,
    SecureInputHolderKind.iterm => l10n.pasteSecureInputIterm,
    SecureInputHolderKind.app => l10n.pasteSecureInputNamed(
      secureInputAppLabel(holder!.name!),
    ),
    SecureInputHolderKind.unknown => l10n.pasteSecureInputGeneric,
  };
}

/// The notice for a paste that secure input skipped: the outcome as a short
/// [title] ("Not pasted automatically"), and a [body] with the cause, the way
/// out and where the transcript is. The overlay card shows the title as its
/// headline and the body below it, so the clipboard sentence is never cut
/// (#1617). [shortcut] is the paste key the user presses (Cmd+V on macOS).
({String title, String body}) secureInputNotice(
  L10n l10n, {
  required String shortcut,
  SecureInputHolder? holder,
}) => (
  title: l10n.pasteSecureInputTitle,
  body: secureInputNoticeBody(l10n, shortcut: shortcut, holder: holder),
);

/// The body of [secureInputNotice].
String secureInputNoticeBody(
  L10n l10n, {
  required String shortcut,
  SecureInputHolder? holder,
}) =>
    '${secureInputCause(l10n, holder)} '
    '${l10n.pasteSecureInputClipboard(shortcut)}';
