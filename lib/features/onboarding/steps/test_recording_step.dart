import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../features/settings/settings_widgets.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../widgets/wp_accent_button.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kTestRecordingStepFieldKey = Key('testRecordingStepSandboxField');
@visibleForTesting
const kTestRecordingStepSkipLinkKey = Key('testRecordingStepSkipLink');
@visibleForTesting
const kTestRecordingStepNextButtonKey = Key('testRecordingStepNextButton');

/// Onboarding step — guided, skippable test recording shown right before
/// [OnboardingStepId.ready].
///
/// Lets the newcomer run the real hotkey → speak → text pipeline once against
/// a local sandbox text field instead of the system clipboard/paste target,
/// so the very first "real" recording after onboarding isn't also their
/// first encounter with the mechanic. Wires
/// [RecordingOrchestrator.sandboxTranscriptSink] for the lifetime of this
/// step only; every other caller of the orchestrator keeps the real
/// clipboard/paste behaviour untouched.
class TestRecordingStep extends ConsumerStatefulWidget {
  const TestRecordingStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

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
    setState(() => _sandboxText = text);
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

    final isDone = _sandboxText != null;
    final isRecording =
        !isDone &&
        (phase == RecordingPhase.recording ||
            phase == RecordingPhase.transcribing);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
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
      children: [
        // Title
        Text(
          l10n.onboardingTestRecordingTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingTestRecordingSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
        ),
        const SizedBox(height: WpSpacing.xl),

        // Current hotkey — reuses the shared HotkeyDisplay chip renderer.
        Text(
          l10n.onboardingTestRecordingHotkeyLabel,
          style: TextStyle(fontSize: 12, color: textMuted),
        ),
        const SizedBox(height: WpSpacing.sm),
        HotkeyDisplay(
          hotkeyKey: settings.hotkeyKey,
          hotkeyModifiers: settings.hotkeyModifiers,
          hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
        ),
        const SizedBox(height: WpSpacing.xl),

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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.circleCheck, size: 16, color: success),
              const SizedBox(width: WpSpacing.xs),
              Text(
                l10n.onboardingTestRecordingDoneMessage,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: success,
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.onboardingTestRecordingReassurance,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: textMuted),
        ),

        // Skip link — hidden once the test already succeeded, since there is
        // nothing left to skip past.
        if (!isDone) ...[
          const SizedBox(height: WpSpacing.xxs),
          Semantics(
            button: true,
            label: l10n.onboardingTestRecordingSkip,
            child: Material(
              key: kTestRecordingStepSkipLinkKey,
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onNext,
                borderRadius: WpRadius.borderSm,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.sm,
                    vertical: WpSpacing.xs,
                  ),
                  child: Text(
                    l10n.onboardingTestRecordingSkip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      decoration: TextDecoration.underline,
                      decorationColor: accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: WpSpacing.lg),

        // Navigation — "Weiter" is always enabled regardless of recording
        // state: neither path is a required step ("kein Zwang, keine
        // Pflicht-Aufnahme" applies to both Skip and Weiter alike).
        Row(
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
              child: WpAccentButton(
                key: kTestRecordingStepNextButtonKey,
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: widget.onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sandbox field — Default / Recording / Done visual states.
// ---------------------------------------------------------------------------

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
      duration: WpMotion.fast,
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
                    style: TextStyle(fontSize: 13, color: textPrimary),
                  ),
                ),
              ],
            )
          : Text(
              isDone ? sandboxText! : l10n.onboardingTestRecordingPlaceholder,
              style: TextStyle(
                fontSize: 13,
                color: isDone ? textPrimary : textMuted,
              ),
            ),
    );
  }
}
