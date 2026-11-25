/// App-wide shortcuts that also work when no widget inside the app holds
/// keyboard focus (#1845).
///
/// [CallbackShortcuts] only sees keys while focus sits below it. After a
/// mouse click on a sidebar item, or right after launch, focus can rest on
/// the root scope or on the title bar outside the shell, and F1 or Ctrl+,
/// then did nothing (found on Windows and Linux). This widget keeps the
/// [CallbackShortcuts] for the normal case and adds a [HardwareKeyboard]
/// handler for the case where focus is outside its subtree, so every press
/// fires exactly once. While a dialog or another route covers the page, the
/// handler stays quiet, as the shortcuts did before.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WpGlobalShortcuts extends StatefulWidget {
  const WpGlobalShortcuts({
    super.key,
    required this.bindings,
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  State<WpGlobalShortcuts> createState() => _WpGlobalShortcutsState();
}

class _WpGlobalShortcutsState extends State<WpGlobalShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Whether keyboard focus sits inside this widget, where the
  /// [CallbackShortcuts] below already handles the key.
  bool _focusInside() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused == context) return true;
    var inside = false;
    focused.visitAncestorElements((e) {
      inside = e == context;
      return !inside;
    });
    return inside;
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || _focusInside()) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    for (final entry in widget.bindings.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      CallbackShortcuts(bindings: widget.bindings, child: widget.child);
}
