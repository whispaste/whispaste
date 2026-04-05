import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../features/recording/recording_state.dart';

/// Recording FAB — phase-aware with distinct visual states.
///
/// | Phase        | Visual                                          |
/// |--------------|-------------------------------------------------|
/// | idle         | Accent gradient, mic icon, hover scale           |
/// | recording    | Red gradient, stop icon, pulse animation          |
/// | transcribing | Amber gradient, rotating loader, non-interactive |
/// | done         | Green, check icon (brief flash before reset)     |
/// | error        | Red, alert icon (brief flash before reset)        |
class WpRecordingFab extends StatefulWidget {
  const WpRecordingFab({
    super.key,
    required this.phase,
    required this.onPressed,
  });

  final RecordingPhase phase;
  final VoidCallback onPressed;

  @override
  State<WpRecordingFab> createState() => _WpRecordingFabState();
}

class _WpRecordingFabState extends State<WpRecordingFab>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnim;
  late final AnimationController _spinController;
  late final AnimationController _breatheController;
  late final Animation<double> _breatheAnim;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    // Pulse animation for recording state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Spin animation for transcribing/processing state
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Subtle idle breathing — very gentle scale oscillation
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _breatheAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(WpRecordingFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) _syncAnimations();
  }

  void _syncAnimations() {
    // Pulse: only during recording
    if (widget.phase == RecordingPhase.recording) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
    // Spin: only during transcribing
    if (widget.phase == RecordingPhase.transcribing) {
      _spinController.repeat();
    } else {
      _spinController.stop();
      _spinController.reset();
    }
    // Breathe: only during idle
    if (widget.phase == RecordingPhase.idle) {
      _breatheController.repeat(reverse: true);
    } else {
      _breatheController.stop();
      _breatheController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final phase = widget.phase;

    final isInteractive = phase == RecordingPhase.idle ||
        phase == RecordingPhase.recording;

    final tooltip = switch (phase) {
      RecordingPhase.idle => l10n.tooltipRecord,
      RecordingPhase.recording => l10n.tooltipStopRecord,
      RecordingPhase.transcribing => l10n.tooltipProcessing,
      RecordingPhase.done => l10n.statusTranscriptionDone,
      RecordingPhase.error => '',
    };

    final gradient = _gradient(phase, isDark);
    final icon = _icon(phase);

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
          child: AnimatedBuilder(
            animation: Listenable.merge([_scaleAnim, _spinController, _breatheAnim]),
            builder: (context, child) {
              final scale = switch (phase) {
                RecordingPhase.recording => _scaleAnim.value,
                RecordingPhase.idle when _isHovered => 1.06,
                RecordingPhase.idle => _breatheAnim.value,
                _ => 1.0,
              };
              return AnimatedScale(
                scale: scale,
                duration: WpMotion.fast,
                child: child,
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
                child: phase == RecordingPhase.transcribing
                    ? _buildSpinner(icon)
                    : Icon(icon, color: Colors.white, size: WpIconSize.lg),
              ),
            ),
          ),
        ),
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
      child: const Icon(LucideIcons.loaderCircle, color: Colors.white, size: WpIconSize.lg),
    );
  }

  static LinearGradient _gradient(RecordingPhase phase, bool isDark) {
    return switch (phase) {
      RecordingPhase.recording => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        ),
      RecordingPhase.transcribing => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        ),
      RecordingPhase.done => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34D399), Color(0xFF10B981)],
        ),
      RecordingPhase.error => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7B7B), Color(0xFFEF4444)],
        ),
      RecordingPhase.idle => isDark
          ? WpColorsDark.accentWarmGradient
          : WpColorsLight.accentWarmGradient,
    };
  }

  static IconData _icon(RecordingPhase phase) {
    return switch (phase) {
      RecordingPhase.idle => LucideIcons.mic,
      RecordingPhase.recording => LucideIcons.square,
      RecordingPhase.transcribing => LucideIcons.loaderCircle,
      RecordingPhase.done => LucideIcons.check,
      RecordingPhase.error => LucideIcons.triangleAlert,
    };
  }
}
