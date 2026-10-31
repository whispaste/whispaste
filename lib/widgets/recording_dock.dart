import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/config/build_config.dart';
import '../core/config/settings_enums.dart' show AfterTranscriptionAction;
import '../core/config/settings_labels.dart'
    show afterTranscriptionDockLabel, afterTranscriptionStatusLabel;
import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart'
    show RecordingPhase, SttServerState;
import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart'
    show
        WpDockTokens,
        WpShellTokens,
        WpSurfacePalette,
        WpTypeScaleTokens,
        wpStagePalette;
import '../core/theme/tokens.dart';
import '../services/automation_api/automation_api_controller.dart'
    show AutomationApiRunState;
import '../services/microphone_selection_service.dart' show micDefaultLabel;
import '../services/transcription/slice_progress.dart';
import '../services/recording_orchestrator.dart'
    show recordingOrchestratorProvider;
import 'recording_dock_controls.dart';
import 'recording_dock_layout.dart';
import 'wp_focus_ring.dart';
import 'wp_status_dot.dart';

export 'recording_dock_controls.dart' show WpDockChoice, WpDockChoiceSet;

/// The recording dock's navy palette. The dock is a navy panel in every
/// appearance mode (AR-20/AR-21), so it reads the stage palette directly
/// rather than the active [WpColors] set.
const WpSurfacePalette _dock = wpStagePalette;

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

/// Figure space (U+2007) — the one blank whose advance width equals a
/// *tabular* digit's. In the bundled Inter it is byte-identical to the `.tf`
/// digit glyphs at every shipped weight (1328 / 1327 / 1325 font units at
/// Regular / Medium / SemiBold); a plain space is less than half that
/// (546–576) and would not hold a numeric column.
const String _figureSpace = '\u2007';

/// Label of the far-right backend chip — `'CPU'` before a reading exists,
/// `'CPU · ␣␣9%'` / `'CPU · 100%'` once one does.
///
/// The percent is right-aligned in a fixed three-character column so the chip
/// keeps one width across every digit-count change (0 → 9 → 10 → 99 → 100).
/// That matters because this chip is a real layout participant of the status
/// bar row: any width change of its own shifts the *centred* chip group
/// (see [WpRecordingDock.build]) sideways, un-damped.
///
/// The padding is only half the job — it fixes the character *count*. The
/// width *per character* is fixed by [FontFeature.tabularFigures], applied at
/// the call site: Inter's default proportional digits run from 833 (`1`) to
/// 1292 (`0`) units, so `'11%'` and `'99%'` would still differ at equal
/// length. Both together, and only both together, make the width constant —
/// dropping either one brings the shift back.
///
/// Wp naming — deliberately unprefixed, same rule as
/// [shouldShowAutoPasteOffHint]: this is a pure string format, not something
/// anyone puts in a widget tree.
String backendUtilizationChipLabel(String backendKind, double? percent) =>
    percent == null
    ? backendKind
    : '$backendKind · ${percent.round().toString().padLeft(3, _figureSpace)}%';

/// Look of the sponsor chip: the call to support, or the thank-you state for
/// supporters (decisions 4, 6 and S2 of `internal-notes`).
enum WpSupportChipMode { sponsor, thanks }

/// Transcription or refinement is running; the primary action is inert.
bool _isBusy(RecordingPhase phase) =>
    phase == RecordingPhase.transcribing || phase == RecordingPhase.refining;

/// Primary action label: the dictate state of the recording pipeline. While
/// the pipeline is busy the button stays inert and keeps its neutral label; the
/// status chip carries the processing word, so it is shown only once.
String _dictateLabel(L10n l10n, RecordingPhase phase) => switch (phase) {
  RecordingPhase.recording => l10n.dockStopDictation,
  _ => l10n.dockDictate,
};

/// One child of the dock row: its selector id (null for non-selectors), the
/// widget, and the width it is laid out at.
class _DockItem {
  const _DockItem(this.id, this.child, this.width);

  final String? id;
  final Widget child;
  final double width;
}

class WpRecordingDock extends ConsumerWidget {
  const WpRecordingDock({
    super.key,
    required this.sttModeLabel,
    this.engine,
    this.sttState = SttServerState.stopped,
    this.backendKind,
    this.backendUtilizationPercent,
    this.sttStartingSince,
    this.sttModelMissing = false,
    this.sttModelDownloadPercent,
    this.recordingPhase = RecordingPhase.idle,
    this.sliceProgress,
    this.doneMessage,
    this.donePasteFailed = false,
    this.doneUnconfirmed = false,
    this.afterActionLabel,
    this.afterAction,
    this.microphoneLabel,
    this.microphoneOptions,
    this.hotkeyLabel,
    this.hotkeyEnabled = true,
    this.updateVersion,
    this.updateReadyToInstall = false,
    this.showAutoPasteOffHint = false,
    this.automationApiRunState,
    this.automationApiPort,
    this.automationApiRequestedPort,
    this.onSttTap,
    this.onAfterActionChanged,
    this.onMicrophoneChanged,
    this.onMicrophoneMenuOpened,
    this.onHotkeyTap,
    this.onUpdateTap,
    this.onAutoPasteOffHintTap,
    this.onAutoPasteOffHintDismiss,
    this.onAutomationApiTap,
    this.supportChipMode,
    this.onSupportTap,
    this.smartMode,
    this.localProcessing = false,
    this.language,
  });

