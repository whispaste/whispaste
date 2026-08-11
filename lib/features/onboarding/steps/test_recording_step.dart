import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../features/settings/settings_widgets.dart';
import 'mic_permission_chip.dart';
import 'onboarding_headings.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../widgets/wp_button.dart';
import '../onboarding_completion_gate.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kTestRecordingStepFieldKey = Key('testRecordingStepSandboxField');
@visibleForTesting
const kTestRecordingStepRecordButtonKey = Key('testRecordingStepRecordButton');
@visibleForTesting
const kTestRecordingStepMicBypassButtonKey = Key(
  'testRecordingStepMicBypassButton',
);

/// The single ambient note under the record button. Carries the reassurance
/// on its own when recordings are unlimited, and reassurance + auto-stop
/// duration in one sentence otherwise — hence one key for both variants.
@visibleForTesting
const kTestRecordingStepReassuranceHintKey = Key(
  'testRecordingStepReassuranceHint',
);

/// Guided, optional test recording content of the final onboarding page.
///
/// Lets the newcomer run the real hotkey → speak → text pipeline once against
/// a local sandbox text field instead of the system clipboard/paste target,
/// so the very first "real" recording after onboarding isn't also their
/// first encounter with the mechanic. Wires
/// [RecordingOrchestrator.sandboxTranscriptSink] for the lifetime of this
/// step only; every other caller of the orchestrator keeps the real
/// clipboard/paste behaviour untouched. Content only — navigation is owned
/// by the onboarding shell and never gated on recording success.
class TestRecordingStep extends ConsumerStatefulWidget {
  const TestRecordingStep({super.key});

  @override
  ConsumerState<TestRecordingStep> createState() => _TestRecordingStepState();
}

class _TestRecordingStepState extends ConsumerState<TestRecordingStep> {
  /// Cached notifier reference so [dispose] never touches `ref` (Riverpod
  /// forbids `ref` access after deactivation) — mirrors the defensive
  /// pattern already used by [OnboardingOverlay] for its paste notifier.
  RecordingOrchestrator? _orchestrator;

  String? _sandboxText;

  @override
  void initState() {
    super.initState();
    _orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    _orchestrator!.sandboxTranscriptSink = _onSandboxTranscript;
  }

  void _onSandboxTranscript(String text) {
    if (!mounted) return;
    if (text.trim().isNotEmpty) {
      // Non-empty transcript == proof that speech was actually recognised —
      // this is what the shell's completion gate waits for. Whitespace-only
      // results (silence, mic picked up nothing) don't count.
      ref
          .read(onboardingTestRecordingSucceededProvider.notifier)
          .markSucceeded();
    }
    setState(() => _sandboxText = text);
  }

  /// Starts/stops the guided test recording from the UI button.
  ///
  /// Deliberately routes through [RecordingOrchestrator.toggleRecording] —
  /// the exact method the systemwide hotkey handler calls — so the button is
  /// merely a second trigger for the identical pipeline, never a parallel
  /// recording path. The sandbox seam ([initState]/[dispose] wiring of
  /// [RecordingOrchestrator.sandboxTranscriptSink]) therefore covers
  /// button-driven starts for free: `_handleAfterTranscription` short-circuits
  /// into the sink regardless of what triggered the recording.
  void _onRecordPressed() {
    ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
  }

  void _onMicBypassPressed() {
    ref.read(onboardingMicBypassProvider.notifier).activate();
  }

