// Onboarding v6, screen 5: the hotkey page as a split page. It only proves
// the dictation key works: hold it, let go, done. No mode choice here; hold
// versus press, double tap and single keys live in the settings, and the
// hands-free double tap is taught on the try-out page. The left column says
// what to do and, live, what the press did; the right panel shows the key
// large. Concept and decisions: internal-notes
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/generated/wp_tokens.g.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_keycap.dart';
import '../../../services/desktop_paste/desktop_paste_controller.dart';
import '../../../services/hotkey_conflicts.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/keyboard_up_monitor.dart';
import '../../../services/linux_desktop_shortcut.dart';
import '../../../services/onboarding_telemetry.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../settings/hotkey_flow.dart';
import '../../settings/sections/linux_desktop_shortcut_block.dart';
import '../../settings/widgets/wayland_hotkey_notice.dart';
import '../hotkey_practice.dart';
import '../onboarding_split_page.dart';
import 'onboarding_headings.dart'
    show OnboardingInitialFocus, onboardingCompactText;

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kTriggerStepChangeHotkeyKey = Key('trigger-step-change-hotkey-button');
@visibleForTesting
const kTriggerStepConflictWarnBoxKey = Key(
  'trigger-step-hotkey-conflict-warn-box',
);
@visibleForTesting
const kTriggerStepInlineRecorderKey = Key(
  'trigger-step-inline-hotkey-recorder',
);
@visibleForTesting
const kTriggerStepDoubleTapFallbackKey = Key(
  'onboarding-hotkey-double-tap-fallback',
);

/// Linux Wayland: the line announcing the desktop's shortcut dialog.
@visibleForTesting
const kTriggerStepDesktopConfirmHintKey = Key(
  'onboarding-hotkey-desktop-confirm',
);
@visibleForTesting
const kTriggerStepKeycapKey = Key('onboarding-hotkey-keycap');
@visibleForTesting
const kTriggerStepSecureInputKey = Key('onboarding-hotkey-secure-input');

/// Asks the desktop paste controller whether macOS reports secure event input
/// (a password or PIN field has focus; W-E1 API). Other platforms and any
/// probe failure count as not blocked. A provider so tests can answer
/// without a native host.
final hotkeySecureInputProbeProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    final controller = ref.read(desktopPasteControllerProvider);
    if (controller is! SecureInputProbe) return false;
    try {
      final state = await (controller as SecureInputProbe)
          .secureInputState()
          .timeout(const Duration(seconds: 2));
      return state == SecureInputState.active;
    } on Object {
      return false;
    }
  },
);

/// The dictation hotkey spelled for this platform, as the pages quote it
/// ("Ctrl+Shift+D", "⇧⌘D").
String onboardingTriggerShortcutText(L10n l10n, AppSettings settings) =>
    formatHotkeyShortcut(
      settings.hotkeyModifiers,
      settings.hotkeyKey,
      l10n: l10n,
      displayOverride: settings.hotkey.hotkeyKeyDisplay,
    );

/// Whether the onboarding pages word their instructions for hold mode: the
/// mode in effect on this platform (see [holdModeInEffect]), not the stored
/// switch alone. Without key-up the recording runs as toggle, so the pages
/// say so too.
bool onboardingHoldMode(WidgetRef ref) => holdModeInEffect(
  ref.read(settingsProvider).value ?? AppSettings.defaults,
  supportsKeyUp: ref.read(hotkeyServiceProvider.notifier).supportsKeyUp,
);

/// The hotkey page. [onNext] is null while a confirmed conflict holds the
/// page (E2 a); otherwise Next waits for one full start and stop, with a
/// quiet way past it, and is free at once where the page cannot observe the
/// key (Wayland without binding).
class TriggerStep extends ConsumerStatefulWidget {
  const TriggerStep({super.key, this.primaryKey, this.onNext, this.onBack});

  final Key? primaryKey;
  final VoidCallback? onNext;
  final VoidCallback? onBack;

  @override
  ConsumerState<TriggerStep> createState() => _TriggerStepState();
}

class _TriggerStepState extends ConsumerState<TriggerStep> {
  HotkeyPractice? _practice;

  /// The configuration [_practice] was built for. A change starts a new
  /// test, because the old proof was for another key or mode.
  String? _practiceSignature;
  Timer? _settle;

  /// "Jetzt loslassen" only once letting go would count (Codex pitfall:
  /// never ask for the release before it succeeds).
  Timer? _holdLongEnough;
  bool _heldLongEnough = false;

