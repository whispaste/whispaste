/// Secondary window content for the floating recording overlay.
///
/// Runs in a separate Flutter engine created by `desktop_multi_window`.
/// Receives [RecordingState] from the main window via method channel and
/// sends commands (stop, cancel) back. Renders a pill-shaped HUD with
/// timer, waveform, and control buttons.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../core/recording/recording_state.dart';
import '../core/multi_window/multi_window_types.dart';

/// Entry point for the floating overlay secondary window.
Future<void> runFloatingOverlayWindow(WindowController controller) async {
  await windowManager.ensureInitialized();

  const overlayWidth = 480.0;
  const overlayHeight = 72.0;

  const options = WindowOptions(
    size: Size(overlayWidth, overlayHeight),
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
    // Position at top-center of screen.
    await windowManager.setAlignment(Alignment.topCenter);
    await windowManager.show();
  });

  runApp(_FloatingOverlayApp(controller: controller));
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class _FloatingOverlayApp extends StatefulWidget {
  const _FloatingOverlayApp({required this.controller});
  final WindowController controller;

  @override
  State<_FloatingOverlayApp> createState() => _FloatingOverlayAppState();
}

class _FloatingOverlayAppState extends State<_FloatingOverlayApp> {
  RecordingState _state = const RecordingState();

  @override
  void initState() {
    super.initState();
    try {
      widget.controller.setWindowMethodHandler(_onMethodCall);
    } catch (e) {
      debugPrint('FloatingOverlay: failed to register method handler: $e');
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'updateRecordingState' && call.arguments is String) {
      setState(() {
        _state = decodeRecordingState(call.arguments as String);
      });
    }
    return null;
  }

  void _stop() => commandChannel.invokeMethod('stopRecording');
  void _cancel() => commandChannel.invokeMethod('cancelRecording');

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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating overlay pill — standalone, no Riverpod
// ---------------------------------------------------------------------------

class _FloatingOverlayPill extends StatefulWidget {
  const _FloatingOverlayPill({
    required this.state,
    required this.onStop,
    required this.onCancel,
  });

  final RecordingState state;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  State<_FloatingOverlayPill> createState() => _FloatingOverlayPillState();
}

class _FloatingOverlayPillState extends State<_FloatingOverlayPill>
    with TickerProviderStateMixin {
  // Waveform level history.
  final List<double> _levelHistory = [];
  static const int _maxLevels = 20;

  // Pulsing red dot.
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Shimmer for indeterminate progress.
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant _FloatingOverlayPill old) {
    super.didUpdateWidget(old);
    if (widget.state.phase != old.state.phase) _syncAnimations();
    // Update waveform buffer.
    if (widget.state.phase == RecordingPhase.recording) {
      _levelHistory.add(widget.state.audioLevel);
      if (_levelHistory.length > _maxLevels) _levelHistory.removeAt(0);
    }
  }

