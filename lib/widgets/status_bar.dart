import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/settings_enums.dart' show AfterTranscriptionAction;
import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart'
    show RecordingPhase, SttServerState;
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Returns `true` when the "Auto-Paste deaktiviert" status-bar hint chip
/// should be visible.
///
/// The chip surfaces the half-state created when the user skips Auto-Paste in
/// the onboarding flow. It must hide automatically the moment Auto-Paste is
/// re-enabled in Settings, regardless of whether the user explicitly
/// dismissed the chip earlier. It must also never appear while onboarding
/// is still in progress — the onboarding overlay covers the status bar then.
///
/// Lives next to [WpStatusBar] so the visibility rule and the widget that
/// consumes it stay locked together.
bool shouldShowAutoPasteOffHint({
  required AfterTranscriptionAction afterAction,
  required bool onboardingCompleted,
  required bool autoPasteOffHintDismissed,
}) {
  if (!onboardingCompleted) return false;
  if (autoPasteOffHintDismissed) return false;
  // Auto-Paste is considered ON when the action injects keystrokes — i.e.
  // `paste` or `clipboardAndPaste`. Anything else (`clipboard` only,
  // `nothing`) counts as Auto-Paste off.
  switch (afterAction) {
    case AfterTranscriptionAction.paste:
    case AfterTranscriptionAction.clipboardAndPaste:
      return false;
    case AfterTranscriptionAction.clipboard:
    case AfterTranscriptionAction.nothing:
      return true;
  }
}

/// Bottom status bar — sits on the app frame, full width.
///
/// Shows only essential runtime state: STT engine status.
/// Static configuration (overlay mode, hotkey, after-action)
/// belongs in Settings, not the status bar.
class WpStatusBar extends StatelessWidget {
  const WpStatusBar({
    super.key,
    required this.sttModeLabel,
    this.sttState = SttServerState.stopped,
    this.sttStartingSince,
    this.recordingPhase = RecordingPhase.idle,
    this.afterActionLabel,
    this.afterAction,
    this.hotkeyLabel,
    this.hotkeyEnabled = true,
    this.updateVersion,
    this.showAutoPasteOffHint = false,
    this.onSttTap,
    this.onAfterActionChanged,
    this.onHotkeyTap,
    this.onUpdateTap,
    this.onAutoPasteOffHintTap,
    this.onAutoPasteOffHintDismiss,
  });

  /// Active STT mode, e.g. "On device" or "OpenAI".
  final String sttModeLabel;

  /// Current state of the STT server subprocess.
  final SttServerState sttState;

  /// When the STT server entered the starting state (for elapsed display).
  final DateTime? sttStartingSince;

  /// Current phase of the recording lifecycle.
  final RecordingPhase recordingPhase;

  /// Short label for the current after-transcription action, or null to hide.
  final String? afterActionLabel;

  /// Current after-transcription action value (for menu selection).
  final AfterTranscriptionAction? afterAction;

  /// Formatted hotkey label, e.g. "Ctrl+Shift+D", or null to hide.
  final String? hotkeyLabel;

  /// Whether the global hotkey is enabled.
  final bool hotkeyEnabled;

  /// Available update version label, e.g. "1.3.0", or null to hide.
  final String? updateVersion;

  /// Whether to render the persistent "Auto-Paste off" hint chip.
  ///
  /// Visibility is decided by the caller — see `WpStatusBar` consumer in
  /// `app.dart`. The chip is shown when Auto-Paste is off **and** onboarding
  /// has completed **and** the user has not dismissed the hint.
  final bool showAutoPasteOffHint;

  /// Callback when user taps the STT chip (navigate to settings).
  final VoidCallback? onSttTap;

  /// Callback when user selects a different after-transcription action.
  final ValueChanged<AfterTranscriptionAction>? onAfterActionChanged;

  /// Callback when user taps the hotkey chip (navigate to settings).
  final VoidCallback? onHotkeyTap;