  /// The last press landed while a secure field had focus (macOS only).
  bool _secureInputBlocked = false;

  /// The test result last reported for the current key; a new key may
  /// report again.
  OnboardingHotkeyResult? _reported;

  @override
  void initState() {
    super.initState();
    // Linux Wayland, first run: the desktop's shortcut dialog was held back
    // until this page, which says it is coming (see the hint below).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(hotkeyServiceProvider.notifier).allowDesktopHotkeyBinding(),
      );
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _holdLongEnough?.cancel();
    super.dispose();
  }

  HotkeyPractice _practiceOf(
    AppSettings settings, {
    required bool hold,
    required bool singleKey,
  }) {
    final signature = [
      hold,
      settings.audioInput.holdOrTap,
      settings.audioInput.holdOrTapThresholdMs,
      settings.hotkey.hotkeyDoubleTap,
      singleKey,
      settings.hotkey.hotkeyDoubleTapKey,
      settings.hotkeyModifiers,
      settings.hotkeyKey,
    ].join('|');
    if (_practice == null || signature != _practiceSignature) {
      _settle?.cancel();
      _holdLongEnough?.cancel();
      _heldLongEnough = false;
      _reported = null;
      _practiceSignature = signature;
      _practice = HotkeyPractice(
        pushToTalk: hold,
        holdOrTap: settings.audioInput.holdOrTap,
        holdOrTapThresholdMs: settings.audioInput.holdOrTapThresholdMs,
        doubleTap: settings.hotkey.hotkeyDoubleTap,
        singleKey: singleKey,
      );
    }
    return _practice!;
  }

  void _onActivity(
    DictationHotkeyActivity? previous,
    DictationHotkeyActivity next,
  ) {
    final practice = _practice;
    if (practice == null || previous == null) return;
    final now = DateTime.now();
    if (next.otherKeys != previous.otherKeys) practice.otherKey(now);
    if (next.presses != previous.presses) {
      _settle?.cancel();
      practice.down(now);
      _heldLongEnough = false;
      _holdLongEnough?.cancel();
      _holdLongEnough = Timer(HotkeyPractice.minUsefulHold, () {
        if (mounted) setState(() => _heldLongEnough = true);
      });
      unawaited(_checkSecureInput());
    }
    if (previous.held && !next.held) {
      _holdLongEnough?.cancel();
      practice.up(now);
      _settle?.cancel();
      _settle = Timer(practice.doubleTapWindow, () {
        if (mounted && practice.settle(DateTime.now())) setState(() {});
      });
    }
    setState(() {});
  }

  Future<void> _checkSecureInput() async {
    final blocked = await ref.read(hotkeySecureInputProbeProvider)();
    if (mounted && blocked != _secureInputBlocked) {
      setState(() => _secureInputBlocked = blocked);
    }
  }

  /// "Taste ändern": the same recorder as in the settings. It takes a
  /// combination or one single key pressed alone.
  Future<void> _change() async {
    await recordDictationHotkey(
      context: context,
      ref: ref,
      settings: ref.read(settingsProvider).value ?? AppSettings.defaults,
    );
  }

  /// Saves a recorded combination. It replaces a single key: one trigger
  /// per action, as in the settings.
  Future<void> _saveCombination(WpHotkeyResult result) async {
    await ref.read(settingsProvider.notifier).updateSettings((s) {
      final next = s.copyWith(
        hotkeyKey: result.key,
        hotkeyKeyDisplay: result.displayKey,
        hotkeyModifiers: result.modifiers,
      );
      return next.copyWithSections(
        hotkey: next.hotkey.copyWith(hotkeyDoubleTapKey: ''),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DictationHotkeyActivity>(
      dictationHotkeyActivityProvider,
      _onActivity,
    );
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final status = ref.watch(hotkeyRegistrationStatusProvider);
    final doubleTapFallback = ref.watch(doubleTapFallbackActiveProvider);
    final desktopShortcutPending = ref.watch(desktopShortcutPendingProvider);
    // Non-null while the Wayland notice explains an unbound hotkey (XP-2-06).
    final waylandUnbound = ref.watch(waylandHotkeyNoticeReasonProvider) != null;
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;
    final lit = ref.watch(dictationHotkeyActivityProvider).held;

    final conflict = status == HotkeyRegistrationStatus.conflict;
    final observable = !conflict && !waylandUnbound && !desktopShortcutPending;
    final keyName = settings.hotkey.hotkeyDoubleTapKey;
    // The single key listens only where it can be observed; otherwise the
    // stored combination stands in, and the page tests that one.
    final singleKey = keyName.isNotEmpty && !doubleTapFallback;
    final hold = holdModeInEffect(settings, supportsKeyUp: supportsKeyUp);
    final practice = _practiceOf(settings, hold: hold, singleKey: singleKey);
    final shortcut = singleKey
        ? modifierOnlyLabel(l10n, keyName)
        : onboardingTriggerShortcutText(l10n, settings);
    final parts = onboardingHotkeyCaps(
      l10n,
      singleKey: singleKey ? keyName : '',
      key: settings.hotkeyKey,
      modifiers: settings.hotkeyModifiers,
      display: settings.hotkey.hotkeyKeyDisplay,
    );
    final (:prompt, :cue) = _gestureTexts(
      l10n,
      shortcut,
      hold: hold,
      doubleTap: singleKey && settings.hotkey.hotkeyDoubleTap,
    );
    _reportResult(practice, conflict: conflict);
    final canAdvance = widget.onNext != null;
    final proven = practice.proven || !observable;

    final compact = onboardingCompactText(context);
    final gap = compact ? WpSpacing.lg : WpSpacing.xl;

    return OnboardingSplitPage(
      panelAsset: 'assets/onboarding/hotkey-glacier.webp',
      panel: OnboardingKeyScene(
        parts: parts,
        lit: lit && observable,
        done: practice.proven && !practice.recording,
      ),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onBack != null)
            OnboardingBackLink(
              testId: 'onboarding-hotkey-back',
              label: l10n.onboardingBack,
              onPressed: widget.onBack!,
            ),
          OnboardingSplitHeading(
            l10n.onboardingTriggerTitle,
            testId: 'onboarding-hotkey-heading',
          ),
          const SizedBox(height: WpSpacing.sm),
          if (observable)
            Text(
              prompt,
              style: TextStyle(
                fontSize: WpTypography.body,
                height: 1.45,
                color: WpColors.textSecondary,
              ),
            ),
          if (doubleTapFallback) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(
              onboardingDoubleTapFallbackHint(l10n),
              key: kTriggerStepDoubleTapFallbackKey,
              style: TextStyle(
                fontSize: WpTypography.small,
                height: 1.4,
                color: WpColors.textMuted,
              ),
            ),
          ],
          if (!conflict) ...[
            const SizedBox(height: WpSpacing.xs),
            WpButton(
              key: kTriggerStepChangeHotkeyKey,
              testId: 'onboarding-hotkey-change',
              label: l10n.onboardingTriggerChooseOther,
              icon: LucideIcons.keyboard,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.accent,
              size: WpButtonSize.dense,
              onPressed: () => unawaited(_change()),
            ),
          ],
          // A confirmed conflict: the shared warning when the table names the
          // combination, otherwise the generic box; the recorder resolves it.
          if (conflict) ...[
            const SizedBox(height: WpSpacing.md),
            KeyedSubtree(
              key: kTriggerStepConflictWarnBoxKey,
              child: switch (findConflict(
                settings.hotkeyModifiers,
                settings.hotkeyKey,
              )) {
                final entry? => WpHotkeyConflictWarning(
                  conflict: entry,
                  l10n: l10n,
                ),
                null => _ConflictBox(
                  title: l10n.onboardingTriggerHotkeyConflictTitle,
                  body: l10n.onboardingTriggerHotkeyConflictBody,
                ),
              },
            ),
          ],
          if (conflict) ...[
            const SizedBox(height: WpSpacing.sm),
            // The keys go to the recorder at once, not to the heading.
            OnboardingInitialFocus(
              announcement:
                  '${l10n.onboardingTriggerTitle}. '
                  '${l10n.onboardingTriggerHotkeyConflictTitle}',
              child: WpHotkeyRecorderDialog(
                key: kTriggerStepInlineRecorderKey,
                initialKey: settings.hotkeyKey,
                initialDisplayKey: settings.hotkey.hotkeyKeyDisplay,
                initialModifiers: settings.hotkeyModifiers,
                onSubmit: _saveCombination,
              ),
            ),
          ],
          // Linux Wayland: registered, but the desktop has not bound it
          // (XP-2-06), or no portal and the desktop's own shortcut carries it
          // (XP-6-14). Either says what to do instead of a test.
          const WaylandHotkeyNotice(idPrefix: 'onboarding'),
          if (ref.watch(waylandHotkeyBindingProvider) ==
              WaylandHotkeyBinding.pending) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(
              l10n.onboardingTriggerDesktopConfirmHint,
              key: kTriggerStepDesktopConfirmHintKey,
              style: TextStyle(
                fontSize: WpTypography.small,
                height: 1.4,
                color: WpColors.textMuted,
              ),
            ),
          ],
          if (!conflict && desktopShortcutPending)
            LinuxDesktopShortcutBlock(settings: settings),
          if (observable) ...[
            SizedBox(height: gap),
            // A minimum height for the status, so the controls below do not
            // jump when a line appears or goes.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  liveRegion: true,
                  identifier: 'onboarding-hotkey-status',
                  child: _statusLine(
                    l10n,
                    practice.phase,
                    hold: hold,
                    cue: conflict ? null : cue,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.sm),
          SizedBox(
            width: kOnboardingCopyWidth,
            child: WpHeroButton(
              testId: 'onboarding-hotkey-next',
              key: widget.primaryKey,
              label: l10n.onboardingNext,
              onPressed: canAdvance && proven ? widget.onNext : null,
            ),
          ),
          if (canAdvance && !proven) ...[
            const SizedBox(height: WpSpacing.sm),
            WpButton(
              testId: 'onboarding-hotkey-skip',
              label: l10n.onboardingHotkeySkip,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              onPressed: widget.onNext,
            ),
          ],
        ],
      ),
    );
  }

  /// Hold is the lesson. Existing installs that chose press-to-toggle are
  /// told their way; a single key in that mode starts with a double tap.
  /// [cue] is the same gesture as one short imperative for the status slot,
  /// so the page says "press now" without reading the paragraph.
  ({String prompt, String cue}) _gestureTexts(
    L10n l10n,
    String shortcut, {
    required bool hold,
    required bool doubleTap,
  }) {
    if (hold) {
      return (
        prompt: l10n.onboardingTriggerDemoPromptHold(shortcut),
        cue: l10n.onboardingHotkeyCueHold(shortcut),
      );
    }
    if (doubleTap) {
      return (
        prompt: l10n.onboardingTriggerDemoPromptDoubleTap(shortcut),
        cue: l10n.onboardingHotkeyCueDoubleTap(shortcut),
      );
    }
    return (
      prompt: l10n.onboardingTriggerDemoPrompt(shortcut),
      cue: l10n.onboardingHotkeyCuePress(shortcut),
    );
  }

  /// `hotkey_result`, once per outcome and key: a confirmed conflict, the
  /// test passed, or a try that was too short to count.
  void _reportResult(HotkeyPractice practice, {required bool conflict}) {
    final result = conflict
        ? OnboardingHotkeyResult.conflict
        : practice.proven
        ? OnboardingHotkeyResult.recognized
        : practice.phase == HotkeyPracticePhase.tooShort
        ? OnboardingHotkeyResult.notRecognized
        : null;
    if (result == null || result == _reported) return;
    _reported = result;
    ref.read(onboardingTelemetryProvider).hotkeyResult(result);
  }

  Widget _statusLine(
    L10n l10n,
    HotkeyPracticePhase phase, {
    required bool hold,
    String? cue,
  }) {
    if (_secureInputBlocked) {
      return _IconLine(
        key: kTriggerStepSecureInputKey,
        icon: LucideIcons.triangleAlert,
        color: WpColors.warning,
        text: l10n.onboardingTriggerSecureInput,
      );
    }
    final text = switch (phase) {
      HotkeyPracticePhase.ready => null,
      HotkeyPracticePhase.held =>
        hold && _heldLongEnough
            ? l10n.onboardingHotkeyStatusRelease
            : l10n.onboardingHotkeyStatusHeld,
      HotkeyPracticePhase.toggledOn => l10n.onboardingHotkeyStatusToggledOn,
      HotkeyPracticePhase.handsFree => l10n.onboardingHotkeyStatusHandsFree,
      HotkeyPracticePhase.tooShort => l10n.onboardingTriggerHoldHint,
      HotkeyPracticePhase.done => l10n.onboardingHotkeyTestRecognized,
      HotkeyPracticePhase.doneHandsFree =>
        l10n.onboardingHotkeyStatusDoneHandsFree,
    };
    if (text == null) {
      return cue == null ? const SizedBox.shrink() : _ReadyCue(text: cue);
    }
    final done =
        phase == HotkeyPracticePhase.done ||
        phase == HotkeyPracticePhase.doneHandsFree;
    return _IconLine(
      icon: done ? LucideIcons.circleCheck : LucideIcons.keyboard,
      color: done ? WpColors.highlight : WpColors.textMuted,
      text: text,
      strong: true,
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.strong = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: WpIconSize.sm, color: color),
        const SizedBox(width: WpSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: WpTypography.body,
              height: 1.4,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
              color: WpColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The call to act while the page waits for the key (maintainer 2026-10-30:
/// "press now" must be clear without reading). An action-coloured pill with
/// the gesture; it breathes three times when it appears (again after the
/// hotkey was changed) and then rests, like the contact launcher.
class _ReadyCue extends StatefulWidget {
  const _ReadyCue({required this.text});

  final String text;

  @override
  State<_ReadyCue> createState() => _ReadyCueState();
}

class _ReadyCueState extends State<_ReadyCue>
    with SingleTickerProviderStateMixin {
  // Half cycles: three breaths, then the pill rests.
  static const int _halfCycles = 6;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _pulse.repeat(reverse: true, count: _halfCycles);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return DecoratedBox(
          // Flat pulse: the accent edge breathes in opacity, no glow (§7).
          // Reduced motion leaves the controller at 0, so the edge stays
          // fully opaque.
          decoration: BoxDecoration(
            color: WpColors.accentChipFill,
            borderRadius: WpRadius.borderFull,
            border: Border.all(
              color: WpColors.accent.withValues(alpha: 1 - 0.5 * t),
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.keyboard,
              size: WpIconSize.md,
              color: WpColors.accent,
            ),
            const SizedBox(width: WpSpacing.sm),
            Flexible(
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: WpTypography.body,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: WpColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red box for a confirmed conflict the table does not name.
class _ConflictBox extends StatelessWidget {
  const _ConflictBox({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WpColors.errorActiveFill,
        borderRadius: WpRadius.borderSm,
        border: Border.all(color: WpColors.errorBorder30),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: WpIconSize.md,
            color: WpColors.error,
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w700,
                    color: WpColors.error,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxs),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel: the key large on the painting, in one row, lit cyan while it
/// is down, an amber check once start and stop were seen, and a quiet label
/// that the microphone stays off. Decoration only: nothing here is
/// clickable.
/// The key caps of the dictation hotkey: the single key when one listens,
/// else the combination.
List<({String cap, String? side})> onboardingHotkeyCaps(
  L10n l10n, {
  required String singleKey,
  required String key,
  required String modifiers,
  required String display,
}) => singleKey.isNotEmpty
    ? [singleKeyCap(l10n, singleKey)]
    : [
        for (final part in hotkeyDisplayParts(
          modifiers,
          key,
          l10n: l10n,
          displayOverride: display,
        ))
          (cap: part, side: null),
      ];

/// The hotkey as large key caps over the panel: they light while the key is
/// held, and a check appears once start and stop were seen. The hotkey page
/// and the try-out page share it.
class OnboardingKeyScene extends StatelessWidget {
  const OnboardingKeyScene({
    super.key,
    required this.parts,
    required this.lit,
    required this.done,
  });

  final List<({String cap, String? side})> parts;
  final bool lit;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const stage = wpStagePalette;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: WpSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                key: kTriggerStepKeycapKey,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: WpSpacing.sm,
                runSpacing: WpSpacing.sm,
                children: [
                  for (final part in parts)
                    WpKeycap.large(
                      label: part.cap,
                      sublabel: part.side,
                      lit: lit,
                    ),
                ],
              ),
            ),
            const SizedBox(height: WpSpacing.lg),
            SizedBox(
              height: WpIconSize.lg,
              child: AnimatedSwitcher(
                duration: WpMotion.durationFor(context, WpMotion.normal),
                child: done
                    ? Icon(
                        LucideIcons.circleCheck,
                        key: const ValueKey('done'),
                        size: WpIconSize.lg,
                        color: WpColors.highlight,
                      )
                    : const SizedBox.shrink(key: ValueKey('idle')),
              ),
            ),
            const SizedBox(height: WpSpacing.lg),
            DecoratedBox(
              decoration: BoxDecoration(
                color: WpColors.floatingSurface,
                borderRadius: WpRadius.borderFull,
                border: Border.all(color: stage.borderSubtle),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.md,
                  vertical: WpSpacing.xxs,
                ),
                child: Text(
                  l10n.onboardingHotkeySceneIdle,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: stage.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A large flat key cap of the scene: navy with a frost rim, cyan rim and
/// glow while the key is down. Sized by its label, never stretched.
