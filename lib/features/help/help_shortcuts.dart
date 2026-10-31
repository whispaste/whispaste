/// App-wide shortcuts that open the Help hub (WP-78): F1 and Cmd/Ctrl+?, the
/// two keys people reach for when they look for help.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bindings for [CallbackShortcuts] that call [openHelp].
Map<ShortcutActivator, VoidCallback> helpShortcuts(VoidCallback openHelp) {
  final isMac = Platform.isMacOS;
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