  /// Callback when user taps the update-available chip.
  final VoidCallback? onUpdateTap;

  /// Callback when user taps the "Auto-Paste off" hint chip body — should
  /// open Settings and scroll to the After-Transcription section.
  final VoidCallback? onAutoPasteOffHintTap;

  /// Callback when user taps the dismiss button on the "Auto-Paste off"
  /// hint chip — should persist `autoPasteOffHintDismissed = true`.
  final VoidCallback? onAutoPasteOffHintDismiss;

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
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _SttChip.build
                    _SttChip(
                      modeLabel: sttModeLabel,
                      state: sttState,
                      startingSince: sttStartingSince,
                      recordingPhase: recordingPhase,
                      textStyle: textStyle,
                      isDark: isDark,
                      l10n: l10n,
                      onTap: onSttTap,
                    ),
                    if (afterActionLabel != null &&
                        afterAction != null &&
                        onAfterActionChanged != null) ...[
                      const SizedBox(width: WpSpacing.xs),
                      _AfterActionChip(
                        label: afterActionLabel!,
                        current: afterAction!,
                        textStyle: textStyle,
                        isDark: isDark,
                        l10n: l10n,
                        onChanged: onAfterActionChanged!,
                      ),
                    ],
                    if (showAutoPasteOffHint) ...[
                      const SizedBox(width: WpSpacing.xs),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _AutoPasteOffHintChip.build
                      _AutoPasteOffHintChip(
                        textStyle: textStyle,
                        isDark: isDark,
                        l10n: l10n,
                        onTap: onAutoPasteOffHintTap,
                        onDismiss: onAutoPasteOffHintDismiss,
                      ),
                    ],
                    if (hotkeyLabel != null) ...[
                      const SizedBox(width: WpSpacing.xs),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _StatusChip.build
                      _StatusChip(
                        icon: hotkeyEnabled
                            ? LucideIcons.keyboard
                            : LucideIcons.keyboardOff,
                        label: hotkeyLabel!,
                        textStyle: textStyle,
                        isDark: isDark,
                        tooltip: l10n.statusBarHotkeyTooltip,
                        onTap: onHotkeyTap,
                        dimmed: !hotkeyEnabled,
                      ),
                    ],
                    if (updateVersion != null) ...[
                      const SizedBox(width: WpSpacing.xs),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _StatusChip.build
                      _StatusChip(
                        icon: LucideIcons.download,
                        label: l10n.updateStatusBarChip(updateVersion!),
                        textStyle: textStyle,
                        isDark: isDark,
                        tooltip: l10n.updateAvailable(updateVersion!),
                        onTap: onUpdateTap,
                      ),
                    ],
                  ],
                ),
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
///   🟢 On Device — Done           (RecordingPhase.done)
///   🔴 On Device — Error          (RecordingPhase.error)
///   — falls back to SttServerState when idle —
///   🟢 On Device — Ready
///   🟡 On Device — Starting…
///   🔴 On Device — Error
///   ⚪ On Device — Standby
class _SttChip extends StatefulWidget {
  const _SttChip({
    required this.modeLabel,
    required this.state,
    this.startingSince,
    this.recordingPhase = RecordingPhase.idle,
    required this.textStyle,
    required this.isDark,
    required this.l10n,
    this.onTap,
  });

  final String modeLabel;
  final SttServerState state;
  final DateTime? startingSince;
  final RecordingPhase recordingPhase;
  final TextStyle textStyle;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onTap;

  @override
  State<_SttChip> createState() => _SttChipState();
}

