/// Shared recording HUD pill widget used by both in-window and floating overlays.
///
/// Renders identically in both contexts for visual consistency. All data is
/// accepted as constructor parameters -- NO Riverpod dependency, making it safe
/// for use in secondary Flutter engines (desktop_multi_window).
///
/// The in-window overlay wraps this with `showBackdropFilter: true` and feeds
/// state from Riverpod. The floating overlay uses `isDarkOnly: true` and
/// `showDragHandle: true`, feeding state decoded from IPC.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'waveform_bars.dart';

// ---------------------------------------------------------------------------
// RecordingPill -- shared between in-window and floating overlays
// ---------------------------------------------------------------------------

/// Pill-shaped recording HUD showing timer, waveform, progress, and status.
///
/// Handles all [RecordingPhase]s with consistent styling. The in-window
/// overlay passes [showBackdropFilter] = true for frosted glass; the floating
/// overlay passes [isDarkOnly] = true and [showDragHandle] = true.
class RecordingPill extends StatefulWidget {
  const RecordingPill({
    super.key,
    required this.phase,
    required this.elapsed,
    required this.audioLevel,
    this.maxDurationSeconds = 0,
    this.isLocalStt,
    this.aiMode,
    this.transcript,
    this.errorMessage,
    this.afterAction,
    this.hotkeyLabel,
    this.onStop,
    this.onCancel,
    this.showBackdropFilter = false,
    this.showDragHandle = false,
    this.isDarkOnly = false,
  });

  /// Current recording phase.
  final RecordingPhase phase;

  /// Elapsed recording time.
  final Duration elapsed;

  /// Current microphone level (0.0-1.0).
  final double audioLevel;

  /// Maximum recording duration in seconds (0 = unlimited).
  final int maxDurationSeconds;

  /// Whether STT is local (true), cloud (false), or unknown (null).
  final bool? isLocalStt;

  /// AI mode label (e.g. "Translate"), or null if not active.
  final String? aiMode;

  /// Partial transcript for preview during transcribing/processing.
  final String? transcript;

  /// Error message to display in error phase.
  final String? errorMessage;

  /// After-action setting as string.
  final String? afterAction;

  /// Pre-formatted hotkey label (e.g. "Ctrl+Shift+Space").
  final String? hotkeyLabel;

  /// Called when the user taps the stop button.
  final VoidCallback? onStop;

  /// Called when the user taps the cancel button.
  final VoidCallback? onCancel;

  /// When true, wraps the pill content in a [BackdropFilter] (in-window overlay).
  final bool showBackdropFilter;

  /// When true, shows a drag handle indicator on hover (floating overlay).
  final bool showDragHandle;

  /// When true, always uses dark theme colors (floating overlay has no Theme access).
  final bool isDarkOnly;

  /// Context-aware done message based on afterAction setting.
  ///
  /// Exposed as static for reuse by wrapper widgets (e.g. semantic labels
  /// in floating overlay).
  static String doneMessageFor(String? afterAction, L10n l10n) {
    return switch (afterAction) {
      'paste' => l10n.overlayDonePasted,
      'copy_and_paste' || 'clipboard_and_paste' => l10n.overlayDoneBoth,
      'clipboard' || 'copy' => l10n.overlayDone,
      _ => l10n.overlayDoneReady,
    };
  }

  @override
  State<RecordingPill> createState() => _RecordingPillState();
}

