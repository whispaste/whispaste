import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../core/recording/recording_state.dart';

/// Recording FAB — phase-aware with distinct visual states.
///
/// | Phase        | Visual                                          |
/// |--------------|-------------------------------------------------|
/// | idle         | Accent gradient, mic icon, hover scale           |
/// | recording    | Red gradient, stop icon, pulse animation          |
/// | transcribing | Amber gradient, rotating loader, non-interactive |
/// | done         | Green, check icon (brief flash before reset)     |
/// | error        | Red, alert icon (brief flash before reset)        |
///
/// When [readiness] is not [RecordingReadiness.ready] and phase is idle:
/// | Readiness         | Visual                                       |
/// |-------------------|----------------------------------------------|
/// | serverMissing     | Muted gradient, download icon, still tappable |
/// | serverDownloading | Muted gradient, spinning loader               |
/// | modelMissing      | Muted gradient, download icon, still tappable |
class WpRecordingFab extends StatefulWidget {
  const WpRecordingFab({
    super.key,
    required this.phase,
    required this.onPressed,
    this.readiness = RecordingReadiness.ready,
  });

  final RecordingPhase phase;
  final VoidCallback onPressed;
  final RecordingReadiness readiness;

  @override
  State<WpRecordingFab> createState() => _WpRecordingFabState();
}

class _WpRecordingFabState extends State<WpRecordingFab>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  late final AnimationController _spinController;
  // Subtle body scale pulse during recording (complements the ring).
  late final AnimationController _bodyPulseController;
  late final Animation<double> _bodyPulseScale;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    // Pulse ring animation for recording state (expanding ring that fades out)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 1.8,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    // Spin animation for transcribing/processing state
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Body scale pulse during recording
    _bodyPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _bodyPulseScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _bodyPulseController, curve: Curves.easeInOut),
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(WpRecordingFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) _syncAnimations();
  }

  void _syncAnimations() {
    // Pulse ring + body pulse: only during recording
    if (widget.phase == RecordingPhase.recording) {
      _pulseController.repeat();
      _bodyPulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
      _bodyPulseController.stop();
      _bodyPulseController.reset();
    }
    // Spin: only during transcribing or processing
    if (widget.phase == RecordingPhase.transcribing ||
        widget.phase == RecordingPhase.processing) {
      _spinController.repeat();
    } else {
      _spinController.stop();
      _spinController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    _bodyPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final phase = widget.phase;
    final readiness = widget.readiness;
    final notReady =
        phase == RecordingPhase.idle && readiness != RecordingReadiness.ready;

    // FAB is tappable when idle (including not-ready — shows info toast)
    // or recording. Non-interactive during transcribing/processing/done/error.
    final isInteractive =
        phase == RecordingPhase.idle || phase == RecordingPhase.recording;

    final tooltip = notReady
        ? switch (readiness) {
            RecordingReadiness.serverDownloading =>
              l10n.tooltipEngineDownloading,
            RecordingReadiness.serverMissing => l10n.tooltipEngineNotReady,
            RecordingReadiness.modelMissing => l10n.tooltipModelMissing,
            RecordingReadiness.ready => '', // unreachable
          }
        : switch (phase) {
            RecordingPhase.idle => l10n.tooltipRecord,
            RecordingPhase.recording => l10n.tooltipStopRecord,
            RecordingPhase.transcribing ||
            RecordingPhase.processing => l10n.tooltipProcessing,
            RecordingPhase.done => l10n.statusTranscriptionDone,
            RecordingPhase.error => '',
          };

    final gradient = notReady
        ? _mutedGradient(isDark)
        : _gradient(phase, isDark);
    final icon = notReady ? _readinessIcon(readiness) : _icon(phase);

    return Semantics(
      label: tooltip,
      button: isInteractive,
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: isInteractive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            // Extra space for the expanding pulse ring.
            width: WpLayout.fabSize * 1.8,
            height: WpLayout.fabSize * 1.8,
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _pulseController,
                  _spinController,
                  _bodyPulseController,
                ]),
                builder: (context, child) {
                  final bodyScale = switch (phase) {
                    RecordingPhase.recording => _bodyPulseScale.value,
                    RecordingPhase.idle when _isHovered => 1.06,
                    _ => 1.0,
                  };
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding pulse ring (recording only)
                      if (phase == RecordingPhase.recording)
                        _buildPulseRing(WpLayout.fabSize, gradient),
                      // Button body with breathing scale
                      Transform.scale(scale: bodyScale, child: child!),
                    ],
                  );
                },
                child: GestureDetector(
                  onTap: isInteractive ? widget.onPressed : null,
                  child: AnimatedContainer(
                    duration: WpMotion.normal,
                    curve: Curves.easeOut,
                    width: WpLayout.fabSize,
                    height: WpLayout.fabSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradient,
                      boxShadow: WpShadows.fab,
                    ),
                    child:
                        notReady &&
                            readiness == RecordingReadiness.serverDownloading
                        ? _buildSpinner(icon)
                        : phase == RecordingPhase.transcribing ||
                              phase == RecordingPhase.processing
                        ? _buildSpinner(icon)
                        : Icon(icon, color: Colors.white, size: WpIconSize.lg),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPulseRing(double buttonSize, LinearGradient gradient) {
    final ringSize = buttonSize * _pulseScale.value;
    final ringColor = gradient.colors.first.withValues(
      alpha: _pulseOpacity.value,
    );
    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2.5),
      ),
    );
  }

  Widget _buildSpinner(IconData icon) {
    return AnimatedBuilder(
      animation: _spinController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _spinController.value * 2 * math.pi,
          child: child,
        );
      },
      child: const Icon(
        LucideIcons.loaderCircle,
        color: Colors.white,
        size: WpIconSize.lg,
      ),
    );
  }

  static LinearGradient _mutedGradient(bool isDark) {
    return isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF52525B), Color(0xFF3F3F46)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9CA3AF), Color(0xFF6B7280)],
          );
  }

  static IconData _readinessIcon(RecordingReadiness readiness) {
    return switch (readiness) {
      RecordingReadiness.serverDownloading => LucideIcons.loaderCircle,
      RecordingReadiness.serverMissing => LucideIcons.download,
      RecordingReadiness.modelMissing => LucideIcons.download,
      RecordingReadiness.ready => LucideIcons.mic,
    };
  }

  static LinearGradient _gradient(RecordingPhase phase, bool isDark) {
    return switch (phase) {
      RecordingPhase.recording => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
      ),
      RecordingPhase.transcribing ||
      RecordingPhase.processing => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
      ),
      RecordingPhase.done => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4ADE80), Color(0xFF16A34A)],
      ),
      RecordingPhase.error => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF7B7B), Color(0xFFEF4444)],
      ),
      RecordingPhase.idle =>
        isDark
            ? WpColorsDark.accentWarmGradient
            : WpColorsLight.accentWarmGradient,
    };
  }

  static IconData _icon(RecordingPhase phase) {
    return switch (phase) {
      RecordingPhase.idle => LucideIcons.mic,
      RecordingPhase.recording => LucideIcons.square,
      RecordingPhase.transcribing ||
      RecordingPhase.processing => LucideIcons.loaderCircle,
      RecordingPhase.done => LucideIcons.check,
      RecordingPhase.error => LucideIcons.triangleAlert,
    };
  }
}
