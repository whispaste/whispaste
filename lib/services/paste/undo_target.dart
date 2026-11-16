/// Platform contract of the keystroke undo (#428, #578): which window is in
/// front, bringing the paste target back, and whether it is a terminal.
///
/// Each host has to implement the native channel methods
/// `undoPlatformSupport`, `foregroundWindow` and `activateTarget` (plus
/// `mouseIdleOutsideApp` in `inputIdleSnapshot`). Linux X11 (#579),
/// Windows (#580) and macOS (#581) do; Wayland does not (see internal-notes,
/// "Rückgängig nach Auswahl-Bearbeitung"). A host that lacks one
/// answers it as unsupported and the undo copies the original text to the
/// clipboard instead of sending a keystroke into the wrong place.
library;

import 'package:flutter/foundation.dart';

/// The window that has the keyboard focus right now.
@immutable
class ForegroundWindow {
  const ForegroundWindow({
    required this.id,
    this.isOwn = false,
    this.isTerminal = false,
  });

  /// Same vocabulary as the paste target id (bundle id, process name).
  final String id;

  /// A WhisPaste window, e.g. after the click on the undo action.
  final bool isOwn;

  /// A terminal, also one embedded in a code editor: Ctrl+Z suspends the
  /// running process there instead of undoing.
  final bool isTerminal;
}

/// What the host of this platform can answer for the keystroke undo.
@immutable
class UndoPlatformSupport {
  const UndoPlatformSupport({
    this.foregroundWindow = false,
    this.activateTarget = false,
    this.terminalDetection = false,
    this.outsideMouseIdle = false,
  });

  /// Nothing is answered (no handler, Wayland, a failed probe).
  static const none = UndoPlatformSupport();

  final bool foregroundWindow;
  final bool activateTarget;
  final bool terminalDetection;
  final bool outsideMouseIdle;

  /// The keystroke is only sent when the host answers all four.
  bool get complete =>
      foregroundWindow &&
      activateTarget &&
      terminalDetection &&
      outsideMouseIdle;

  factory UndoPlatformSupport.fromMap(Map<Object?, Object?> raw) =>
      UndoPlatformSupport(
        foregroundWindow: raw['foregroundWindow'] == true,
        activateTarget: raw['activateTarget'] == true,
        terminalDetection: raw['terminalDetection'] == true,
        outsideMouseIdle: raw['outsideMouseIdle'] == true,
      );
}
