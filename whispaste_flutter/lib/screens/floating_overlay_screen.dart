/// Secondary window content for the floating recording overlay.
///
/// Runs in a separate Flutter engine created by `desktop_multi_window`.
/// Receives [RecordingState] from the main window via method channel and
/// sends commands (stop, cancel) back. Renders a pill-shaped HUD with
/// timer, waveform, and control buttons.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../core/multi_window/window_heartbeat.dart';

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

  const overlaySize = Size(480, 100);

  const options = WindowOptions(
    size: overlaySize,
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
    await windowManager.setSize(overlaySize);
    await windowManager.setAlignment(Alignment.topCenter);

    // CRITICAL: Briefly show then hide to force Windows to materialize the
    // rendering surface at the correct dimensions. Transparent frameless
    // windows that are created hidden (hiddenAtLaunch: true) get collapsed
    // to minimal size on Windows because the OS never allocates a proper
    // surface. The floating button works because it shows during init —
    // we replicate that pattern here. The window content is SizedBox.shrink()
    // at this point (idle phase), so nothing is visible.
    await windowManager.show();
    await windowManager.setAlwaysOnTop(true);
    if (Platform.isWindows) {
      // Give Windows time to process the show + style flags before hiding.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.hide();
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
  /// We can't truly destroy a secondary engine (the package has no API for it),
  /// so we hide + go inert instead of calling exit(0) which would kill the
  /// entire process.
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
    if (_inert) return null; // Window has been shut down — ignore everything.
    if (call.method == 'updateRecordingState' && call.arguments is String) {
      final decoded = decodeRecordingState(call.arguments as String);
      // Only log phase transitions — elapsed-time updates would flood the log.
      if (decoded.phase != _state.phase) {
        debugPrint('FloatingOverlay: phase → ${decoded.phase.name}');
      }
      setState(() {
        _state = decoded;
      });
    } else if (call.method == 'assertTopmost') {
      // Re-assert always-on-top from inside the secondary engine so the
      // overlay is guaranteed to appear above the main window.
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
        const targetSize = Size(480, 100);
        await windowManager.setSize(targetSize);
        if (posX != null && posX >= 0 && posY != null && posY >= 0) {
          await windowManager.setPosition(Offset(posX, posY));
        } else {
          await windowManager.setAlignment(Alignment.topCenter);
        }
        await windowManager.show();
        await windowManager.setAlwaysOnTop(true);

        // Post-show size verification — on Windows, verify the actual window
        // size matches what we requested. If Windows collapsed the geometry
        // (e.g. after sleep/wake or display change), re-assert.
        if (Platform.isWindows) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final actualSize = await windowManager.getSize();
          if (actualSize.width < 400 || actualSize.height < 60) {
            debugPrint(
              'FloatingOverlay: size mismatch! '
              'Expected $targetSize, got $actualSize — re-asserting',
            );
            await windowManager.setSize(targetSize);
            if (posX != null && posX >= 0 && posY != null && posY >= 0) {
              await windowManager.setPosition(Offset(posX, posY));
            } else {
              await windowManager.setAlignment(Alignment.topCenter);
            }
          }
        }
      } catch (e) {
        debugPrint('FloatingOverlay: showWindow failed: $e');
      }
    } else if (call.method == 'hideWindow') {
      try {
        await windowManager.hide();
      } catch (e) {
        debugPrint('FloatingOverlay: hideWindow failed: $e');
      }
    } else if (call.method == 'getWindowStatus') {
      return jsonEncode({
        'type': WindowType.floatingOverlay,
        'visible': await windowManager.isVisible(),
        'inert': _inert,
        'launchEpochMs': widget.launchEpochMs,
      });
    } else if (call.method == 'shutdown') {
      // IMPORTANT: Do NOT call exit(0) here! All windows share the same OS
      // process — exit(0) would kill the ENTIRE application including the
      // main window. Instead, go inert: stop heartbeat, hide, ignore future
      // method calls.
      debugPrint('FloatingOverlay: received shutdown — going inert');
      stopHeartbeat();
      _inert = true;
      try {
        await windowManager.hide();
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
// Floating overlay pill — standalone, no Riverpod
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

  // Done-phase hold: keep pill visible for a few seconds after completion.
  Timer? _doneHoldTimer;
  bool _showDonePill = false;

  // Hover state for drag handle + hotkey hint.
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant _FloatingOverlayPill old) {
    super.didUpdateWidget(old);
    if (widget.state.phase != old.state.phase) {
      _syncAnimations();

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
    _doneHoldTimer?.cancel();
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

  /// Start native window drag. Saves position on completion.
  Future<void> _startDrag() async {
    await windowManager.startDragging();
    final pos = await windowManager.getPosition();
    widget.onPositionChanged(pos);
  }

  /// Timer text color — amber at 75%, red at 90% of max duration.
  Color _timerColor() {
    final maxSec = widget.state.maxRecordDurationSeconds;
    if (maxSec <= 0) return Colors.white;
    final fraction = widget.state.elapsed.inSeconds / maxSec;
    if (fraction > 0.9) return WpColorsDark.errorGradient.colors.first;
    if (fraction > 0.75) return WpColorsDark.processingGradient.colors.first;
    return Colors.white;
  }

  /// Context-aware done message based on afterAction setting.
  String _doneMessage(L10n l10n) {
    return switch (widget.state.afterAction) {
      'paste' => l10n.overlayDonePasted,
      'copy_and_paste' => l10n.overlayDoneBoth,
      'copy' => l10n.overlayDone,
      _ => l10n.overlayDoneReady,
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

    // Fixed-size transparent container when idle — ensures the window always
    // has content to prevent thin-line rendering on Windows frameless windows.
    if (!showPill) return const SizedBox(width: 480, height: 100);

    final l10n = L10n.of(context);
    final pillRadius = BorderRadius.circular(38);
    final semanticLabel = _semanticLabel(displayPhase, l10n);
    final decoded = widget.state;
    final hotkeyLabel = decoded.hotkeyLabel;

    return Semantics(
      liveRegion: true,
      label: semanticLabel,
      child: Center(
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onPanStart: (_) => _startDrag(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Main pill.
                Container(
                  constraints:
                      const BoxConstraints(maxWidth: 480, minHeight: 56),
                  decoration: BoxDecoration(
                    color: WpColorsDark.background.withValues(alpha: 0.92),
                    borderRadius: pillRadius,
                    boxShadow: WpShadows.elevated,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WpSpacing.md,
                          vertical: WpSpacing.xs,
                        ),
                        child: _buildContent(context, displayPhase, l10n),
                      ),
                      // Badges row (AI mode + privacy) — recording only.
                      if (displayPhase == RecordingPhase.recording)
                        _buildBadgesRow(decoded, l10n),
                      // Transcript preview — transcribing/processing.
                      if ((displayPhase == RecordingPhase.transcribing ||
                              displayPhase == RecordingPhase.processing) &&
                          decoded.transcript != null &&
                          decoded.transcript!.isNotEmpty)
                        _buildTranscriptPreview(decoded),
                      _buildProgressBar(displayPhase),
                    ],
                  ),
                ),
                // Drag handle indicator — fades on hover.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 2,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: (_isHovered &&
                              displayPhase != RecordingPhase.done)
                          ? 1.0
                          : 0.0,
                      duration: WpMotion.fast,
                      child: Center(
                        child: Text(
                          '⠿',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                WpColorsDark.textMuted.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Hotkey hint — fades on hover, positioned below the pill.
                if (hotkeyLabel != null && hotkeyLabel.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -24,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: WpMotion.fast,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  WpColorsDark.surface.withValues(alpha: 0.9),
                              borderRadius: WpRadius.borderSm,
                            ),
                            child: Text(
                              hotkeyLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                color: WpColorsDark.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- Badges row (privacy + AI mode) during recording ---------------------

  Widget _buildBadgesRow(DecodedRecordingState decoded, L10n l10n) {
    final badges = <Widget>[];

    // Privacy badge.
    if (decoded.isLocalStt != null) {
      final isLocal = decoded.isLocalStt!;
      final color = isLocal ? WpColorsDark.success : WpColorsDark.accent;
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xs,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: WpRadius.borderFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLocal ? '🔒' : '☁️',
                style: const TextStyle(fontSize: 10),
              ),
              const SizedBox(width: 3),
              Text(
                isLocal
                    ? l10n.overlayProcessingLocal
                    : l10n.overlayProcessingCloud,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // AI mode badge.
    if (decoded.aiMode != null && decoded.aiMode!.isNotEmpty) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xs,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: WpColorsDark.accent.withValues(alpha: 0.12),
            borderRadius: WpRadius.borderFull,
          ),
          child: Text(
            '🤖 ${decoded.aiMode}',
            style: const TextStyle(
              fontSize: 10,
              color: WpColorsDark.textSecondary,
            ),
          ),
        ),
      );
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return AnimatedSize(
      duration: WpMotion.fast,
      curve: WpMotion.defaultCurve,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: WpSpacing.xs,
          left: WpSpacing.md,
          right: WpSpacing.md,
        ),
        child: Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xxs,
          alignment: WrapAlignment.center,
          children: badges,
        ),
      ),
    );
  }

  // -- Transcript preview during transcribing/processing -------------------

  Widget _buildTranscriptPreview(DecodedRecordingState decoded) {
    final text = decoded.transcript!;
    final truncated = text.length > 50 ? '${text.substring(0, 50)}…' : text;

    return AnimatedSize(
      duration: WpMotion.smooth,
      curve: WpMotion.defaultCurve,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: WpSpacing.xs,
          left: WpSpacing.md,
          right: WpSpacing.md,
        ),
        child: Text(
          truncated,
          style: const TextStyle(
            fontSize: 11,
            color: WpColorsDark.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, RecordingPhase phase, L10n l10n) {
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
        final timerColor = _timerColor();
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
            // Timer with color warnings.
            AnimatedDefaultTextStyle(
              duration: WpMotion.fast,
              style: TextStyle(
                color: timerColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: Text(_formatElapsed(widget.state.elapsed)),
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
            const Icon(
              LucideIcons.circleCheck,
              size: 16,
              color: WpColorsDark.success,
            ),
            const SizedBox(width: WpSpacing.xs),
            Text(
              _doneMessage(l10n),
              style: const TextStyle(
                color: WpColorsDark.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case RecordingPhase.error:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.triangleAlert,
              size: 16,
              color: Colors.redAccent,
            ),
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

  String _semanticLabel(RecordingPhase phase, L10n l10n) {
    return switch (phase) {
      RecordingPhase.recording =>
        '${l10n.overlayRecording} ${_formatElapsed(widget.state.elapsed)}',
      RecordingPhase.transcribing => l10n.overlayTranscribing,
      RecordingPhase.processing => l10n.overlayRefining,
      RecordingPhase.done => _doneMessage(l10n),
      RecordingPhase.error => widget.state.errorMessage ?? 'Error',
      _ => '',
    };
  }

  List<Widget> _buildWaveformBars() {
    if (_levelHistory.isEmpty) return [];
    const barCount = 16;
    const barWidth = 3.0;
    const maxHeight = 24.0;
    const gap = 2.0;

    final bars = <Widget>[];
    final startIdx = _levelHistory.length > barCount
        ? _levelHistory.length - barCount
        : 0;
    for (int i = startIdx; i < _levelHistory.length; i++) {
      final level = _levelHistory[i].clamp(0.0, 1.0);
      final height = (level * maxHeight).clamp(3.0, maxHeight);
      bars.add(
        AnimatedContainer(
          duration: WpMotion.fast,
          width: barWidth,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: gap / 2),
          decoration: BoxDecoration(
            color: WpColorsDark.accent.withValues(
              alpha: level > 0.3 ? 0.85 : 0.5,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }
    return bars;
  }

  Widget _buildProgressBar(RecordingPhase phase) {
    const height = 3.0;

    if (phase == RecordingPhase.recording) {
      final maxSec = widget.state.maxRecordDurationSeconds;
      if (maxSec > 0) {
        // Determinate progress when max duration is known.
        final progress =
            (widget.state.elapsed.inSeconds / maxSec).clamp(0.0, 1.0);
        final fraction = widget.state.elapsed.inSeconds / maxSec;
        final barColor = fraction > 0.9
            ? WpColorsDark.errorGradient.colors.first
            : fraction > 0.75
                ? WpColorsDark.processingGradient.colors.first
                : WpColorsDark.accent;
        return AnimatedContainer(
          duration: WpMotion.fast,
          height: height,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              height: height,
              color: barColor,
            ),
          ),
        );
      }
      // Thin accent line when no max duration.
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
      return Container(height: height, color: WpColorsDark.success);
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
            padding: const EdgeInsets.all(10),
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
              gradient: WpColorsDark.recordingGradient,
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