  /// Active STT mode, e.g. "On device" or "OpenAI".
  final String sttModeLabel;

  /// Current state of the STT server subprocess.
  final SttServerState sttState;

  /// The confirmed transcription compute-device kind — `'CPU'` or `'GPU'`
  /// (never the specific architecture; see `_sttBackendKind` in `app.dart`),
  /// or `null` to hide the far-right backend-utilization chip entirely (no
  /// local model loaded yet, the active engine has no GPU concept, or the
  /// user turned the indicator off in Settings).
  final String? backendKind;

  /// This process's CPU utilization as a 0..100 share of total machine
  /// capacity, or `null` before a reading exists. Shown regardless of
  /// [backendKind]: even on the GPU backend, whisper.cpp still drives CPU
  /// threads, so this stays a meaningful "is it working" signal — see
  /// `process_cpu_probe.dart`'s file doc comment for why no portable,
  /// sudo-free *GPU*-load number exists to show instead when [backendKind]
  /// is `'GPU'` (the tooltip clarifies that this reading is CPU, not GPU,
  /// load).
  final double? backendUtilizationPercent;

  /// When the STT server entered the starting state (for elapsed display).
  final DateTime? sttStartingSince;

  /// Current phase of the recording lifecycle.
  final RecordingPhase recordingPhase;

  /// Slices finished of a long recording being transcribed: the status chip
  /// shows "part k of n" while it runs. Null for every other recording.
  final SliceProgress? sliceProgress;

  /// Done label for the finished recording's real outcome, from
  /// `doneMessageFor`. Null falls back to the generic "Done".
  final String? doneMessage;

  /// The finished run's paste failed: the done dot turns to the warning
  /// colour instead of green (XP-5-07).
  final bool donePasteFailed;

  /// The paste was attempted but is not confirmed: the done dot is neutral,
  /// neither green ("pasted") nor the warning colour (a failure). Label:
  /// "In der Zwischenablage" (W-D1).
  final bool doneUnconfirmed;

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
  /// Visibility is decided by the caller — see `WpRecordingDock` consumer in
  /// `app.dart`. The chip is shown when Auto-Paste is off **and** onboarding
  /// has completed **and** the user has not dismissed the hint.
  final bool showAutoPasteOffHint;

  /// Current lifecycle state of the local Automation API, or `null` to hide
  /// the chip entirely — the API is off by default (see
  /// `AutomationApiController`), so most users never see this chip. Shown
  /// only for `running`/`error`; `stopped` also hides the chip, same as
  /// `null` (an explicit "off" state is not worth a persistent chip for a
  /// feature that defaults to off).
  final AutomationApiRunState? automationApiRunState;

  /// The bound port while [automationApiRunState] is `running`, or `null`
  /// otherwise.
  final int? automationApiPort;

  /// The port the current start attempt was configured for — differs from
  /// [automationApiPort] only when the target port was taken and a fallback
  /// port bound instead. See `AutomationApiState.requestedPort`.
  final int? automationApiRequestedPort;

  /// Callback when user taps the STT chip (navigate to settings).
  final VoidCallback? onSttTap;

  /// The selected on-device model is not on disk — idle "Standby" would
  /// read as "all set" although the next dictation cannot run.
  final bool sttModelMissing;

  /// Progress of a running speech-model download, `null` when none runs.
  final int? sttModelDownloadPercent;

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

  /// Callback when user taps the Automation API chip (navigate to
  /// settings).
  final VoidCallback? onAutomationApiTap;

  /// Sponsor chip look, or `null` to hide the chip.
  final WpSupportChipMode? supportChipMode;

  /// Callback when user taps the sponsor chip (opens the support page).
  final VoidCallback? onSupportTap;

  /// The Smart Mode dropdown, or null to hide the group.
  final WpDockChoiceSet? smartMode;

  /// Whether transcription AND the active post-processing run on this device.
  /// Only then does the status segment say "Lokal bereit" — see AR-06.
  final bool localProcessing;

  /// The recognition-language dropdown, or null to hide it (Parakeet cannot
  /// choose a language per request).
  final WpDockChoiceSet? language;

  /// The speech-recognition dropdown: the on-device engines and the cloud
  /// providers that work. Null leaves the engine out of the row.
  final WpDockChoiceSet? engine;

