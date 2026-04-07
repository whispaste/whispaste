import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart'
    show RecordingPhase, SttServerState;
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Bottom status bar — sits on the app frame, full width.
///
/// Shows only essential runtime state: STT engine status and active
/// post-processing. Static configuration (overlay mode, hotkey, after-action)
/// belongs in Settings, not the status bar.
class WpStatusBar extends StatelessWidget {
  const WpStatusBar({
    super.key,
    required this.sttModeLabel,
    this.postProcessingLabel,
    this.sttState = SttServerState.stopped,
    this.recordingPhase = RecordingPhase.idle,
    this.onSttTap,
    this.onPostProcessTap,
  });

  /// Active STT mode, e.g. "On device" or "OpenAI".
  final String sttModeLabel;

  /// Active post-processing preset label, or `null` when disabled.
  /// When null, the chip is hidden entirely — no visual noise.
  final String? postProcessingLabel;

  /// Current state of the STT server subprocess.
  final SttServerState sttState;

  /// Current phase of the recording lifecycle.
  final RecordingPhase recordingPhase;

  /// Callback when user taps the STT chip (navigate to settings).
  final VoidCallback? onSttTap;

  /// Callback when user taps the post-processing chip.
  final VoidCallback? onPostProcessTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStyle = Theme.of(context).textTheme.labelSmall!;
    final l10n = L10n.of(context);

    return SizedBox(
      height: WpLayout.statusBarHeight,
      child: Row(
        children: [
          // Sidebar-width spacer — chips start in the content area
          const SizedBox(width: WpLayout.sidebarWidth),
          // Content-area span.
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SttChip(
                    modeLabel: sttModeLabel,
                    state: sttState,
                    recordingPhase: recordingPhase,
                    textStyle: textStyle,
                    isDark: isDark,
                    l10n: l10n,
                    onTap: onSttTap,
                  ),
                  if (postProcessingLabel != null) ...[
                    const SizedBox(width: WpSpacing.xs),
                    _StatusChip(
                      icon: LucideIcons.sparkles,
                      label: postProcessingLabel!,
                      textStyle: textStyle,
                      isDark: isDark,
                      tooltip: l10n.statusBarPostProcessTooltip,
                      onTap: onPostProcessTap,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Combined STT mode + recording/server state chip.
///
/// Prioritises the recording lifecycle phase over the STT subprocess state:
///   🔴 On Device — Recording…     (RecordingPhase.recording)
///   🟡 On Device — Transcribing…  (RecordingPhase.transcribing)
///   ✨ On Device — Processing…    (RecordingPhase.processing)
///   🟢 On Device — Done           (RecordingPhase.done)
///   🔴 On Device — Error          (RecordingPhase.error)
///   — falls back to SttServerState when idle —
///   🟢 On Device — Ready
///   🟡 On Device — Starting…
///   🔴 On Device — Error
///   ⚪ On Device — Standby
class _SttChip extends StatelessWidget {
  const _SttChip({
    required this.modeLabel,
    required this.state,
    this.recordingPhase = RecordingPhase.idle,
    required this.textStyle,
    required this.isDark,
    required this.l10n,
    this.onTap,
  });

  final String modeLabel;
  final SttServerState state;
  final RecordingPhase recordingPhase;
  final TextStyle textStyle;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color dotColor, String stateLabel, bool showSpinner) =
        _resolveDisplay();

    return Tooltip(
      message: l10n.statusBarSttTooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: WpRadius.borderFull,
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? WpColorsDark.surface.withValues(alpha: 0.5)
                : WpColorsLight.surfaceVariant,
            borderRadius: WpRadius.borderFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: dotColor,
                  ),
                )
              else
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                '$modeLabel — $stateLabel',
                style: textStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves the display triple (dot color, label, spinner) by prioritising
  /// the recording lifecycle phase over the STT subprocess state.
  (Color, String, bool) _resolveDisplay() {
    // Active recording phases take priority over STT subprocess state.
    switch (recordingPhase) {
      case RecordingPhase.recording:
        return (
          isDark ? WpColorsDark.error : WpColorsLight.error,
          l10n.statusBarRecording,
          true,
        );
      case RecordingPhase.transcribing:
        return (
          isDark ? WpColorsDark.accent : WpColorsLight.accent,
          l10n.statusBarTranscribing,
          true,
        );
      case RecordingPhase.processing:
        return (
          isDark ? WpColorsDark.accent : WpColorsLight.accent,
          l10n.statusBarProcessing,
          true,
        );
      case RecordingPhase.done:
        return (
          isDark ? WpColorsDark.success : WpColorsLight.success,
          l10n.statusBarDone,
          false,
        );
      case RecordingPhase.error:
        return (
          isDark ? WpColorsDark.error : WpColorsLight.error,
          l10n.sttStatusError,
          false,
        );
      case RecordingPhase.idle:
        // Fall through to STT subprocess state below.
        break;
    }

    // Idle — show STT subprocess state.
    return switch (state) {
      SttServerState.stopped => (
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        l10n.sttStatusStandby,
        false,
      ),
      SttServerState.starting => (
        isDark ? WpColorsDark.accent : WpColorsLight.accent,
        l10n.sttStatusStarting,
        true,
      ),
      SttServerState.ready => (
        isDark ? WpColorsDark.success : WpColorsLight.success,
        l10n.sttStatusReady,
        false,
      ),
      SttServerState.error => (
        isDark ? WpColorsDark.error : WpColorsLight.error,
        l10n.sttStatusError,
        false,
      ),
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.textStyle,
    required this.isDark,
    this.icon,
    this.tooltip,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final TextStyle textStyle;
  final bool isDark;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final chip = InkWell(
      onTap: onTap,
      borderRadius: WpRadius.borderFull,
      mouseCursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? WpColorsDark.surface.withValues(alpha: 0.5)
              : WpColorsLight.surfaceVariant,
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: cs.secondary),
              const SizedBox(width: 4),
            ],
            Text(label, style: textStyle),
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}