class _SttChipState extends State<_SttChip> {
  Timer? _elapsedTicker;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_SttChip old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state ||
        old.startingSince != widget.startingSince) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncTicker() {
    if (widget.state == SttServerState.starting &&
        widget.startingSince != null) {
      _elapsedTicker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _elapsedTicker?.cancel();
      _elapsedTicker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (Color dotColor, String stateLabel, bool showSpinner) =
        _resolveDisplay();

    final inkWell = InkWell(
      onTap: widget.onTap,
      focusNode: widget.onTap != null ? _focusNode : null,
      borderRadius: WpRadius.borderFull,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: widget.isDark
              ? WpColorsDark.surfaceChipFill
              : WpColorsLight.surfaceChipFill,
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
            Text('${widget.modeLabel} — $stateLabel', style: widget.textStyle),
          ],
        ),
      ),
    );

    final body = widget.onTap != null
        ? WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.full,
            child: inkWell,
          )
        : inkWell;

    return Semantics(
      label: widget.l10n.statusBarSttTooltip,
      button: true,
      child: Tooltip(message: widget.l10n.statusBarSttTooltip, child: body),
    );
  }

  /// Resolves the display triple (dot color, label, spinner) by prioritising
  /// the recording lifecycle phase over the STT subprocess state.
  (Color, String, bool) _resolveDisplay() {
    // Active recording phases take priority over STT subprocess state.
    switch (widget.recordingPhase) {
      case RecordingPhase.recording:
        return (
          widget.isDark ? WpColorsDark.error : WpColorsLight.error,
          widget.l10n.statusBarRecording,
          true,
        );
      case RecordingPhase.transcribing:
        return (
          widget.isDark ? WpColorsDark.accent : WpColorsLight.accent,
          widget.l10n.statusBarTranscribing,
          true,
        );
      case RecordingPhase.done:
        return (
          widget.isDark ? WpColorsDark.success : WpColorsLight.success,
          widget.l10n.statusBarDone,
          false,
        );
      case RecordingPhase.error:
        return (
          widget.isDark ? WpColorsDark.error : WpColorsLight.error,
          widget.l10n.sttStatusError,
          false,
        );
      case RecordingPhase.idle:
        // Fall through to STT subprocess state below.
        break;
    }

    // Idle — show STT subprocess state.
    return switch (widget.state) {
      SttServerState.stopped => (
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        widget.l10n.sttStatusStandby,
        false,
      ),
      SttServerState.starting => (
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent,
        _startingLabel(),
        true,
      ),
      SttServerState.ready => (
        widget.isDark ? WpColorsDark.success : WpColorsLight.success,
        widget.l10n.sttStatusReady,
        false,
      ),
      SttServerState.error => (
        widget.isDark ? WpColorsDark.error : WpColorsLight.error,
        widget.l10n.sttStatusError,
        false,
      ),
    };
  }

  /// Returns e.g. "Starting... (15s)" when elapsed time is available.
  String _startingLabel() {
    final since = widget.startingSince;
    if (since == null) return widget.l10n.sttStatusStarting;
    final elapsed = DateTime.now().difference(since).inSeconds;
    if (elapsed < 2) return widget.l10n.sttStatusStarting;
    return '${widget.l10n.sttStatusStarting} (${elapsed}s)';
  }
}

class _StatusChip extends StatefulWidget {
  const _StatusChip({
    required this.label,
    required this.textStyle,
    required this.isDark,
    this.icon,
    this.tooltip,
    this.onTap,
    this.dimmed = false,
  });

  final IconData? icon;
  final String label;
  final TextStyle textStyle;
  final bool isDark;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final inkWell = InkWell(
      onTap: widget.onTap,
      focusNode: widget.onTap != null ? _focusNode : null,
      borderRadius: WpRadius.borderFull,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: widget.isDark
              ? WpColorsDark.surfaceChipFill
              : WpColorsLight.surfaceChipFill,
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: WpIconSize.xs, color: cs.secondary),
              const SizedBox(width: WpSpacing.xxs),
            ],
            Text(widget.label, style: widget.textStyle),
          ],
        ),
      ),
    );

    final body = widget.onTap != null
        ? WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.full,
            child: inkWell,
          )
        : inkWell;

    final chip = Semantics(
      label: widget.tooltip ?? widget.label,
      button: true,
      child: Opacity(opacity: widget.dimmed ? 0.5 : 1.0, child: body),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: chip);
    }
    return chip;
  }
}

