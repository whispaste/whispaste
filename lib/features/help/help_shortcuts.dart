/// App-wide shortcuts that open the Help hub (ticket): F1 and Cmd/Ctrl+?, the
/// two keys people reach for when they look for help.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bindings for [CallbackShortcuts] that call [openHelp].
Map<ShortcutActivator, VoidCallback> helpShortcuts(VoidCallback openHelp) {
  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  return <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.f1): openHelp,
    SingleActivator(
      LogicalKeyboardKey.slash,
      shift: true,
      control: !isMac,
      meta: isMac,
    ): openHelp,
  };
}