  static const List<String> _rowSelectorIds = [
    'smart-mode',
    'engine',
    'language',
    'output-action',
    'microphone',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildSurface(
        context,
        ref,
        constraints.maxWidth - 2 * WpShellTokens.dockInset,
      ),
    );
  }

  /// The dock row. Widths are measured at the current text scale and handed to
  /// [planDockRow]; whatever does not fit moves into the Mehr menu.
  Widget _buildSurface(BuildContext context, WidgetRef ref, double dockWidth) {
    final l10n = L10n.of(context);
    final specs = _selectorSpecs(context, l10n);
    final overflowWidth = _hasMenuContent(l10n, specs)
        ? WpDockTokens.controlHeight
        : 0.0;
    var plan = _planRow(context, l10n, dockWidth, specs, overflowWidth);
    final entries = _menuEntries(context, l10n, plan);
    if (entries.isEmpty) {
      plan = _planRow(context, l10n, dockWidth, specs, 0);
    }

    final dictateWidth = _dictateWidth(context, l10n, plan);
    final items = <_DockItem>[
      _DockItem(
        null,
        _dictateButton(ref, l10n, plan, dictateWidth),
        dictateWidth,
      ),
      for (final id in _rowSelectorIds)
        if (specs.containsKey(id) &&
            plan.forms[id] != WpDockSelectorForm.inMenu)
          _DockItem(
            id,
            _selectorWidget(context, l10n, id, plan.forms[id]!),
            _selectorWidth(specs[id]!, plan.forms[id]!),
          ),
      if (entries.isNotEmpty)
        _DockItem(
          null,
          WpDockOverflow(
            entries: entries,
            attention: _attention(l10n),
            tooltip: l10n.dockOverflow,
            onOpened: onMicrophoneMenuOpened,
          ),
          WpDockTokens.controlHeight,
        ),
    ];

    return _dockSurface(
      context,
      items: items,
      status: _statusChip(l10n, plan, dockWidth),
      fits: plan.fits,
      statusWidth: _statusShortWidth(context),
    );
  }

  /// Width the status is reserved when shortened. A done message may wrap to
  /// two lines at large text scales instead of being cut mid-word (UX-105).
  /// The width is the narrowest split of the words into two lines, so the
  /// greedy wrap never needs a third line. Other states keep the short width.
  double _statusShortWidth(BuildContext context) {
    final base = 90 * MediaQuery.textScalerOf(context).scale(1);
    final message = doneMessage;
    if (recordingPhase != RecordingPhase.done || message == null) return base;
    final style = Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(fontSize: WpTypeScaleTokens.bodyLg);
    final words = message.split(' ');
    var twoLines = dockTextWidth(context, message, style);
    for (var k = 1; k < words.length; k++) {
      final first = dockTextWidth(
        context,
        words.sublist(0, k).join(' '),
        style,
      );
      final second = dockTextWidth(context, words.sublist(k).join(' '), style);
      twoLines = math.min(twoLines, math.max(first, second));
    }
    // The dot, its gap, the chip padding and the measure slack around the text.
    const chrome =
        _statusDotSize + WpSpacing.xs + 2 * WpSpacing.xs + dockMeasureSlack;
    return math.max(base, twoLines + chrome);
  }

  /// The selectors that appear in the row, measured at the current text scale.
  /// A selector without its value is left out.
  Map<String, WpDockSelectorSpec> _selectorSpecs(
    BuildContext context,
    L10n l10n,
  ) {
    final specs = <String, WpDockSelectorSpec>{};
    void add(
      String id,
      String overline,
      String value, {
      String? compactValue,
      int? rank,
    }) {
      final valueWidth = dockTextWidth(context, value, dockValueStyle(context));
      final compactWidth = dockTextWidth(
        context,
        compactValue ?? value,
        dockValueStyle(context),
      );
      final overlineWidth = dockTextWidth(
        context,
        overline.toUpperCase(),
        dockOverlineStyle(context),
      );
      specs[id] = WpDockSelectorSpec(
        id: id,
        labelledWidth:
            dockSelectorChrome +
            math.max(valueWidth, overlineWidth) +
            dockMeasureSlack,
        compactWidth: dockSelectorChrome + compactWidth + dockMeasureSlack,
        iconWidth: WpDockTokens.controlHeight,
        dropRank: rank,
      );
    }

    final smart = smartMode;
    if (smart != null) {
      add(smart.id, smart.overline, smart.currentLabel, rank: 3);
    }
    final eng = engine;
    if (eng != null) add(eng.id, eng.overline, eng.currentLabel);
    final lang = language;
    if (lang != null) add(lang.id, lang.overline, lang.currentLabel, rank: 2);
    if (_outputValid) {
      add(
        'output-action',
        l10n.settingsAfterTranscription,
        afterActionLabel!,
        compactValue: afterTranscriptionStatusLabel(afterAction!, l10n),
        rank: 1,
      );
    }
    if (_micValid) {
      add('microphone', l10n.settingsMicrophone, _micDisplay(l10n), rank: 0);
    }
    return specs;
  }

  bool get _outputValid =>
      afterActionLabel != null &&
      afterAction != null &&
      onAfterActionChanged != null;

  bool get _micValid =>
      microphoneLabel != null &&
      microphoneOptions != null &&
      onMicrophoneChanged != null;

  String _micDisplay(L10n l10n) {
    final current = microphoneLabel ?? '';
    return current == micDefaultLabel ? l10n.settingsMicSystemDefault : current;
  }

  /// Whether anything would go into Mehr, so the overflow button needs room.
  bool _hasMenuContent(L10n l10n, Map<String, WpDockSelectorSpec> specs) =>
      hotkeyLabel != null ||
      specs.values.any((s) => s.droppable) ||
      showAutoPasteOffHint ||
      _updateLabel(l10n) != null ||
      _automationShown ||
      backendKind != null ||
      supportChipMode != null;

  WpDockRowPlan _planRow(
    BuildContext context,
    L10n l10n,
    double dockWidth,
    Map<String, WpDockSelectorSpec> specs,
    double overflowWidth,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final dictateNeed = _dictateNeed(context, l10n);
    return planDockRow(
      WpDockRowMetrics(
        available: dockWidth - 2 * WpSpacing.md,
        dictateFull: math.max(WpDockTokens.dictateWidth, dictateNeed),
        dictateCompact: math.max(WpDockTokens.dictateWidthCompact, dictateNeed),
        dictateIcon: WpDockTokens.controlHeight,
        keycapWidth: _keycapWidth(context),
        // A done message reserves at least its two-line width (UX-105).
        statusFull: math.max(160 * scale, _statusShortWidth(context)),
        statusShort: _statusShortWidth(context),
        overflowWidth: overflowWidth,
        gap: WpDockTokens.itemGap,
        allowLabels:
            dockWidth >= WpDockTokens.breakpointLabels && scale <= 1.25,
        belowCompactBreakpoint: dockWidth < WpDockTokens.breakpointCompact,
        selectors: specs.values.toList(),
      ),
    );
  }

  double _dictateNeed(BuildContext context, L10n l10n) =>
      dockTextWidth(
        context,
        _dictateLabel(l10n, recordingPhase),
        dockDictateLabelStyle(context),
      ) +
      2 * WpSpacing.sm +
      WpIconSize.md +
      WpSpacing.xs +
      dockMeasureSlack;

  double _dictateWidth(BuildContext context, L10n l10n, WpDockRowPlan plan) {
    final need = _dictateNeed(context, l10n);
    if (plan.dictateIcon) return WpDockTokens.controlHeight;
    final base = plan.dictateCompact
        ? math.max(WpDockTokens.dictateWidthCompact, need)
        : math.max(WpDockTokens.dictateWidth, need);
    // The keycap sits inside the Dictate button while the plan shows it.
    return plan.keycap && hotkeyLabel != null
        ? base + _keycapWidth(context)
        : base;
  }

  double _keycapWidth(BuildContext context) {
    final hotkey = hotkeyLabel;
    if (hotkey == null) return 0;
    final text = dockTextWidth(context, hotkey, dockKeycapStyle(context));
    return math.max(24, text + 2 * WpSpacing.xs + 2) +
        dockMeasureSlack +
        WpSpacing.xs;
  }

  double _selectorWidth(WpDockSelectorSpec spec, WpDockSelectorForm form) =>
      switch (form) {
        WpDockSelectorForm.labelled => spec.labelledWidth,
        WpDockSelectorForm.compact => spec.compactWidth,
        WpDockSelectorForm.iconOnly => spec.iconWidth,
        WpDockSelectorForm.inMenu => 0,
      };

  Widget _selectorWidget(
    BuildContext context,
    L10n l10n,
    String id,
    WpDockSelectorForm form,
  ) => switch (id) {
    'smart-mode' => _choiceSelector(smartMode!, form),
    'language' => _choiceSelector(language!, form),
    'output-action' => _outputSelector(context, l10n, form),
    'microphone' => _microphoneSelector(context, l10n, form),
    _ => _choiceSelector(engine!, form),
  };

  /// Whether [set] accepts a change right now. A locked set (the speech
  /// engine) waits until the running dictation is over.
  bool _choiceEnabled(WpDockChoiceSet set) =>
      !(set.lockedWhileBusy &&
          (recordingPhase == RecordingPhase.recording ||
              _isBusy(recordingPhase)));

  /// A dropdown in the row. The popup is built on open, so it always shows
  /// the value the settings hold at that moment.
  Widget _choiceSelector(WpDockChoiceSet set, WpDockSelectorForm form) =>
      WpDockSelector(
        key: ValueKey('dock-${set.id}'),
        id: set.id,
        form: form,
        icon: set.icon,
        overline: set.overline,
        value: set.currentLabel,
        // Always opens: a locked set shows its reason in the menu.
        menu: () => [
          WpDockMenuHeader(set.overline),
          ...dockChoiceEntries(set, enabled: _choiceEnabled(set)),
        ],
      );

  Widget _dictateButton(
    WidgetRef ref,
    L10n l10n,
    WpDockRowPlan plan,
    double width,
  ) => WpDockDictate(
    label: _dictateLabel(l10n, recordingPhase),
    recording: recordingPhase == RecordingPhase.recording,
    width: width,
    hotkeyHint: hotkeyLabel,
    keycapLabel: plan.keycap ? hotkeyLabel : null,
    keycapDimmed: !hotkeyEnabled,
    onPressed: _isBusy(recordingPhase)
        ? null
        : () => ref
              .read(recordingOrchestratorProvider.notifier)
              .toggleRecording(),
  );

  Widget _statusChip(L10n l10n, WpDockRowPlan plan, double dockWidth) =>
      // loam-ignore: a11y-interactive-semantics – accessible name is set by the selector's own Semantics
      _SttChip(
        modeLabel: sttModeLabel,
        state: sttState,
        startingSince: sttStartingSince,
        modelMissing: sttModelMissing,
        modelDownloadPercent: sttModelDownloadPercent,
        recordingPhase: recordingPhase,
        sliceProgress: sliceProgress,
        doneMessage: doneMessage,
        donePasteFailed: donePasteFailed,
        doneUnconfirmed: doneUnconfirmed,
        localReady: localProcessing,
        tight: plan.statusShort || dockWidth < WpDockTokens.breakpointCompact,
        l10n: l10n,
        onTap: onSttTap,
      );

  /// Lays the row out. When the planner fits it, the status takes the rest of
  /// the row. When even the last step is too wide, the row keeps its widths and
  /// scrolls sideways (with a scrollbar) instead of overflowing.
  Widget _dockSurface(
    BuildContext context, {
    required List<_DockItem> items,
    required Widget status,
    required bool fits,
    required double statusWidth,
  }) {
    final children = <Widget>[];
    for (final item in items) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: WpDockTokens.itemGap));
      }
      children.add(
        SizedBox(
          width: item.width,
          height: WpDockTokens.controlHeight,
          child: item.child,
        ),
      );
    }
    if (children.isNotEmpty) {
      children.add(const SizedBox(width: WpDockTokens.itemGap));
    }
    final statusAligned = Align(
      alignment: AlignmentDirectional.centerEnd,
      child: status,
    );
    children.add(
      fits
          ? Expanded(child: statusAligned)
          : SizedBox(width: statusWidth, child: statusAligned),
    );

    final row = fits
        ? Row(children: children)
        : _ScrollableDockRow(children: children);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpShellTokens.dockInset,
        0,
        WpShellTokens.dockInset,
        WpShellTokens.dockInset,
      ),
      child: Container(
        key: const ValueKey('dock-surface'),
        height: WpShellTokens.dockHeight,
        decoration: BoxDecoration(
          color: _dock.surface,
          borderRadius: BorderRadius.circular(WpShellTokens.dockRadius),
          // On a dark content surface the navy dock nearly merges into it, so
          // it gets a hairline rim. The light mockup shows none, and light
          // content already separates the dock.
          border: WpColors.current.brightness == Brightness.dark
              ? Border.all(color: WpColorsDark.frostBorder15)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
        child: row,
      ),
    );
  }

  String? _updateLabel(L10n l10n) => updateReadyToInstall
      ? l10n.updateInstall
      : updateVersion == null
      ? null
      : l10n.updateStatusBarChip(updateVersion!);

  bool get _automationShown {
    final runState = automationApiRunState;
    return runState != null && runState != AutomationApiRunState.stopped;
  }

  /// Tooltip of the automation entry; a fallback port names the port that was
  /// in use, so the user can see why the API is not on the usual port.
  String _automationTooltip(L10n l10n) {
    final port = automationApiPort ?? 0;
    final requested = automationApiRequestedPort;
    if (automationApiRunState == AutomationApiRunState.error) {
      return l10n.statusBarAutomationApiTooltipError;
    }
    if (requested != null && requested != port) {
      return l10n.statusBarAutomationApiTooltipFallback(port, requested);
    }
    return l10n.statusBarAutomationApiTooltip(port);
  }

  bool _attention(L10n l10n) =>
      showAutoPasteOffHint ||
      automationApiRunState == AutomationApiRunState.error ||
      _updateLabel(l10n) != null;

  IconData _outputIcon(AfterTranscriptionAction action) => switch (action) {
    AfterTranscriptionAction.clipboard => LucideIcons.clipboard,
    AfterTranscriptionAction.paste => LucideIcons.clipboardPaste,
    AfterTranscriptionAction.clipboardAndPaste => LucideIcons.clipboardCheck,
    AfterTranscriptionAction.nothing => LucideIcons.clipboardX,
  };

  /// Whether [action] needs simulated-keystroke auto-paste, which the build
  /// cannot perform when [kAutoPasteSupported] is false (MAS sandbox).
  bool _needsAutoPaste(AfterTranscriptionAction action) =>
      action == AfterTranscriptionAction.paste ||
      action == AfterTranscriptionAction.clipboardAndPaste;

  /// The output-action choices: one radio group, shared by the selector's
  /// popup and the Mehr menu.
  List<WpDockMenuSpec> _outputChoices(L10n l10n) {
    final current = afterAction!;
    return [
      for (final action in AfterTranscriptionAction.values)
        if (kAutoPasteSupported || !_needsAutoPaste(action))
          WpDockMenuAction(
            id: 'dock-menu-output-${action.name}',
            icon: _outputIcon(action),
            label: afterTranscriptionDockLabel(action, l10n),
            onTap: () => onAfterActionChanged!(action),
            checked: action == current,
          ),
    ];
  }

  Widget _outputSelector(
    BuildContext context,
    L10n l10n,
    WpDockSelectorForm form,
  ) => WpDockSelector(
    key: const ValueKey('dock-output-action'),
    id: 'output-action',
    form: form,
    icon: _outputIcon(afterAction!),
    overline: l10n.settingsAfterTranscription,
    value: afterActionLabel!,
    compactValue: afterTranscriptionStatusLabel(afterAction!, l10n),
    menu: () => [
      WpDockMenuHeader(l10n.settingsAfterTranscription),
      ..._outputChoices(l10n),
    ],
  );

  /// The microphone choices: one radio group, shared by the selector's popup
  /// and the Mehr menu.
  List<WpDockMenuSpec> _microphoneChoices(L10n l10n) {
    final current = microphoneLabel!;
    final options = microphoneOptions!;
    return [
      for (final option in options)
        WpDockMenuAction(
          id: 'dock-menu-microphone-${options.indexOf(option)}',
          icon: LucideIcons.mic,
          label: option == micDefaultLabel
              ? l10n.settingsMicSystemDefault
              : option,
          onTap: () => onMicrophoneChanged!(option),
          checked: option == current,
        ),
    ];
  }

  Widget _microphoneSelector(
    BuildContext context,
    L10n l10n,
    WpDockSelectorForm form,
  ) => WpDockSelector(
    key: const ValueKey('dock-microphone'),
    id: 'microphone',
    form: form,
    icon: LucideIcons.mic,
    overline: l10n.settingsMicrophone,
    value: _micDisplay(l10n),
    onMenuOpened: onMicrophoneMenuOpened,
    menu: () => [
      WpDockMenuHeader(l10n.settingsMicrophone),
      ..._microphoneChoices(l10n),
    ],
  );

  /// The Mehr menu: the selectors that moved out of the row, the shortcut,
  /// the notices, the sponsor entry and the status. Each entry runs the same
  /// action as its control in the row. Groups are divided; the hide entry sits
  /// directly under the sponsor entry.
  List<WpDockMenuSpec> _menuEntries(
    BuildContext context,
    L10n l10n,
    WpDockRowPlan plan,
  ) {
    final groups = [
      _selectorMenuGroup(l10n, plan),
      _outputMenuGroup(l10n, plan),
      _microphoneMenuGroup(l10n, plan),
      _hotkeyMenuGroup(l10n),
      _noticeMenuGroup(l10n),
      _supportMenuGroup(l10n),
      _statusMenuGroup(l10n),
    ];
    final entries = <WpDockMenuSpec>[];
    for (final group in groups.where((g) => g.isNotEmpty)) {
      if (entries.isNotEmpty) entries.add(const WpDockMenuDivider());
      entries.addAll(group);
    }
    return entries;
  }

  /// The dropdowns that moved out of the row, as submenus that open in place.
  List<WpDockMenuSpec> _selectorMenuGroup(L10n l10n, WpDockRowPlan plan) {
    final sets = [?smartMode, ?language, ?engine];
    return [
      for (final set in sets)
        if (plan.forms[set.id] == WpDockSelectorForm.inMenu)
          WpDockMenuSubmenu(
            id: 'dock-menu-${set.menuId}',
            icon: set.icon,
            label: '${set.overline}: ${set.currentLabel}',
            children: dockChoiceEntries(set, enabled: _choiceEnabled(set)),
          ),
    ];
  }

  List<WpDockMenuSpec> _outputMenuGroup(L10n l10n, WpDockRowPlan plan) {
    if (!_outputValid ||
        plan.forms['output-action'] != WpDockSelectorForm.inMenu) {
      return const [];
    }
    return [
      WpDockMenuHeader(l10n.settingsAfterTranscription),
      ..._outputChoices(l10n),
    ];
  }

  List<WpDockMenuSpec> _microphoneMenuGroup(L10n l10n, WpDockRowPlan plan) {
    if (!_micValid || plan.forms['microphone'] != WpDockSelectorForm.inMenu) {
      return const [];
    }
    return [
      WpDockMenuHeader(l10n.settingsMicrophone),
      ..._microphoneChoices(l10n),
    ];
  }

  List<WpDockMenuSpec> _hotkeyMenuGroup(L10n l10n) => [
    if (hotkeyLabel != null)
      WpDockMenuAction(
        id: 'dock-menu-hotkey',
        icon: LucideIcons.keyboard,
        label: l10n.dockMenuHotkeyChange,
        onTap: onHotkeyTap,
      ),
  ];

  List<WpDockMenuSpec> _noticeMenuGroup(L10n l10n) {
    final updateLabel = _updateLabel(l10n);
    final error = automationApiRunState == AutomationApiRunState.error;
    final notices = <WpDockMenuSpec>[
      if (showAutoPasteOffHint)
        WpDockMenuAction(
          id: 'dock-menu-auto-paste',
          icon: LucideIcons.clipboardX,
          label: l10n.statusBarAutoPasteOffHint,
          onTap: onAutoPasteOffHintTap,
        ),
      if (showAutoPasteOffHint && onAutoPasteOffHintDismiss != null)
        WpDockMenuAction(
          id: 'dock-menu-auto-paste-dismiss',
          icon: LucideIcons.x,
          label: l10n.statusBarAutoPasteOffHintDismiss,
          onTap: onAutoPasteOffHintDismiss,
        ),
      if (updateLabel != null)
        WpDockMenuAction(
          id: 'dock-menu-update',
          icon: updateReadyToInstall
              ? LucideIcons.packageCheck
              : LucideIcons.download,
          label: updateLabel,
          onTap: onUpdateTap,
        ),
      if (_automationShown)
        WpDockMenuAction(
          id: 'dock-menu-automation',
          icon: error ? LucideIcons.circleAlert : LucideIcons.terminal,
          label: error
              ? l10n.statusBarAutomationApiChipLabelError
              : l10n.statusBarAutomationApiChipLabel(automationApiPort ?? 0),
          onTap: onAutomationApiTap,
          tooltip: _automationTooltip(l10n),
        ),
    ];
    if (notices.isEmpty) return const [];
    return [WpDockMenuHeader(l10n.dockMenuGroupNotices), ...notices];
  }

  List<WpDockMenuSpec> _supportMenuGroup(L10n l10n) {
    final mode = supportChipMode;
    if (mode == null) return const [];
    final thanks = mode == WpSupportChipMode.thanks;
    return [
      WpDockMenuAction(
        id: 'dock-menu-sponsor',
        icon: Icons.favorite_rounded,
        label: thanks ? l10n.supportChipThanksLabel : l10n.supportChipLabel,
        onTap: onSupportTap,
      ),
    ];
  }

  /// The GPU or CPU reading: information, not an action, so it is an info row
  /// under its own header.
  List<WpDockMenuSpec> _statusMenuGroup(L10n l10n) {
    final kind = backendKind;
    if (kind == null) return const [];
    return [
      WpDockMenuHeader(l10n.dockMenuGroupStatus),
      WpDockMenuInfo(
        id: 'dock-menu-backend',
        icon: kind == 'GPU' ? LucideIcons.zap : LucideIcons.cpu,
        label: backendUtilizationChipLabel(kind, backendUtilizationPercent),
      ),
    ];
  }
}

