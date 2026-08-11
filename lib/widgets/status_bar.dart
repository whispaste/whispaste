import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/build_config.dart';
import '../core/config/settings_enums.dart' show AfterTranscriptionAction;
import '../core/config/settings_labels.dart' show afterTranscriptionStatusLabel;
import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart'
    show RecordingPhase, SttServerState;
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/microphone_selection_service.dart' show micDefaultLabel;
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
///
/// Wp naming — deliberately unprefixed: the prefix marks the shared component
/// vocabulary of lib/widgets/ (types you instantiate, plus the `showWp*`
/// launchers that are a component's own public API). This is a pure boolean
/// predicate over settings, not something anyone puts in a widget tree.
bool shouldShowAutoPasteOffHint({
  required AfterTranscriptionAction afterAction,
  required bool onboardingCompleted,
  required bool autoPasteOffHintDismissed,
  bool autoPasteSupported = kAutoPasteSupported,
}) {
  // Auto-Paste isn't a toggleable choice in MAS builds — it's not offered at
  // all (see AfterTranscriptionSection/_AfterActionChip). A "disabled" hint
  // would tell users they turned off something that was never available to
  // turn on.
  if (!autoPasteSupported) return false;
  if (!onboardingCompleted) return false;
  if (autoPasteOffHintDismissed) return false;
  // Auto-Paste is considered ON when the action injects the transcript at
  // the cursor — `paste`/`clipboardAndPaste` (the visible "paste" action;
  // the native mechanism underneath may be a ⌘V shortcut or synthetic
  // Unicode typing, an implementation detail — see DesktopPaster.paste).
  // Anything else (`clipboard` only, `nothing`) counts as Auto-Paste off.
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
    this.microphoneLabel,
    this.microphoneOptions,
    this.hotkeyLabel,
    this.hotkeyEnabled = true,
    this.updateVersion,
    this.updateReadyToInstall = false,
    this.showAutoPasteOffHint = false,
    this.onSttTap,
    this.onAfterActionChanged,
    this.onMicrophoneChanged,
    this.onMicrophoneMenuOpened,
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

  /// Raw label of the currently selected microphone (`'Default'` sentinel or
  /// a device name), or null to hide the microphone chip.
  final String? microphoneLabel;

  /// Raw microphone option labels for the popup, system-default sentinel
  /// first (see `buildMicrophoneOptions`). Null hides the chip — the host
  /// passes null when only the default pseudo-device was enumerated, so the
  /// chip mirrors the tray submenu's "nothing to switch to" rule.
  final List<String>? microphoneOptions;

  /// Formatted hotkey label, e.g. "Ctrl+Shift+D", or null to hide.
  final String? hotkeyLabel;

  /// Whether the global hotkey is enabled.
  final bool hotkeyEnabled;

  /// Available update version label, e.g. "1.3.0", or null to hide (unless
  /// [updateReadyToInstall] is set — that chip needs no version string).
  final String? updateVersion;

  /// Whether a downloaded update is ready to install (PRD Bug 6 — the chip
  /// used to only ever appear for the `available` phase, even though the
  /// About page already surfaces this state). Takes precedence over
  /// [updateVersion] when both are set.
  final bool updateReadyToInstall;

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

  /// Callback when user selects a different microphone (raw label).
  final ValueChanged<String>? onMicrophoneChanged;

  /// Callback when the microphone popup opens — the host should re-enumerate
  /// devices here so the next open reflects docking/undocking changes (same
  /// freshness rule as the tray submenu).
  final VoidCallback? onMicrophoneMenuOpened;

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
          //
          // Start-aligned, not centred: the chip row's membership changes at
          // runtime (microphone, after-action, update, Auto-Paste hint all
          // come and go), and a centred row re-flows every chip sideways each
          // time one appears — the STT chip, the one that is always there,
          // never sits still. Anchored to the start, an arriving chip only
          // grows the row to the right and every chip before it stays put.
          //
          // The `start: xl` inset puts the first chip on the same gutter
          // `WpPageShell`'s default `fromLTRB(xl, …)` padding gives page
          // content, so the status line reads as the same column as the page
          // above it rather than as a second, narrower one.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.only(start: WpSpacing.xl),
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
                    if (microphoneLabel != null &&
                        microphoneOptions != null &&
                        onMicrophoneChanged != null) ...[
                      const SizedBox(width: WpSpacing.xs),
                      _MicrophoneChip(
                        current: microphoneLabel!,
                        options: microphoneOptions!,
                        textStyle: textStyle,
                        isDark: isDark,
                        l10n: l10n,
                        onChanged: onMicrophoneChanged!,
                        onOpened: onMicrophoneMenuOpened,
                      ),
                    ],
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
                    if (updateReadyToInstall) ...[
                      const SizedBox(width: WpSpacing.xs),
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _StatusChip.build
                      _StatusChip(
                        icon: LucideIcons.packageCheck,
                        label: l10n.updateInstall,
                        textStyle: textStyle,
                        isDark: isDark,
                        tooltip: l10n.updateInstall,
                        onTap: onUpdateTap,
                      ),
                    ] else if (updateVersion != null) ...[
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
    if (old.recordingPhase != widget.recordingPhase ||
        old.state != widget.state) {
      final (_, stateLabel, _) = _resolveDisplay();
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${widget.modeLabel} — $stateLabel',
        Directionality.of(context),
      );
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
          color: WpColors.surfaceChipFill,
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

    // House idiom (`section.dart`): MergeSemantics + a *label-less*
    // Semantics. The old label repeated two things the merged subtree
    // already supplies — `Text('${modeLabel} — $stateLabel')` renders the
    // state, and `Tooltip` contributes `statusBarSttTooltip` as the node's
    // tooltip field — so the chip announced as "Spracherkennung: Whisper —
    // Bereit, Whisper — Bereit". Dropping the label leaves name and tooltip
    // cleanly separated, which is what the two fields are for.
    //
    // `button:` is now conditional: the chip is only tappable when `onTap`
    // is wired, and claiming a button role on the inert variant promised an
    // action that does not exist. The live state changes are announced
    // separately in `didUpdateWidget`, so this node stays a plain name.
    return MergeSemantics(
      child: Semantics(
        button: widget.onTap != null,
        child: Tooltip(message: widget.l10n.statusBarSttTooltip, child: body),
      ),
    );
  }

  /// Resolves the display triple (dot color, label, spinner) by prioritising
  /// the recording lifecycle phase over the STT subprocess state.
  (Color, String, bool) _resolveDisplay() {
    // Active recording phases take priority over STT subprocess state.
    switch (widget.recordingPhase) {
      case RecordingPhase.recording:
        return (WpColors.error, widget.l10n.statusBarRecording, true);
      case RecordingPhase.transcribing:
        return (
          // Recording family: this rung reads a `RecordingPhase`, so it is the
          // one accent in this chip that means "your recording is in flight".
          // The `SttServerState.starting` rung below looks the same today but
          // reads a different enum (subprocess boot, no recording running) and
          // therefore stays on the generic accent.
          WpColors.recordingAccent,
          widget.l10n.statusBarTranscribing,
          true,
        );
      case RecordingPhase.done:
        return (WpColors.success, widget.l10n.statusBarDone, false);
      case RecordingPhase.error:
        return (WpColors.error, widget.l10n.sttStatusError, false);
      case RecordingPhase.idle:
        // Fall through to STT subprocess state below.
        break;
    }

    // Idle — show STT subprocess state.
    return switch (widget.state) {
      SttServerState.stopped => (
        WpColors.textMuted,
        widget.l10n.sttStatusStandby,
        false,
      ),
      SttServerState.starting => (WpColors.accent, _startingLabel(), true),
      SttServerState.ready => (
        WpColors.success,
        widget.l10n.sttStatusReady,
        false,
      ),
      SttServerState.error => (
        WpColors.error,
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
          color: WpColors.surfaceChipFill,
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

    // Same treatment `_SttChipState` above already got — this chip was missed
    // by that pass and still had both of its defects.
    //
    // The label is gone: it repeated `Text(widget.label)` from the subtree
    // ("Ready, Ready" whenever no tooltip was set), and where a tooltip *was*
    // set it glued the two together into one name. `Tooltip` fills the node's
    // own tooltip field, so both survive — properly separated into name and
    // description instead of concatenated into the name.
    //
    // `button:` is now conditional. Most chips in this bar are read-only
    // status, yet every one of them claimed a button role, inviting the user
    // to activate something inert.
    final dimmable = Opacity(opacity: widget.dimmed ? 0.5 : 1.0, child: body);

    // Tooltip *inside* the MergeSemantics, as in `_SttChipState` — outside it
    // the tooltip would sit on its own ancestor node instead of folding into
    // the chip's.
    return MergeSemantics(
      child: Semantics(
        button: widget.onTap != null,
        child: widget.tooltip != null
            ? Tooltip(message: widget.tooltip!, child: dimmable)
            : dimmable,
      ),
    );
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

  String _labelFor(AfterTranscriptionAction action) =>
      afterTranscriptionStatusLabel(action, l10n);

  /// Whether [action] needs simulated-keystroke auto-paste, unavailable
  /// when [kAutoPasteSupported] is `false` (the 2.4.5 kill switch — see its
  /// doc in build_config.dart).
  bool _requiresAutoPaste(AfterTranscriptionAction action) =>
      action == AfterTranscriptionAction.paste ||
      action == AfterTranscriptionAction.clipboardAndPaste;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<AfterTranscriptionAction>(
      onSelected: onChanged,
      initialValue: current,
      tooltip: l10n.settingsAfterTranscription,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      color: WpColors.surfaceElevated,
      itemBuilder: (_) => [
        // Auto-paste-requiring actions aren't offered at all when the build
        // can't perform them (MAS sandbox) — see the matching comment on
        // AfterTranscriptionSection in feedback_section.dart.
        for (final action in AfterTranscriptionAction.values)
          if (kAutoPasteSupported || !_requiresAutoPaste(action))
            PopupMenuItem<AfterTranscriptionAction>(
              value: action,
              child: _AfterActionRow(
                action: action,
                current: current,
                cs: cs,
                label: _labelFor(action),
                icon: _iconFor(action),
              ),
            ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: WpColors.surfaceChipFill,
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

/// Icon + label row shared by enabled and disabled [_AfterActionChip] popup
/// menu items, so the disabled (Mac App Store) rendering only differs by the
/// [Tooltip]/[Opacity] wrapper around it.
class _AfterActionRow extends StatelessWidget {
  const _AfterActionRow({
    required this.action,
    required this.current,
    required this.cs,
    required this.label,
    required this.icon,
  });

  final AfterTranscriptionAction action;
  final AfterTranscriptionAction current;
  final ColorScheme cs;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isCurrent = action == current;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: WpIconSize.sm,
          color: isCurrent ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: WpSpacing.sm),
        Text(
          label,
          style: TextStyle(
            fontSize: WpTypography.body,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
            color: isCurrent ? cs.primary : cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Microphone chip — quick-switcher with popup menu. Mirrors the tray
// submenu: same option list (system default first, selected-but-unplugged
// device appended) and the same selection path via
// MicrophoneSelectionService, wired by the host.
// ---------------------------------------------------------------------------

class _MicrophoneChip extends StatelessWidget {
  const _MicrophoneChip({
    required this.current,
    required this.options,
    required this.textStyle,
    required this.isDark,
    required this.l10n,
    required this.onChanged,
    this.onOpened,
  });

  /// Raw label of the current selection (`micDefaultLabel` or device name).
  final String current;

  /// Raw option labels, system-default sentinel first.
  final List<String> options;
  final TextStyle textStyle;
  final bool isDark;
  final L10n l10n;
  final ValueChanged<String> onChanged;
  final VoidCallback? onOpened;

  String _labelFor(String option) =>
      option == micDefaultLabel ? l10n.settingsMicSystemDefault : option;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      onSelected: onChanged,
      onOpened: onOpened,
      initialValue: current,
      tooltip: l10n.settingsMicrophone,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      color: WpColors.surfaceElevated,
      itemBuilder: (_) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option,
            child: _MicrophoneRow(
              isCurrent: option == current,
              cs: cs,
              label: _labelFor(option),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: WpColors.surfaceChipFill,
          borderRadius: WpRadius.borderFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mic, size: WpIconSize.xs, color: cs.secondary),
            const SizedBox(width: WpSpacing.xxs),
            // Device names come from the OS and can be arbitrarily long
            // ("Razer Seiren Mini 2 USB Ultra…") — cap the chip so one mic
            // can't crowd out the rest of the status bar.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                _labelFor(current),
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(LucideIcons.chevronUp, size: 10, color: cs.secondary),
          ],
        ),
      ),
    );
  }
}

/// Icon + label row for [_MicrophoneChip] popup menu items — same current-
/// value highlight (primary color, semi-bold) as [_AfterActionRow].
class _MicrophoneRow extends StatelessWidget {
  const _MicrophoneRow({
    required this.isCurrent,
    required this.cs,
    required this.label,
  });

  final bool isCurrent;
  final ColorScheme cs;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.mic,
          size: WpIconSize.sm,
          color: isCurrent ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: WpSpacing.sm),
        // OS device names are arbitrarily long — ellipsize instead of
        // overflowing the popup's max menu width.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: WpTypography.body,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
              color: isCurrent ? cs.primary : cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Auto-Paste-Off hint chip — persistent, dismissible nudge surfaced after the
// user skips Auto-Paste in onboarding. Tapping the body opens Settings (and
// scrolls to the After-Transcription section). The trailing X persists the
// dismiss flag.
// ---------------------------------------------------------------------------

class _AutoPasteOffHintChip extends StatefulWidget {
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
  State<_AutoPasteOffHintChip> createState() => _AutoPasteOffHintChipState();
}

/// Stateful only to own the two focus nodes. Both actions used to be bare
/// `InkWell`s with neither a node nor a ring, while every other tappable chip
/// in this bar (`_StatusChip`, `_SttChip`) has had both all along — so the one
/// chip in the row that actually asks the user to do something was the one
/// they could not reach without a mouse.
class _AutoPasteOffHintChipState extends State<_AutoPasteOffHintChip> {
  final FocusNode _openFocusNode = FocusNode(debugLabel: 'AutoPasteHintOpen');
  final FocusNode _dismissFocusNode = FocusNode(
    debugLabel: 'AutoPasteHintDismiss',
  );

  @override
  void dispose() {
    _openFocusNode.dispose();
    _dismissFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = widget.l10n;
    final onTap = widget.onTap;
    final onDismiss = widget.onDismiss;
    const accent = WpColors.accent;

    // No `label:` — it used to repeat the tooltip string verbatim, so the
    // chip stated the same fact three times in a row: once as the wrapper
    // label ("Auto-Paste ist aktuell aus. Klicken, um die Einstellungen zu
    // öffnen."), once as the rendered `Text` ("Auto-Paste deaktiviert, in
    // Settings aktivierbar"), and once more as the tooltip the `Tooltip`
    // below contributes by itself. `container: true` keeps the chip a single
    // group; the name now comes from the visible text and the longer
    // explanation stays where it belongs, in the tooltip field.
    //
    // Not `MergeSemantics`: the chip holds two independent targets — open
    // settings, and dismiss — and merging would collapse them into one.
    return Semantics(
      container: true,
      child: Tooltip(
        message: l10n.statusBarAutoPasteOffHintTooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: WpColors.surfaceChipFill,
            borderRadius: WpRadius.borderFull,
            // The tint ladder's outline rung, not a hand-mixed 40 %: this is a
            // resting 1 px chip border, which is exactly what 30 % is for.
            border: Border.all(color: WpColors.accentBorder30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WpFocusRing(
                focusNode: _openFocusNode,
                radius: WpRadius.full,
                child: InkWell(
                  onTap: onTap,
                  focusNode: onTap != null ? _openFocusNode : null,
                  borderRadius: WpRadius.borderFull,
                  // WpFocusRing owns the focus visual — as on the chips above.
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  mouseCursor: onTap != null
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.clipboardX,
                        size: WpIconSize.xs,
                        color: accent,
                      ),
                      const SizedBox(width: WpSpacing.xxs),
                      Text(
                        l10n.statusBarAutoPasteOffHint,
                        style: widget.textStyle,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              Tooltip(
                message: l10n.statusBarAutoPasteOffHintDismiss,
                child: WpFocusRing(
                  focusNode: _dismissFocusNode,
                  radius: WpRadius.full,
                  child: InkWell(
                    onTap: onDismiss,
                    focusNode: onDismiss != null ? _dismissFocusNode : null,
                    borderRadius: WpRadius.borderFull,
                    focusColor: Colors.transparent,
                    highlightColor: Colors.transparent,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