// ---------------------------------------------------------------------------
// After-transcription action chip — quick-switcher with popup menu
// ---------------------------------------------------------------------------

class _AfterActionChip extends StatelessWidget {
  const _AfterActionChip({
    required this.label,
    required this.current,
    required this.textStyle,
    required this.isDark,
    required this.l10n,
    required this.onChanged,
  });

  final String label;
  final AfterTranscriptionAction current;
  final TextStyle textStyle;
  final bool isDark;
  final L10n l10n;
  final ValueChanged<AfterTranscriptionAction> onChanged;

  IconData _iconFor(AfterTranscriptionAction action) => switch (action) {
    AfterTranscriptionAction.clipboard => LucideIcons.clipboard,
    AfterTranscriptionAction.paste => LucideIcons.clipboardPaste,
    AfterTranscriptionAction.clipboardAndPaste => LucideIcons.clipboardCheck,
    AfterTranscriptionAction.nothing => LucideIcons.clipboardX,
  };

  String _labelFor(AfterTranscriptionAction action) => switch (action) {
    AfterTranscriptionAction.clipboard => l10n.statusBarAfterCopy,
    AfterTranscriptionAction.paste => l10n.statusBarAfterPaste,
    AfterTranscriptionAction.clipboardAndPaste => l10n.statusBarAfterBoth,
    AfterTranscriptionAction.nothing => l10n.statusBarAfterNothing,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<AfterTranscriptionAction>(
      onSelected: onChanged,
      initialValue: current,
      tooltip: l10n.settingsAfterTranscription,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      color: isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surface,
      itemBuilder: (_) => [
        for (final action in AfterTranscriptionAction.values)
          PopupMenuItem<AfterTranscriptionAction>(
            value: action,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconFor(action),
                  size: WpIconSize.sm,
                  color: action == current
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: WpSpacing.sm),
                Text(
                  _labelFor(action),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: action == current
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: action == current ? cs.primary : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? WpColorsDark.surfaceChipFill
              : WpColorsLight.surfaceChipFill,
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(current), size: WpIconSize.xs, color: cs.secondary),
            const SizedBox(width: WpSpacing.xxs),
            Text(label, style: textStyle),
            const SizedBox(width: 2),
            Icon(LucideIcons.chevronUp, size: 10, color: cs.secondary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Auto-Paste-Off hint chip — persistent, dismissible nudge surfaced after the
// user skips Auto-Paste in onboarding. Tapping the body opens Settings (and
// scrolls to the After-Transcription section). The trailing X persists the
// dismiss flag.
// ---------------------------------------------------------------------------

class _AutoPasteOffHintChip extends StatelessWidget {
  const _AutoPasteOffHintChip({
    required this.textStyle,
    required this.isDark,
    required this.l10n,
    this.onTap,
    this.onDismiss,
  });

  final TextStyle textStyle;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Semantics(
      label: l10n.statusBarAutoPasteOffHintTooltip,
      child: Tooltip(
        message: l10n.statusBarAutoPasteOffHintTooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? WpColorsDark.surfaceChipFill
                : WpColorsLight.surfaceChipFill,
            borderRadius: WpRadius.borderFull,
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onTap,
                borderRadius: WpRadius.borderFull,
                mouseCursor: onTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.clipboardX,
                      size: WpIconSize.xs,
                      color: accent,
                    ),
                    const SizedBox(width: WpSpacing.xxs),
                    Text(l10n.statusBarAutoPasteOffHint, style: textStyle),
                  ],
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              Tooltip(
                message: l10n.statusBarAutoPasteOffHintDismiss,
                child: InkWell(
                  onTap: onDismiss,
                  borderRadius: WpRadius.borderFull,
                  mouseCursor: onDismiss != null
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Icon(
                      LucideIcons.x,
                      size: WpIconSize.xs,
                      color: cs.onSurface.withValues(alpha: 0.6),
                      semanticLabel: l10n.statusBarAutoPasteOffHintDismiss,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