  void _syncAnimations() {
    final phase = widget.state.phase;
    if (phase == RecordingPhase.recording) {
      _pulseCtrl.repeat(reverse: true);
      _shimmerCtrl.stop();
    } else if (phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.processing) {
      _pulseCtrl.stop();
      _shimmerCtrl.repeat();
    } else {
      _pulseCtrl.stop();
      _shimmerCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // Format elapsed time as M:SS.
  String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.state.phase;
    if (phase == RecordingPhase.idle) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final pillRadius = BorderRadius.circular(38);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, minHeight: 64),
        decoration: BoxDecoration(
          borderRadius: pillRadius,
          boxShadow: WpShadows.elevated,
        ),
        child: ClipRRect(
          borderRadius: pillRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xD9141926),
                borderRadius: pillRadius,
                border: Border.all(color: WpColorsDark.borderDefault),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.md,
                      vertical: WpSpacing.sm,
                    ),
                    child: _buildContent(context, phase, l10n),
                  ),
                  _buildProgressBar(phase),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, RecordingPhase phase, L10n l10n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cancel button.
        if (phase != RecordingPhase.done)
          _IconBtn(
            icon: LucideIcons.x,
            tooltip: l10n.overlayCancel,
            onPressed: widget.onCancel,
          ),
        const SizedBox(width: WpSpacing.sm),

        // Center content (phase-specific).
        Flexible(child: _buildCenter(phase, l10n)),
        const SizedBox(width: WpSpacing.sm),

        // Stop button (recording only).
        if (phase == RecordingPhase.recording)
          _StopBtn(onPressed: widget.onStop),
      ],
    );
  }

  Widget _buildCenter(RecordingPhase phase, L10n l10n) {
    switch (phase) {
      case RecordingPhase.recording:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing red dot.
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, a) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withValues(alpha: _pulseAnim.value),
                ),
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            // Timer.
            Text(
              _formatElapsed(widget.state.elapsed),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            // Simplified waveform (no bars — just level indicator).
            ..._buildWaveformBars(),
          ],
        );

      case RecordingPhase.transcribing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WpColorsDark.accent,
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            Text(
              l10n.overlayTranscribing,
              style: const TextStyle(
                color: WpColorsDark.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        );

      case RecordingPhase.processing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WpColorsDark.accent,
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            Text(
              l10n.overlayRefining,
              style: const TextStyle(
                color: WpColorsDark.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        );

      case RecordingPhase.done:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.check, size: 16, color: WpColorsDark.success),
            const SizedBox(width: WpSpacing.xs),
            Text(
              l10n.overlayDone,
              style: const TextStyle(color: WpColorsDark.success, fontSize: 13),
            ),
          ],
        );

      case RecordingPhase.error:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.triangleAlert,
                size: 16, color: Colors.redAccent),
            const SizedBox(width: WpSpacing.xs),
            Flexible(
              child: Text(
                widget.state.errorMessage ?? 'Error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

      case RecordingPhase.idle:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildWaveformBars() {
    if (_levelHistory.isEmpty) return [];
    const barCount = 16;
    const barWidth = 3.0;
    const maxHeight = 24.0;
    const gap = 2.0;

    final bars = <Widget>[];
    final startIdx =
        _levelHistory.length > barCount ? _levelHistory.length - barCount : 0;
    for (int i = startIdx; i < _levelHistory.length; i++) {
      final level = _levelHistory[i].clamp(0.0, 1.0);
      final height = (level * maxHeight).clamp(3.0, maxHeight);
      bars.add(AnimatedContainer(
        duration: WpMotion.fast,
        width: barWidth,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: gap / 2),
        decoration: BoxDecoration(
          color: WpColorsDark.accent.withValues(alpha: level > 0.3 ? 0.85 : 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ));
    }
    return bars;
  }

  Widget _buildProgressBar(RecordingPhase phase) {
    const height = 3.0;

    if (phase == RecordingPhase.recording) {
      // Thin accent line (no percentage since we don't have maxDuration here).
      return Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WpColorsDark.accent.withValues(alpha: 0.6),
              WpColorsDark.accent,
            ],
          ),
        ),
      );
    }

    if (phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.processing) {
      // Indeterminate shimmer.
      return AnimatedBuilder(
        animation: _shimmerCtrl,
        builder: (_, a) {
          final offset = _shimmerCtrl.value;
          return Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + 2 * offset, 0),
                end: Alignment(-0.5 + 2 * offset, 0),
                colors: [
                  Colors.transparent,
                  WpColorsDark.accent.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          );
        },
      );
    }

    if (phase == RecordingPhase.done) {
      return Container(
        height: height,
        color: WpColorsDark.success,
      );
    }

    return const SizedBox(height: height);
  }
}

// ---------------------------------------------------------------------------
// Button helpers (standalone — no Riverpod)
// ---------------------------------------------------------------------------

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: WpColorsDark.textMuted),
          ),
        ),
      ),
    );
  }
}

class _StopBtn extends StatelessWidget {
  const _StopBtn({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: L10n.of(context).overlayStop,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // Red gradient — consistent with FAB stop state.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              ),
            ),
            child: const Center(
              child: Icon(LucideIcons.square, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