  @override
  void dispose() {
    _orchestrator?.sandboxTranscriptSink = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final phase = ref.watch(recordingPhaseProvider);
    final testRecordingSucceeded = ref.watch(
      onboardingTestRecordingSucceededProvider,
    );
    final micBypassed = ref.watch(onboardingMicBypassProvider);

    final isDone = _sandboxText != null;
    final isRecording =
        !isDone &&
        (phase == RecordingPhase.recording ||
            phase == RecordingPhase.transcribing);

    const textSecondary = WpColors.textSecondary;
    const textMuted = WpColors.textMuted;
    // Recording family: this colour has exactly one job below — the live
    // border of the sandbox field while the test recording runs.
    const recordingAccent = WpColors.recordingAccent;
    const success = WpColors.success;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingPageHeading(
          title: l10n.onboardingTestRecordingTitle,
          subtitle: l10n.onboardingTestRecordingSubtitle,
        ),
        // `lg`, not the `kOnboardingHeaderGap` (`xxl`) every other page uses.
        // Two reasons, both specific to this page: it is the only one whose
        // heading is not the *page* header but the left column's own — the
        // right column starts with an [OnboardingSectionLabel] + `lg`, and
        // `xxl` here would offset the two columns against each other — and
        // tryAndGo is the one page that does not fill the viewport, with
        // ~32 px of slack left to spend in German (was ~6 px until the two
        // stacked ambient muted lines below merged into one).
        const SizedBox(height: WpSpacing.md),

        // Current hotkey and microphone status — the two preconditions of the
        // recording this page asks for, on one line. Label and key caps are
        // one statement, not two stacked blocks; Wrap lets the caps (and the
        // chip) drop below instead of overflowing when the column is narrow
        // or the translation is long.
        //
        // The microphone chip used to live on page 1, where it announced a
        // permission nothing on that page needed yet. Here it sits next to
        // the button that will use it, so a "action needed" state is visible
        // exactly when it becomes actionable. The permission itself is still
        // requested much earlier — on leaving page 1 (see `_goNext` in
        // onboarding_overlay.dart) — so the OS dialog never lands in the
        // middle of this page either.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.xs,
            children: [
              // `body` (13), not `small` (12): this caption, the key caps and
              // the microphone chip are one status line, and they carried
              // three different type sizes and three different heights
              // between them. The caps and the chip are both `body` over
              // `WpSpacing.xxs` (see [MicPermissionChip]'s library comment),
              // so the caption joins them rather than the other way round —
              // it stays muted, which is what makes it read as the label of
              // the line instead of a fourth item in it.
              Text(
                l10n.onboardingTestRecordingHotkeyLabel,
                style: const TextStyle(
                  fontSize: WpTypography.body,
                  color: textMuted,
                ),
              ),
              HotkeyDisplay(
                hotkeyKey: settings.hotkeyKey,
                hotkeyModifiers: settings.hotkeyModifiers,
                hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
              ),
              // Self-gates to nothing on Linux (no Settings deep-link there).
              const MicPermissionChip(),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.md),

        // Start/Stop button — the trigger for the test recording.
        // Deliberately a button and not the hotkey (which could still be in
        // conflict with other software); the hotkey keeps working in
        // parallel through the same orchestrator path. Disabled while a
        // finished recording is being transcribed — the sandbox field's
        // in-progress line explains the wait.
        //
        // A standard [WpButton], not the gradient [WpHeroButton] it used to
        // be. It was 382×55 px of accent gradient — three times the area of
        // the shell's actual primary CTA ("Los geht's", 140×49) and wearing
        // the identical gradient, so the page's *secondary* action outshouted
        // the one that ends the flow. Rank now reads off the components
        // themselves: gradient hero for the flow CTA, filled accent button
        // for the page's own action, ghost for the escape hatch below.
        // Left-aligned rather than stretched, because a button that spans the
        // full column reads as a banner and inherits none of that ladder.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: WpButton(
            key: kTestRecordingStepRecordButtonKey,
            label: phase == RecordingPhase.recording
                ? l10n.onboardingTestRecordingStopCta
                : l10n.onboardingTestRecordingStartCta,
            variant: WpButtonVariant.primary,
            onPressed: phase == RecordingPhase.transcribing
                ? null
                : _onRecordPressed,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

        // Sandbox field
        _SandboxField(
          key: kTestRecordingStepFieldKey,
          isDone: isDone,
          isRecording: isRecording,
          sandboxText: _sandboxText,
          isDark: isDark,
          recordingAccent: recordingAccent,
          l10n: l10n,
        ),

        if (isDone) ...[
          const SizedBox(height: WpSpacing.xs),
          Row(
            children: [
              const Icon(
                LucideIcons.circleCheck,
                size: WpIconSize.sm,
                color: success,
              ),
              const SizedBox(width: WpSpacing.xs),
              // Flexible so long translations wrap instead of overflowing
              // the row (surfaced by the walkthrough test's Ahem metrics).
              Flexible(
                child: Text(
                  l10n.onboardingTestRecordingDoneMessage,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w600,
                    color: success,
                  ),
                ),
              ),
            ],
          ),
        ],

