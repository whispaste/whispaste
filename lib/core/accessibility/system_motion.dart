/// Takes the system setting "Reduce motion" into every Flutter engine (#1756).
///
/// No desktop embedder sets `AccessibilityFeatures.disableAnimations`, so
/// `MediaQuery.disableAnimations` stayed false for users who asked the system
/// for less motion, and every animation gated on it kept running. Each native
/// shell (macOS `SystemMotionHost.swift`, Windows `system_motion_channel.cpp`,
/// Linux `system_motion_host.cc`) opens [kSystemMotionChannelName] on every
/// engine it boots: main window, floating overlay, floating button, tray
/// panel, side panel, snippet picker. Dart asks once with `reduceMotion` and
/// receives `reduceMotionChanged` whenever the user flips the switch.
///
/// [SystemMotionScope] sits at the root of each engine (directly below the
/// `View` that `runApp` inserts) and folds the value into `MediaQuery`, so
/// all existing `MediaQuery.disableAnimationsOf` checks follow the system
/// without further changes. The value is OR-ed with what the embedder
/// reports: if a future Flutter sets the flag itself, nothing switches off.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('SystemMotion');

/// Channel shared by all engines; mirrored in the three native shells.
const String kSystemMotionChannelName = 'com.whispaste.system_motion';

/// Folds the system "Reduce motion" setting into
/// [MediaQueryData.disableAnimations] for [child].
class SystemMotionScope extends StatefulWidget {
  const SystemMotionScope({
    super.key,
    required this.child,
    this.channel = const MethodChannel(kSystemMotionChannelName),
  });

  final Widget child;

  /// Injected in tests; production uses the shared channel.
  final MethodChannel channel;

  @override
  State<SystemMotionScope> createState() => _SystemMotionScopeState();
}

class _SystemMotionScopeState extends State<SystemMotionScope> {
  bool _systemReduceMotion = false;

  /// Set once a push arrived, so a late answer to the initial read never
  /// overwrites a newer value.
  bool _pushed = false;

  @override
  void initState() {
    super.initState();
    widget.channel.setMethodCallHandler(_onCall);
    unawaited(_readInitial());
  }

  @override
  void dispose() {
    widget.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _readInitial() async {
    bool? value;
    try {
      value = await widget.channel.invokeMethod<bool>('reduceMotion');
    } on MissingPluginException {
      // Shell without the channel (tests, debug mains): keep the default.
      return;
    } on PlatformException catch (e) {
      _log.warning('[system-motion] read failed: ${e.code}');
      return;
    }
    if (!mounted || _pushed || value == null) return;
    _apply(value);
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'reduceMotionChanged') {
      throw MissingPluginException(call.method);
    }
    final value = call.arguments;
    if (value is! bool || !mounted) return;
    _pushed = true;
    _apply(value);
  }

  void _apply(bool value) {
    // One line per engine and change: the proof that the handover arrived
    // (lab runs, support logs); never on every build.
    _log.info('[system-motion] reduceMotion=$value');
    if (value == _systemReduceMotion) return;
    setState(() => _systemReduceMotion = value);
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    // Always the same tree shape: wrapping only when reduced would remount
    // the whole engine UI (and lose its state) on every switch.
    return MediaQuery(
      data: data.copyWith(
        disableAnimations: data.disableAnimations || _systemReduceMotion,
      ),
      child: widget.child,
    );
  }
}
