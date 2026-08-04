import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../features/settings/settings_widgets.dart';
import 'onboarding_headings.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../widgets/wp_accent_button.dart';
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

    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final success = isDark ? WpColorsDark.success : WpColorsLight.success;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingPageHeading(
          title: l10n.onboardingTestRecordingTitle,
          subtitle: l10n.onboardingTestRecordingSubtitle,
        ),
        const SizedBox(height: WpSpacing.lg),

        // Current hotkey — reuses the shared HotkeyDisplay chip renderer.
        // Label and key caps share one line (they are one statement, not two
        // stacked blocks); Wrap lets the caps drop below the label instead of
        // overflowing when the column is narrow or the translation is long.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.xs,
            children: [
              Text(
                l10n.onboardingTestRecordingHotkeyLabel,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: textMuted,
                ),
              ),
              HotkeyDisplay(
                hotkeyKey: settings.hotkeyKey,
                hotkeyModifiers: settings.hotkeyModifiers,
                hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
              ),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.md),

        // Start/Stop button — the primary trigger for the test recording.
        // Deliberately a button and not the hotkey (which could still be in
        // conflict with other software); the hotkey keeps working in
        // parallel through the same orchestrator path. Disabled while a
        // finished recording is being transcribed — the sandbox field's
        // in-progress line explains the wait.
        // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
        WpAccentButton(
          key: kTestRecordingStepRecordButtonKey,
          label: phase == RecordingPhase.recording
              ? l10n.onboardingTestRecordingStopCta
              : l10n.onboardingTestRecordingStartCta,
          gradient: accentGradient,
          verticalPadding: WpSpacing.sm,
          onPressed: phase == RecordingPhase.transcribing
              ? null
              : _onRecordPressed,
        ),
        const SizedBox(height: WpSpacing.md),

        // Sandbox field
        _SandboxField(
          key: kTestRecordingStepFieldKey,
          isDone: isDone,
          isRecording: isRecording,
          sandboxText: _sandboxText,
          isDark: isDark,
          accent: accent,
          l10n: l10n,
        ),

        if (isDone) ...[
          const SizedBox(height: WpSpacing.sm),
          Row(
            children: [
              Icon(LucideIcons.circleCheck, size: 16, color: success),
              const SizedBox(width: WpSpacing.xs),
              // Flexible so long translations wrap instead of overflowing
              // the row (surfaced by the walkthrough test's Ahem metrics).
              Flexible(
                child: Text(
                  l10n.onboardingTestRecordingDoneMessage,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w600,
                    color: success,
                  ),
                ),
              ),
            ],
          ),
        ],

        // Completion-gate explainer — the shell's "Los geht's" CTA stays
        // disabled until a test recording succeeded (or the escape hatch was
        // taken); this line names the reason so the disabled CTA never
        // appears unexplained.
        if (!testRecordingSucceeded && !micBypassed) ...[
          const SizedBox(height: WpSpacing.sm),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              l10n.onboardingTestRecordingCompletionHint,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: textSecondary,
              ),
            ),
          ),
        ],

        const SizedBox(height: WpSpacing.sm),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
          child: Text(
            l10n.onboardingTestRecordingReassurance,
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: WpTypography.small, color: textMuted),
          ),
        ),

        // Escape hatch "continue without a microphone" — deliberately
        // restrained (plain text button, never the accent gradient). Only
        // bypasses the microphone condition of the completion gate; a
        // confirmed hotkey conflict still keeps the CTA disabled (heads-up
        // rendered by ReadyStep). Hidden once a recording succeeded — at
        // that point it has nothing left to bypass.
        if (!testRecordingSucceeded) ...[
          const SizedBox(height: WpSpacing.xs),
          if (!micBypassed)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: kTestRecordingStepMicBypassButtonKey,
                onPressed: _onMicBypassPressed,
                child: Text(
                  l10n.onboardingTestRecordingMicBypassCta,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: WpTypography.body,
                  ),
                ),
              ),
            )
          else
            // Honest consequence note: no recording works until a microphone
            // does, and where to catch up later.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(LucideIcons.info, size: 14, color: textMuted),
                ),
                const SizedBox(width: WpSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.onboardingTestRecordingMicBypassHint,
                    textAlign: TextAlign.start,
                    style: TextStyle(
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
    required this.accent,
    required this.l10n,
  });

  final bool isDone;
  final bool isRecording;
  final String? sandboxText;
  final bool isDark;
  final Color accent;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final error = isDark ? WpColorsDark.error : WpColorsLight.error;
    final borderDefault = isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;

    final borderColor = isRecording ? accent : borderDefault;

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
                  decoration: BoxDecoration(
                    color: error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.onboardingTestRecordingInProgress,
                    style: TextStyle(
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
