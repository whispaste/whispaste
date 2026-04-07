/// Secondary window content for the floating recording overlay.
///
/// Runs in a separate Flutter engine created by `desktop_multi_window`.
/// Receives [RecordingState] from the main window via method channel and
/// sends commands (stop, cancel) back. Delegates all pill rendering to
/// the shared [RecordingPill] widget for visual consistency with the
/// in-window overlay.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/theme.dart';
import '../core/recording/recording_state.dart';
import '../core/multi_window/multi_window_types.dart';
import '../core/multi_window/window_heartbeat.dart';
import '../widgets/recording_pill.dart';

/// Entry point for the floating overlay secondary window.
Future<void> runFloatingOverlayWindow(WindowController controller) async {
  await windowManager.ensureInitialized();
  var launchEpochMs = 0;
  try {
    final args = jsonDecode(controller.arguments) as Map<String, dynamic>;
    launchEpochMs = (args['launchEpochMs'] as num?)?.toInt() ?? 0;
  } catch (e) {
    debugPrint('FloatingOverlay: failed to parse arguments: $e');
  }

  // Start at 1x1 -- effectively invisible but the OS keeps the rendering
  // surface alive. We NEVER call hide()/show() after init because
  // window_manager 0.5.1 on Windows has a dead-code bug in Show() where
  // SWP_FRAMECHANGED never executes, causing transparent frameless windows
  // to lose their compositor surface after a hide->show cycle.
  // Instead we toggle visibility by resizing: 1x1 = hidden, 520x100 = visible.
  const hiddenSize = Size(1, 1);

  const options = WindowOptions(
    size: hiddenSize,
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    if (Platform.isWindows) {
      await windowManager.setHasShadow(false);
    }
    // Show at 1x1 -- the window is "shown" from the OS perspective so the
    // rendering surface is properly allocated, but at 1x1 it is invisible
    // and does not intercept mouse events.
    await windowManager.show();
    await windowManager.setAlwaysOnTop(true);
  });

  runApp(
    _FloatingOverlayApp(controller: controller, launchEpochMs: launchEpochMs),
  );
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class _FloatingOverlayApp extends StatefulWidget {
  const _FloatingOverlayApp({
    required this.controller,
    required this.launchEpochMs,
  });
  final WindowController controller;
  final int launchEpochMs;

  @override
  State<_FloatingOverlayApp> createState() => _FloatingOverlayAppState();
}

