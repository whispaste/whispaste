import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/recording/recording_state.dart';
import '../../widgets/waveform_bars.dart';
import '../../services/recording_orchestrator.dart';
import '../../widgets/privacy_badge.dart';

// ---------------------------------------------------------------------------
// Recording overlay — pill-shaped transparent HUD shown during recording
// ---------------------------------------------------------------------------

/// Pill-shaped overlay that appears during recording and post-processing.
///
/// Shows waveform visualization, timer, privacy badge, and control buttons.
/// Designed to be hosted in a secondary window or as a Stack layer.
class RecordingOverlay extends ConsumerStatefulWidget {
  const RecordingOverlay({super.key});

  @override
  ConsumerState<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends ConsumerState<RecordingOverlay>
    with TickerProviderStateMixin {
  // Waveform level history buffer (scrolling bars).
  final List<double> _levelHistory = [];
  static const int _maxLevelHistory = 20;

  // Pulsing red dot animation.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  // Auto-dismiss timer for the "done" phase.
  Timer? _doneTimer;

  // Hover state for showing the hotkey hint.
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _doneTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color _timerColor({
    required Duration elapsed,
    required int maxSeconds,
    required bool isDark,
  }) {
    if (maxSeconds <= 0) {
      return isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    }
    final pct = elapsed.inSeconds / maxSeconds;
    if (pct >= 0.90) return const Color(0xFFFF5252);
    if (pct >= 0.75) return const Color(0xFFFFC107);
    return isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
  }

  double _progressFraction({
    required Duration elapsed,
    required int maxSeconds,
  }) {
    if (maxSeconds <= 0) return 0.0;
    return (elapsed.inSeconds / maxSeconds).clamp(0.0, 1.0);
  }

  String _hotkeyLabel(AppSettings settings) {
    final mods = settings.hotkeyModifiers
        .split('+')
        .where((m) => m.isNotEmpty)
        .map((m) => '${m[0].toUpperCase()}${m.substring(1)}')
        .join('+');
    if (mods.isEmpty) return settings.hotkeyKey;
    return '$mods+${settings.hotkeyKey}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(recordingPhaseProvider);

    // Schedule auto-dismiss when entering the done phase (fast, subtle).
    ref.listen<RecordingPhase>(recordingPhaseProvider, (prev, next) {
      if (next == RecordingPhase.done) {
        _doneTimer?.cancel();
        _doneTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted) ref.read(recordingOrchestratorProvider.notifier).reset();
        });
      }
    });

    // Accumulate level history for waveform bars.
    ref.listen<double>(audioLevelProvider, (_, level) {
      if (!mounted) return;
      setState(() {
        _levelHistory.add(level);
        if (_levelHistory.length > _maxLevelHistory) {
          _levelHistory.removeAt(0);
        }
      });
    });

    // Clear waveform history when leaving recording phase.
    ref.listen<RecordingPhase>(recordingPhaseProvider, (prev, next) {
      if (prev == RecordingPhase.recording && next != RecordingPhase.recording) {
        _levelHistory.clear();
      }
    });

    if (phase == RecordingPhase.idle) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: WpMotion.smooth,
      switchInCurve: WpMotion.defaultCurve,
      switchOutCurve: WpMotion.defaultCurve,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: const ValueKey('recording-overlay-visible'),
        child: _buildPill(context, phase),
      ),
    );
  }

  Widget _buildPill(BuildContext context, RecordingPhase phase) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillRadius = BorderRadius.circular(38);
    final settings =
        ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final elapsed = ref.watch(recordingElapsedProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
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
                color: isDark
                    ? const Color(0xD9141926)
                    : const Color(0xD9F0F3F7),
                borderRadius: pillRadius,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.md,
                      vertical: WpSpacing.sm,
                    ),
                    child: _buildContent(context, phase, settings, elapsed),
                  ),
                  _buildProgressBar(context, phase, elapsed, settings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main content row
  // ---------------------------------------------------------------------------

  Widget _buildContent(
    BuildContext context,
    RecordingPhase phase,
    AppSettings settings,
    Duration elapsed,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Left: secondary buttons ---
        _buildSecondaryButtons(context, phase),
        const SizedBox(width: WpSpacing.sm),

        // -- Center: status + waveform ---
        Flexible(
          child: AnimatedSwitcher(
            duration: WpMotion.fast,
            switchInCurve: WpMotion.defaultCurve,
            switchOutCurve: WpMotion.defaultCurve,
            child: KeyedSubtree(
              key: ValueKey(phase),
              child: _buildCenterContent(
                context,
                phase,
                settings,
                elapsed,
                isDark,
              ),
            ),
          ),
        ),
        const SizedBox(width: WpSpacing.sm),

        // -- Right: badge + hotkey + stop ---
        _buildRightSection(context, phase, settings, isDark),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Left — cancel & pause
  // ---------------------------------------------------------------------------

  Widget _buildSecondaryButtons(BuildContext context, RecordingPhase phase) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final l10n = L10n.of(context);

    final showCancel = phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.processing ||
        phase == RecordingPhase.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCancel)
          Tooltip(
            message: l10n.overlayCancel,
            child: _OverlayIconButton(
              icon: LucideIcons.x,
              color: mutedColor,
              semanticsLabel: l10n.overlayCancel,
              onPressed: () => ref.read(recordingOrchestratorProvider.notifier).reset(),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Center — phase-dependent content
  // ---------------------------------------------------------------------------

  Widget _buildCenterContent(
    BuildContext context,
    RecordingPhase phase,
    AppSettings settings,
    Duration elapsed,
    bool isDark,
  ) {
    switch (phase) {
      case RecordingPhase.recording:
        return _buildRecordingCenter(context, settings, elapsed, isDark);
      case RecordingPhase.transcribing:
        return _buildProcessingCenter(
          context,
          elapsed,
          isDark,
          label: L10n.of(context).overlayTranscribing,
          accentColor: isDark ? WpColorsDark.accent : WpColorsLight.accent,
        );
      case RecordingPhase.processing:
        return _buildProcessingCenter(
          context,
          elapsed,
          isDark,
          label: L10n.of(context).overlayRefining,
          accentColor: isDark ? WpColorsDark.accent : WpColorsLight.accent,
        );
      case RecordingPhase.done:
        return _buildDoneCenter(isDark);
      case RecordingPhase.error:
        return _buildErrorCenter(context, isDark);
      case RecordingPhase.idle:
        return const SizedBox.shrink();
    }
  }

  /// Recording: pulsing dot + timer + waveform bars.
  Widget _buildRecordingCenter(
    BuildContext context,
    AppSettings settings,
    Duration elapsed,
    bool isDark,
  ) {
    final maxSec = settings.maxRecordDuration;
    final tColor = _timerColor(
      elapsed: elapsed,
      maxSeconds: maxSec,
      isDark: isDark,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing red dot.
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, _) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF5252).withValues(
                alpha: _pulseAnim.value,
              ),
            ),
          ),
        ),
        const SizedBox(width: WpSpacing.xs),

        // Timer.
        Semantics(
          label: '${L10n.of(context).overlayRecording} ${_formatDuration(elapsed)}',
          child: AnimatedDefaultTextStyle(
            duration: WpMotion.fast,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: tColor,
            ),
            child: Text(_formatDuration(elapsed)),
          ),
        ),
        const SizedBox(width: WpSpacing.sm),

        // Waveform bars.
        WpWaveformBars(
          levels: List.unmodifiable(_levelHistory),
          barCount: _maxLevelHistory,
          height: 32,
          barWidth: 3,
          barSpacing: 2,
          isActive: true,
        ),
      ],
    );
  }

  /// Transcribing / Processing: spinner + label + muted elapsed time.
  Widget _buildProcessingCenter(
    BuildContext context,
    Duration elapsed,
    bool isDark, {
    required String label,
    required Color accentColor,
  }) {
    final mutedColor =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(accentColor),
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: accentColor,
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
        Text(
          _formatDuration(elapsed),
          style: TextStyle(fontSize: 12, color: mutedColor),
        ),
      ],
    );
  }

  /// Done: subtle success text that fades out quickly.
  /// Adapts message to the actual after-transcription setting.
  Widget _buildDoneCenter(bool isDark) {
    final l10n = L10n.of(context);
    final settings =
        ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final textColor =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;

    // Show context-appropriate done message.
    final doneText = switch (settings.afterTranscription) {
      'paste' => l10n.overlayDonePasted,
      'both' => l10n.overlayDoneBoth,
      'nothing' => l10n.overlayDoneReady,
      _ => l10n.overlayDone, // 'clipboard' default
    };

    return Text(
      doneText,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }

  /// Error: red tint + error message.
  Widget _buildErrorCenter(BuildContext context, bool isDark) {
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;
    final state = ref.watch(recordingProvider);
    final message = state.errorMessage ?? L10n.of(context).overlayError;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.circleAlert, size: WpIconSize.sm, color: errorColor),
        const SizedBox(width: WpSpacing.xs),
        Flexible(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: errorColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Right — privacy badge, hotkey hint, stop button
  // ---------------------------------------------------------------------------

  Widget _buildRightSection(
    BuildContext context,
    RecordingPhase phase,
    AppSettings settings,
    bool isDark,
  ) {
    final showStop = phase == RecordingPhase.recording;
    final mutedColor =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Privacy badge (with text for clarity per persona review).
        if (phase == RecordingPhase.recording ||
            phase == RecordingPhase.transcribing ||
            phase == RecordingPhase.processing)
          const WpPrivacyBadge(),

        // Hotkey hint (visible on hover only).
        AnimatedOpacity(
          opacity: _isHovered && showStop ? 1.0 : 0.0,
          duration: WpMotion.fast,
          curve: WpMotion.defaultCurve,
          child: Padding(
            padding: const EdgeInsets.only(left: WpSpacing.xs),
            child: Text(
              _hotkeyLabel(settings),
              style: TextStyle(fontSize: 11, color: mutedColor),
            ),
          ),
        ),

        // Stop button.
        if (showStop) ...[
          const SizedBox(width: WpSpacing.xs),
          _StopButton(
            onPressed: () =>
                ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom progress bar
  // ---------------------------------------------------------------------------

  Widget _buildProgressBar(
    BuildContext context,
    RecordingPhase phase,
    Duration elapsed,
    AppSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxSec = settings.maxRecordDuration;

    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth;

          switch (phase) {
            case RecordingPhase.recording:
              if (maxSec <= 0) {
                // Unlimited: thin accent line.
                return Container(
                  height: 4,
                  width: fullWidth,
                  color: (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                      .withValues(alpha: 0.3),
                );
              }
              final fraction =
                  _progressFraction(elapsed: elapsed, maxSeconds: maxSec);
              final barColor = _timerColor(
                elapsed: elapsed,
                maxSeconds: maxSec,
                isDark: isDark,
              );
              return Stack(
                children: [
                  Container(
                    height: 4,
                    width: fullWidth,
                    color: (isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted)
                        .withValues(alpha: 0.15),
                  ),
                  AnimatedContainer(
                    duration: WpMotion.smooth,
                    curve: Curves.linear,
                    height: 4,
                    width: fullWidth * fraction,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(2),
                      ),
                    ),
                  ),
                ],
              );

            case RecordingPhase.transcribing:
            case RecordingPhase.processing:
              return _ShimmerBar(
                width: fullWidth,
                color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
              );

            case RecordingPhase.done:
            case RecordingPhase.error:
            case RecordingPhase.idle:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }
}

// =============================================================================
// Private sub-widgets
// =============================================================================

/// Small icon button for secondary overlay actions (meets 44×44 touch target).
class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.color,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            hoverColor: color.withValues(alpha: 0.12),
            child: Center(
              child: Icon(icon, size: WpIconSize.sm, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prominent accent stop button (44×44 circle with gradient — matches FAB shape).
class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient =
        isDark ? WpColorsDark.accentWarmGradient : WpColorsLight.accentWarmGradient;

    return Tooltip(
      message: L10n.of(context).overlayStop,
      child: Semantics(
        label: L10n.of(context).overlayStop,
        button: true,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: WpMotion.fast,
              curve: WpMotion.defaultCurve,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: gradient,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(LucideIcons.square, size: WpIconSize.sm, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indeterminate shimmer bar — a gradient that slides left→right repeatedly.
class _ShimmerBar extends StatefulWidget {
  const _ShimmerBar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Slide a highlight band across the full width.
        final value = _controller.value;
        return Container(
          height: 4,
          width: widget.width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.color.withValues(alpha: 0.15),
                widget.color.withValues(alpha: 0.6),
                widget.color.withValues(alpha: 0.15),
              ],
              stops: [
                (value - 0.3).clamp(0.0, 1.0),
                value,
                (value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}