        // ONE ambient note under the record button, not two. It used to be a
        // reassurance line plus a separate recording-duration row, and with
        // the completion-gate hint above them that stacked three muted lines
        // under a single control — where every other page of the flow and
        // every Settings section in the app carries at most one. Both were
        // unconditional ambient advice about the very same button, so they
        // are one sentence now (a dedicated string, never two runtime-glued
        // ones — that breaks in RTL and reads translated-by-machine). The
        // completion-gate hint stays its own line: it is conditional and
        // explains the *disabled CTA*, a different subject.
        //
        // The duration half sits on this page rather than beside the hotkey
        // settings because this is where the first recording happens:
        // "recordings stop by themselves after N seconds" is advice about
        // the button directly above. With no limit set (0 = unlimited) there
        // is nothing to warn about, so the line falls back to the plain
        // reassurance — and drops the leading info icon with it, since the
        // icon marks the duration information and the two variants never
        // appear together.
        //
        // `xs`, and directly under the field: this line is a caption of the
        // button/field pair above it, and it now says so by sitting closer to
        // them than to anything below. It used to be the middle of three
        // evenly spaced muted items (`sm`/`sm`/`xs`), which split the two
        // completion-gate items — the "record once to continue" line and the
        // button that bypasses exactly that requirement — around a sentence
        // that has nothing to do with either.
        const SizedBox(height: WpSpacing.xs),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
          child: Row(
            key: kTestRecordingStepReassuranceHintKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (settings.behavior.maxRecordDuration > 0) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.info,
                    size: WpIconSize.xs,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
              ],
              Expanded(
                child: Text(
                  settings.behavior.maxRecordDuration > 0
                      ? l10n.onboardingTestRecordingReassuranceWithDuration(
                          settings.behavior.maxRecordDuration,
                          l10n.settingsRecordingSafety,
                        )
                      : l10n.onboardingTestRecordingReassurance,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: WpTypography.small,
                    color: textMuted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        // The completion gate, as ONE block: the reason the shell's "Los
        // geht's" CTA is disabled, and the escape hatch that lifts it. Both
        // exist only while no recording has succeeded, and they disappear
        // together — so they are one conditional with one gap in front of it
        // rather than two conditionals that happened to render next to each
        // other.
        //
        // `lg` in front of the block (against the `xs` that binds the caption
        // above to the field): that step is the whole point of the
        // regrouping. It is the one gap on this column that separates two
        // subjects rather than spacing items within one, and at the old flat
        // `sm` the column read as five evenly stacked strips with no
        // discernible grouping — the single densest spot in the flow.
        //
        // The escape hatch itself stays deliberately restrained (plain ghost
        // button, never the accent gradient). It only bypasses the microphone
        // condition; a confirmed hotkey conflict still keeps the CTA disabled
        // (heads-up rendered by ReadyStep).
        if (!testRecordingSucceeded) ...[
          const SizedBox(height: WpSpacing.lg),
          if (!micBypassed) ...[
            // Named reason for the disabled CTA, so it never appears
            // unexplained. `textSecondary`, not `textMuted`: it is the one
            // line here that states a requirement rather than offering
            // ambient advice.
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: kSettingRowInset,
              ),
              child: Text(
                l10n.onboardingTestRecordingCompletionHint,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: WpTypography.small,
                  color: textSecondary,
                ),
              ),
            ),
            const SizedBox(height: WpSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WpButton(
                key: kTestRecordingStepMicBypassButtonKey,
                label: l10n.onboardingTestRecordingMicBypassCta,
                variant: WpButtonVariant.ghost,
                tone: WpButtonTone.neutral,
                onPressed: _onMicBypassPressed,
              ),
            ),
          ] else
            // Honest consequence note: no recording works until a microphone
            // does, and where to catch up later.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.info,
                    size: WpIconSize.xs,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.onboardingTestRecordingMicBypassHint,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      fontSize: WpTypography.small,
                      color: textMuted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sandbox field — Default / Recording / Done visual states.
// ---------------------------------------------------------------------------

/// Line cap for the recognised transcript — see the field's own comment for
/// the measured reason. Five lines keep page 5 at 471 of its 551-px viewport
/// even when the transcript is arbitrarily long.
const int _kSandboxMaxLines = 5;

class _SandboxField extends StatelessWidget {
  const _SandboxField({
    super.key,
    required this.isDone,
    required this.isRecording,
    required this.sandboxText,
    required this.isDark,
    required this.recordingAccent,
    required this.l10n,
  });

  final bool isDone;
  final bool isRecording;
  final String? sandboxText;
  final bool isDark;
  final Color recordingAccent;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    const textPrimary = WpColors.textPrimary;
    const textMuted = WpColors.textMuted;
    const error = WpColors.error;
    const borderDefault = WpColors.borderDefault;

    final borderColor = isRecording ? recordingAccent : borderDefault;

    return AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.fast),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: borderColor, width: isRecording ? 1.5 : 1),
      ),
      child: isRecording
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.onboardingTestRecordingInProgress,
                    style: const TextStyle(
                      fontSize: WpTypography.body,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              isDone ? sandboxText! : l10n.onboardingTestRecordingPlaceholder,
              // Bounded on purpose. This field proves that speech was
              // recognised; it is not a transcript viewer, and the page it
              // sits on cannot scroll (fixed 1100x720 window). Unbounded, a
              // 600-character dictation already pushed page 5 over its
              // 551-px viewport by 50 px, a 1200-character one by 290 px —
              // and recordings run up to `maxRecordDuration` seconds.
              maxLines: _kSandboxMaxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WpTypography.body,
                color: isDone ? textPrimary : textMuted,
              ),
            ),
    );
  }
}
