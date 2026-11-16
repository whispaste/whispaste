/// Reports app-internal input to the central nudge gate (growth review R-11).
///
/// Pointer and keyboard events inside the window count as user activity.
/// Nudges wait for [kNudgeIdleThreshold] of such silence. Global input
/// outside the app is not observed: it is not reliably available on all
/// three desktop platforms, and a dictation is covered by the busy check.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/nudge_gate.dart';

class WpNudgeInputListener extends ConsumerStatefulWidget {
  const WpNudgeInputListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpNudgeInputListener> createState() =>
      _NudgeInputListenerState();
}

class _NudgeInputListenerState extends ConsumerState<WpNudgeInputListener> {
  bool _onKey(KeyEvent event) {
    _noteInput();
    return false;
  }

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

  void _noteInput() => ref.read(nudgeGateProvider).noteInput();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _noteInput(),
      onPointerMove: (_) => _noteInput(),
      onPointerHover: (_) => _noteInput(),
      onPointerSignal: (_) => _noteInput(),
      child: widget.child,
    );
  }
}