class _FloatingOverlayAppState extends State<_FloatingOverlayApp>
    with WindowHeartbeat {
  DecodedRecordingState _state = const DecodedRecordingState();

  /// When true, this window has been shut down and ignores all method calls.
  bool _inert = false;

  @override
  void initState() {
    super.initState();
    try {
      widget.controller.setWindowMethodHandler(_onMethodCall);
    } catch (e) {
      debugPrint('FloatingOverlay: failed to register method handler: $e');
    }
    startHeartbeat();
  }

  @override
  void dispose() {
    stopHeartbeat();
    super.dispose();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (_inert) return null; // Window has been shut down -- ignore everything.
    if (call.method == 'updateRecordingState' && call.arguments is String) {
      final decoded = decodeRecordingState(call.arguments as String);
      // Only log phase transitions -- elapsed-time updates would flood the log.
      if (decoded.phase != _state.phase) {
        debugPrint('FloatingOverlay: phase -> ${decoded.phase.name}');
      }
      setState(() {
        _state = decoded;
      });
    } else if (call.method == 'assertTopmost') {
      try {
        await windowManager.setAlwaysOnTop(true);
      } catch (_) {}
    } else if (call.method == 'showWindow') {
      // Parse optional saved position from arguments.
      double? posX, posY;
      if (call.arguments is String) {
        try {
          final pos =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          posX = (pos['x'] as num?)?.toDouble();
          posY = (pos['y'] as num?)?.toDouble();
        } catch (_) {}
      }
      try {
        // Resize from 1x1 (hidden) -> 520x100 (visible). The window is
        // already "shown" from the OS perspective -- we never hide/show,
        // we only resize. This avoids the window_manager Show() bug that
        // breaks transparent frameless window compositing on Windows.
        const targetSize = Size(520, 100);
        await windowManager.setSize(targetSize);
        if (posX != null && posX >= 0 && posY != null && posY >= 0) {
          await windowManager.setPosition(Offset(posX, posY));
        } else {
          await windowManager.setAlignment(Alignment.topCenter);
        }
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        debugPrint('FloatingOverlay: showWindow failed: $e');
      }
    } else if (call.method == 'hideWindow') {
      try {
        // Shrink to 1x1 instead of hiding -- keeps the rendering surface
        // alive so the next show (resize) works correctly.
        await windowManager.setSize(const Size(1, 1));
      } catch (e) {
        debugPrint('FloatingOverlay: hideWindow failed: $e');
      }
    } else if (call.method == 'getWindowStatus') {
      final size = await windowManager.getSize();
      final isExpanded = size.width > 10 && size.height > 10;
      return jsonEncode({
        'type': WindowType.floatingOverlay,
        'visible': isExpanded,
        'inert': _inert,
        'launchEpochMs': widget.launchEpochMs,
      });
    } else if (call.method == 'shutdown') {
      debugPrint('FloatingOverlay: received shutdown -- going inert');
      stopHeartbeat();
      _inert = true;
      try {
        await windowManager.setSize(const Size(1, 1));
      } catch (_) {}
    }
    return null;
  }

  void _stop() => commandChannel.invokeMethod('stopRecording');
  void _cancel() => commandChannel.invokeMethod('cancelRecording');
  void _savePosition(Offset pos) {
    commandChannel.invokeMethod(
      'saveOverlayPosition',
      jsonEncode({'x': pos.dx, 'y': pos.dy}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      darkTheme: wpDarkTheme(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _FloatingOverlayPill(
          state: _state,
          onStop: _stop,
          onCancel: _cancel,
          onPositionChanged: _savePosition,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating overlay pill -- thin wrapper around shared RecordingPill
// ---------------------------------------------------------------------------

class _FloatingOverlayPill extends StatefulWidget {
  const _FloatingOverlayPill({
    required this.state,
    required this.onStop,
    required this.onCancel,
    required this.onPositionChanged,
  });

  final DecodedRecordingState state;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final ValueChanged<Offset> onPositionChanged;

  @override
  State<_FloatingOverlayPill> createState() => _FloatingOverlayPillState();
}

class _FloatingOverlayPillState extends State<_FloatingOverlayPill> {
  // Done-phase hold: keep pill visible for a few seconds after completion.
  Timer? _doneHoldTimer;
  bool _showDonePill = false;

  @override
  void didUpdateWidget(covariant _FloatingOverlayPill old) {
    super.didUpdateWidget(old);
    if (widget.state.phase != old.state.phase) {
      // Hold the "done" pill visible for 3 seconds before hiding.
      if (widget.state.phase == RecordingPhase.done) {
        _doneHoldTimer?.cancel();
        _showDonePill = true;
        _doneHoldTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showDonePill = false);
        });
      } else if (widget.state.phase != RecordingPhase.idle) {
        _doneHoldTimer?.cancel();
        _showDonePill = false;
      }
    }
  }

  @override
  void dispose() {
    _doneHoldTimer?.cancel();
    super.dispose();
  }

  /// Start native window drag. Saves position on completion.
  Future<void> _startDrag() async {
    await windowManager.startDragging();
    final pos = await windowManager.getPosition();
    widget.onPositionChanged(pos);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Context-aware done message based on afterAction setting.
  /// Delegates to [RecordingPill.doneMessageFor] for single source of truth.
  String _doneMessage(L10n l10n) =>
      RecordingPill.doneMessageFor(widget.state.afterAction, l10n);

  String _semanticLabel(RecordingPhase phase, L10n l10n) {
    return switch (phase) {
      RecordingPhase.recording =>
        '${l10n.overlayRecording} ${_formatDuration(widget.state.elapsed)}',
      RecordingPhase.transcribing => l10n.overlayTranscribing,
      RecordingPhase.processing => l10n.overlayRefining,
      RecordingPhase.done => _doneMessage(l10n),
      RecordingPhase.error => widget.state.errorMessage ?? 'Error',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.state.phase;
    // Show pill for active phases, or during the done-hold period.
    final showPill = phase != RecordingPhase.idle || _showDonePill;
    // When holding the done pill, display as "done" even though phase is idle.
    final displayPhase = (phase == RecordingPhase.idle && _showDonePill)
        ? RecordingPhase.done
        : phase;

    // Fixed-size transparent container when idle -- ensures the window always
    // has content to prevent thin-line rendering on Windows frameless windows.
    if (!showPill) return const SizedBox(width: 520, height: 100);

    final l10n = L10n.of(context);
    final semanticLabel = _semanticLabel(displayPhase, l10n);
    final decoded = widget.state;

    return Semantics(
      liveRegion: true,
      label: semanticLabel,
      child: Center(
        child: GestureDetector(
          onPanStart: (_) => _startDrag(),
          child: RecordingPill(
            phase: displayPhase,
            elapsed: decoded.elapsed,
            audioLevel: decoded.audioLevel,
            maxDurationSeconds: decoded.maxRecordDurationSeconds,
            isLocalStt: decoded.isLocalStt,
            aiMode: decoded.aiMode,
            transcript: decoded.transcript,
            errorMessage: decoded.errorMessage,
            afterAction: decoded.afterAction,
            hotkeyLabel: decoded.hotkeyLabel,
            showDragHandle: true,
            isDarkOnly: true,
            onStop: widget.onStop,
            onCancel: phase == RecordingPhase.idle ? null : widget.onCancel,
          ),
        ),
      ),
    );
  }
}