const double _statusDotSize = 10;

class _SttChip extends StatefulWidget {
  const _SttChip({
    required this.modeLabel,
    required this.state,
    this.startingSince,
    this.modelMissing = false,
    this.modelDownloadPercent,
    this.recordingPhase = RecordingPhase.idle,
    this.sliceProgress,
    this.doneMessage,
    this.donePasteFailed = false,
    this.doneUnconfirmed = false,
    this.localReady = false,
    this.tight = false,
    required this.l10n,
    this.onTap,
  });

  final String modeLabel;
  final SttServerState state;
  final DateTime? startingSince;
  final bool modelMissing;
  final int? modelDownloadPercent;
  final RecordingPhase recordingPhase;

  /// Slice progress of the running transcription (see [WpRecordingDock]).
  final SliceProgress? sliceProgress;

  /// Done label for the finished recording's real outcome (see `doneMessageFor`).
  final String? doneMessage;

  /// See [WpRecordingDock.donePasteFailed].
  final bool donePasteFailed;

  /// See [WpRecordingDock.doneUnconfirmed].
  final bool doneUnconfirmed;

  /// True only when dictation provably runs on this machine and is ready, so
  /// the chip may say "Lokal bereit" (computed by the caller).
  final bool localReady;

  /// A compact dock shows the shortest ready text ("Ready") rather than
  /// "Ready locally"; the accessible name keeps the full state either way.
  final bool tight;
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
        old.state != widget.state ||
        old.modelMissing != widget.modelMissing) {
      final (_, stateLabel, _) = _resolveDisplay();
      announce(
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
    // In an error state the tooltip names the cause and the one next step.
    // The recording phase outranks the engine state (see _resolveDisplay), so
    // the cause follows the same precedence.
    final tooltip = widget.recordingPhase == RecordingPhase.error
        ? '${widget.l10n.dockErrorCauseRecording} ${widget.l10n.dockErrorAction}'
        : widget.state == SttServerState.error
        ? '${widget.l10n.dockErrorCauseEngine} ${widget.l10n.dockErrorAction}'
        : widget.l10n.statusBarSttTooltip;
    final style = Theme.of(context).textTheme.bodyLarge!.copyWith(
      fontSize: WpTypeScaleTokens.bodyLg,
      color: _dock.textPrimary,
    );
    final doneWraps = widget.recordingPhase == RecordingPhase.done;

    final inkWell = InkWell(
      onTap: widget.onTap,
      focusNode: widget.onTap != null ? _focusNode : null,
      borderRadius: WpRadius.borderFull,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xs,
          vertical: WpSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              SizedBox(
                width: _statusDotSize,
                height: _statusDotSize,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: dotColor,
                ),
              )
            else
              WpStatusDot(tone: _toneFor(dotColor), size: _statusDotSize),
            const SizedBox(width: WpSpacing.xs),
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  stateLabel,
                  // A done message may take two lines at large text scales
                  // (UX-105); the line height is tight enough that two lines
                  // still fit the 76 px dock.
                  style: doneWraps ? style.copyWith(height: 1.05) : style,
                  maxLines: doneWraps ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
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

    // The accessible name carries the engine and the state together, since the
    // visible text shows the state alone. Button role only when tappable: an
    // inert chip must not promise an action. Live state changes are announced
    // separately in `didUpdateWidget`.
    return MergeSemantics(
      child: Semantics(
        key: const ValueKey('dock-status'),
        button: widget.onTap != null,
        label: '${widget.modeLabel} — $stateLabel',
        child: Tooltip(message: tooltip, child: body),
      ),
    );
  }

  /// Maps the dock's resolved dot colour onto the status-dot primitive's tone.
  /// Only the non-spinner states paint a dot, so only those colours appear.
  WpStatusTone _toneFor(Color dotColor) {
    if (dotColor == _dock.success) return WpStatusTone.success;
    if (dotColor == _dock.error) return WpStatusTone.error;
    if (dotColor == _dock.warning) return WpStatusTone.busy;
    return WpStatusTone.idle;
  }

  /// Resolves the display triple (dot color, label, spinner) by prioritising
  /// the recording lifecycle phase over the STT subprocess state.
  (Color, String, bool) _resolveDisplay() {
    // Active recording phases take priority over STT subprocess state.
    switch (widget.recordingPhase) {
      case RecordingPhase.recording:
        return (_dock.error, widget.l10n.statusBarRecording, true);
      case RecordingPhase.transcribing:
        final slice = widget.sliceProgress;
        return (
          // Recording family: this rung reads a `RecordingPhase`, so it is the
          // one accent in this chip that means "your recording is in flight".
          // The `SttServerState.starting` rung below looks the same today but
          // reads a different enum (subprocess boot, no recording running) and
          // therefore stays on the generic accent.
          _dock.recording,
          slice != null && slice.isSliced
              ? widget.l10n.transcribingSliceProgress(
                  slice.current,
                  slice.total,
                )
              : widget.l10n.statusBarTranscribing,
          true,
        );
      case RecordingPhase.refining:
        return (_dock.recording, widget.l10n.statusBarRefining, true);
      case RecordingPhase.done:
        return (
          widget.donePasteFailed
              ? _dock.warning
              : widget.doneUnconfirmed
              ? _dock.textMuted
              : _dock.success,
          widget.doneMessage ?? widget.l10n.overlayDoneReady,
          false,
        );
      case RecordingPhase.error:
        return (_dock.error, widget.l10n.sttStatusError, false);
      case RecordingPhase.idle:
        // Fall through to STT subprocess state below.
        break;
    }

    // Idle — a missing or downloading model outranks the subprocess state:
    // "Standby" would promise a dictation that cannot run yet.
    final downloadPercent = widget.modelDownloadPercent;
    if (downloadPercent != null) {
      return (
        _dock.action,
        widget.l10n.statusBarModelDownloading(downloadPercent),
        true,
      );
    }
    if (widget.modelMissing) {
      return (_dock.warning, widget.l10n.statusBarModelMissing, false);
    }

    // Idle — show STT subprocess state.
    return switch (widget.state) {
      // Stopped means the engine loads on demand; dictation still works, so
      // it reads as the same "Ready" state as a warm engine.
      SttServerState.stopped => (
        _dock.textMuted,
        widget.l10n.statusReady,
        false,
      ),
      SttServerState.starting => (_dock.action, _startingLabel(), true),
      // Green only when dictation provably runs locally ("Lokal bereit", spec
      // §2). Any other ready engine stays neutral. This is the dock's ready
      // state, the one allowlisted use of `success` besides the done phase
      // (`test/core/design/earned_green_test.dart`).
      // The state word is always "Ready"; the locality is a qualifier appended
      // to it, never a second term for the same state.
      SttServerState.ready => (
        widget.localReady ? _dock.success : _dock.textMuted,
        widget.localReady && !widget.tight
            ? '${widget.l10n.statusReady} · ${widget.l10n.statusLocal}'
            : widget.l10n.statusReady,
        false,
      ),
      SttServerState.error => (_dock.error, widget.l10n.sttStatusError, false),
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

/// The last-resort row: keeps its widths and scrolls sideways when the dock is
/// narrower than the minimal plan.
class _ScrollableDockRow extends StatefulWidget {
  const _ScrollableDockRow({required this.children});

  final List<Widget> children;

  @override
  State<_ScrollableDockRow> createState() => _ScrollableDockRowState();
}

class _ScrollableDockRowState extends State<_ScrollableDockRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
    ),
  );
}