class _RecordingPillState extends State<RecordingPill>
    with TickerProviderStateMixin {
  // Waveform level history buffer (scrolling bars).
  final List<double> _levelHistory = [];
  static const int _maxLevelHistory = 20;

  // Pulsing red dot animation.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  // Shimmer for indeterminate progress bar.
  late final AnimationController _shimmerController;

  // Hover state for hotkey hint / drag handle.
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant RecordingPill old) {
    super.didUpdateWidget(old);

    // Accumulate waveform level history during recording.
    // Guard against duplicates: only add when audioLevel actually changes
    // (parent rebuilds on elapsed ticks would otherwise duplicate samples).
    if (widget.phase == RecordingPhase.recording &&
        widget.audioLevel != old.audioLevel) {
      _levelHistory.add(widget.audioLevel);
      if (_levelHistory.length > _maxLevelHistory) _levelHistory.removeAt(0);
    }

    // Clear history when leaving recording phase.
    if (old.phase == RecordingPhase.recording &&
        widget.phase != RecordingPhase.recording) {
      _levelHistory.clear();
    }

    // Sync animation controllers when phase changes.
    if (widget.phase != old.phase) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    final phase = widget.phase;
    if (phase == RecordingPhase.recording) {
      _shimmerController
        ..stop()
        ..reset();
      _pulseController
        ..reset()
        ..repeat(reverse: true);
    } else if (phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.processing) {
      _pulseController
        ..stop()
        ..reset();
      _shimmerController
        ..reset()
        ..repeat();
    } else {
      _pulseController
        ..stop()
        ..reset();
      _shimmerController
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool get _isDark =>
      widget.isDarkOnly ||
      Theme.of(context).brightness == Brightness.dark;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color _timerColor() {
    final maxSec = widget.maxDurationSeconds;
    if (maxSec <= 0) {
      return _isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    }
    final pct = widget.elapsed.inSeconds / maxSec;
    if (pct >= 0.90) return const Color(0xFFFF5252);
    if (pct >= 0.75) return const Color(0xFFFFC107);
    return _isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
  }

  double _progressFraction() {
    final maxSec = widget.maxDurationSeconds;
    if (maxSec <= 0) return 0.0;
    return (widget.elapsed.inSeconds / maxSec).clamp(0.0, 1.0);
  }

  /// Context-aware done message based on afterAction setting.
  String _doneMessage(L10n l10n) =>
      RecordingPill.doneMessageFor(widget.afterAction, l10n);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pillRadius = BorderRadius.circular(999);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main pill container.
          Container(
            constraints: const BoxConstraints(
              maxWidth: 520,
              minWidth: 200,
              minHeight: 40,
            ),
            decoration: BoxDecoration(
              borderRadius: pillRadius,
              boxShadow: WpShadows.elevated,
            ),
            child: ClipRRect(
              borderRadius: pillRadius,
              child: _buildPillInterior(pillRadius),
            ),
          ),

          // Drag handle indicator -- fades on hover (floating overlay only).
          if (widget.showDragHandle)
            Positioned(
              left: 0,
              right: 0,
              top: 2,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity:
                      (_isHovered && widget.phase != RecordingPhase.done)
                          ? 1.0
                          : 0.0,
                  duration: WpMotion.fast,
                  child: Center(
                    child: Text(
                      '\u2837',
                      style: TextStyle(
                        fontSize: 12,
                        color: (_isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Hotkey hint -- fades on hover, positioned below the pill.
          if (widget.hotkeyLabel != null && widget.hotkeyLabel!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: -24,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity:
                      _isHovered && widget.phase == RecordingPhase.recording
                          ? 1.0
                          : 0.0,
                  duration: WpMotion.fast,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WpSpacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (_isDark
                                ? WpColorsDark.surface
                                : WpColorsLight.surface)
                            .withValues(alpha: 0.9),
                        borderRadius: WpRadius.borderSm,
                      ),
                      child: Text(
                        widget.hotkeyLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          color: _isDark
                              ? WpColorsDark.textMuted
                              : WpColorsLight.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the pill interior, optionally wrapped in a [BackdropFilter].
  Widget _buildPillInterior(BorderRadius pillRadius) {
    final bgColor = widget.showBackdropFilter
        ? (_isDark
            ? const Color(0xD9141926)
            : const Color(0xD9F0F3F7))
        : (_isDark
            ? WpColorsDark.background.withValues(alpha: 0.92)
            : WpColorsLight.background.withValues(alpha: 0.92));

    Widget interior = DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: pillRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: 4,
            ),
            child: _buildContent(context),
          ),
          _buildProgressBar(),
        ],
      ),
    );

    if (widget.showBackdropFilter) {
      interior = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: interior,
      );
    }

    return interior;
  }

  // ---------------------------------------------------------------------------
  // Main content row
  // ---------------------------------------------------------------------------

  Widget _buildContent(BuildContext context) {
    final l10n = L10n.of(context);
    final mutedColor =
        _isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final phase = widget.phase;

    final showCancel = phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.processing ||
        phase == RecordingPhase.error ||
        phase == RecordingPhase.done;

    final showStop = phase == RecordingPhase.recording;

    // Show inline badges during active phases.
    final showBadges = phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.processing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Left: cancel button ---
        if (showCancel && widget.onCancel != null)
          Tooltip(
            message: l10n.overlayCancel,
            child: _PillIconButton(
              icon: LucideIcons.x,
              color: mutedColor,
              semanticsLabel: l10n.overlayCancel,
              onPressed: widget.onCancel!,
            ),
          ),
        const SizedBox(width: WpSpacing.xs),

        // -- Inline privacy badge ---
        if (showBadges) _buildInlinePrivacyBadge(),

        // -- Center: phase-specific content ---
        Flexible(
          child: AnimatedSwitcher(
            duration: WpMotion.fast,
            switchInCurve: WpMotion.defaultCurve,
            switchOutCurve: WpMotion.defaultCurve,
            child: KeyedSubtree(
              key: ValueKey(phase),
              child: _buildCenterContent(context, l10n),
            ),
          ),
        ),

        // -- Inline AI mode badge ---
        if (showBadges) _buildInlineAiBadge(),

        // -- Right: stop button ---
        if (showStop && widget.onStop != null) ...[
          const SizedBox(width: WpSpacing.xs),
          _PillStopButton(onPressed: widget.onStop!),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Center -- phase-dependent content
  // ---------------------------------------------------------------------------

  Widget _buildCenterContent(BuildContext context, L10n l10n) {
    final accentColor =
        _isDark ? WpColorsDark.accent : WpColorsLight.accent;

    switch (widget.phase) {
      case RecordingPhase.recording:
        return _buildRecordingCenter(context, l10n);
      case RecordingPhase.transcribing:
        return _buildProcessingCenter(
          label: l10n.overlayTranscribing,
          accentColor: accentColor,
        );
      case RecordingPhase.processing:
        return _buildProcessingCenter(
          label: l10n.overlayRefining,
          accentColor: accentColor,
        );
      case RecordingPhase.done:
        return _buildDoneCenter(l10n);
      case RecordingPhase.error:
        return _buildErrorCenter(l10n);
      case RecordingPhase.idle:
        return const SizedBox.shrink();
    }
  }

  /// Recording: pulsing dot + timer + waveform bars.
  Widget _buildRecordingCenter(BuildContext context, L10n l10n) {
    final tColor = _timerColor();

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
              color: const Color(
                0xFFFF5252,
              ).withValues(alpha: _pulseAnim.value),
            ),
          ),
        ),
        const SizedBox(width: WpSpacing.xs),

        // Timer.
        Semantics(
          label: '${l10n.overlayRecording} ${_formatDuration(widget.elapsed)}',
          child: AnimatedDefaultTextStyle(
            duration: WpMotion.fast,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: tColor,
            ),
            child: Text(_formatDuration(widget.elapsed)),
          ),
        ),
        const SizedBox(width: WpSpacing.sm),

        // Waveform bars.
        WpWaveformBars(
          levels: List.unmodifiable(_levelHistory),
          barCount: _maxLevelHistory,
          height: 22,
          barWidth: 2.5,
          barSpacing: 2,
          isActive: true,
        ),
      ],
    );
  }

  /// Transcribing / Processing: spinner + label + muted elapsed time.
  Widget _buildProcessingCenter({
    required String label,
    required Color accentColor,
  }) {
    final mutedColor =
        _isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: accentColor,
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
        Text(
          _formatDuration(widget.elapsed),
          style: TextStyle(fontSize: 12, color: mutedColor),
        ),
      ],
    );
  }

  /// Done: success icon + context-appropriate message.
  Widget _buildDoneCenter(L10n l10n) {
    final successColor =
        _isDark ? WpColorsDark.success : WpColorsLight.success;
    final doneText = _doneMessage(l10n);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.circleCheck, size: WpIconSize.sm, color: successColor),
        const SizedBox(width: WpSpacing.xs),
        Text(
          doneText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: successColor,
          ),
        ),
      ],
    );
  }

  /// Error: error icon + error message.
  Widget _buildErrorCenter(L10n l10n) {
    final errorColor = _isDark ? WpColorsDark.error : WpColorsLight.error;
    final message = widget.errorMessage ?? l10n.overlayError;

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
  // Inline badges (compact, single-line)
  // ---------------------------------------------------------------------------

  Widget _buildInlinePrivacyBadge() {
    if (widget.isLocalStt == null) return const SizedBox(width: WpSpacing.xs);

    final l10n = L10n.of(context);
    final isLocal = widget.isLocalStt!;
    final color = isLocal
        ? (_isDark ? WpColorsDark.success : WpColorsLight.success)
        : (_isDark ? WpColorsDark.accent : WpColorsLight.accent);
    final icon = isLocal ? LucideIcons.shieldCheck : LucideIcons.cloud;
    final label = isLocal
        ? l10n.overlayProcessingLocal
        : l10n.overlayProcessingCloud;

    return Padding(
      padding: const EdgeInsets.only(right: WpSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
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

  Widget _buildInlineAiBadge() {
    if (widget.aiMode == null || widget.aiMode!.isEmpty) {
      return const SizedBox(width: WpSpacing.xs);
    }

    final accentColor =
        _isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final secondaryColor =
        _isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(left: WpSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: WpRadius.borderFull,
        ),
        child: Text(
          '\u{1F916} ${widget.aiMode}',
          style: TextStyle(fontSize: 10, color: secondaryColor),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom progress bar
  // ---------------------------------------------------------------------------

  Widget _buildProgressBar() {
    final phase = widget.phase;
    final accentColor =
        _isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final mutedColor =
        _isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth;

          switch (phase) {
            case RecordingPhase.recording:
              final maxSec = widget.maxDurationSeconds;
              if (maxSec <= 0) {
                // Unlimited: thin accent line.
                return Container(
                  height: 4,
                  width: fullWidth,
                  color: accentColor.withValues(alpha: 0.3),
                );
              }
              final fraction = _progressFraction();
              final barColor = _timerColor();
              return Stack(
                children: [
                  Container(
                    height: 4,
                    width: fullWidth,
                    color: mutedColor.withValues(alpha: 0.15),
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
                color: accentColor,
                controller: _shimmerController,
              );

            case RecordingPhase.done:
              final successColor =
                  _isDark ? WpColorsDark.success : WpColorsLight.success;
              return Container(
                height: 4,
                width: fullWidth,
                decoration: BoxDecoration(
                  color: successColor,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(2),
                  ),
                ),
              );

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
// Private sub-widgets (shared -- no Riverpod)
// =============================================================================

/// Small icon button for secondary pill actions (36x36 compact).
class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
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
        width: 36,
        height: 36,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            hoverColor: color.withValues(alpha: 0.12),
            child: Center(
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prominent accent stop button (36x36 circle with gradient).
class _PillStopButton extends StatelessWidget {
  const _PillStopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Red gradient -- consistent across both overlays.
    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    );

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
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: gradient,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  LucideIcons.square,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indeterminate shimmer bar using a parent-provided [AnimationController].
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.width,
    required this.color,
    required this.controller,
  });

  final double width;
  final Color color;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        return Container(
          height: 4,
          width: width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.6),
                color.withValues(alpha: 0.15),
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