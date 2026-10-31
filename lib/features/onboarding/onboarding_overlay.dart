import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart' show appVersion;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/config/build_config.dart';
import '../../core/config/settings_provider.dart';
import '../../core/onboarding/onboarding_revision.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_reporter.dart';
import '../../services/hotkey_self_heal.dart';
import '../../services/hotkey_service.dart';
import '../../services/paste/paste_capability_notifier.dart';
import '../../services/permissions/mic_permission_notifier.dart';
import '../../services/model_hardware_telemetry.dart';
import '../../services/onboarding_telemetry.dart';
import '../../services/system_user_name.dart' show systemFirstNameProvider;
import '../../services/telemetry_model_buckets.dart' show telemetryModelId;
import '../../services/telemetry_service.dart';
import '../settings/widgets/settings_scroll_affordance.dart';
import 'widgets/onboarding_contact_launcher.dart';
import '../../widgets/dialog.dart';
import '../../widgets/hotkey_recorder.dart' show WpHotkeyRecorderDialog;
import '../../widgets/wp_button.dart';
import 'onboarding_download_footer.dart';
import '../../widgets/wp_hero_button.dart';
import '../../widgets/wp_toast_dock.dart';
import 'onboarding_flow_migration.dart';
import 'onboarding_mic_gate.dart';
import 'onboarding_download_provider.dart';
import 'onboarding_download_status.dart' show OnboardingDownloadPhase;
import 'onboarding_telemetry_signals.dart';
import 'steps/about_step.dart';
import 'steps/permissions_step.dart';
import 'steps/access_mic_step.dart';
import 'steps/onboarding_motion_clip.dart';
import 'steps/onboarding_headings.dart';
import 'steps/onboarding_page_fill.dart';
import 'steps/welcome_step.dart';
import 'onboarding_speech_consent.dart';
import 'steps/model_step.dart';
import 'steps/trigger_step.dart';
import 'steps/test_recording_step.dart';
import 'steps/privacy_step.dart';
import 'onboarding_completion_gate.dart';
import 'stt_model_readiness.dart';

/// Widget keys exposed for testing — the shell-owned navigation actions.
@visibleForTesting
const kOnboardingNavRowKey = Key('onboarding-nav-row');
@visibleForTesting
const kOnboardingBackButtonKey = Key('onboarding-nav-back-button');
@visibleForTesting
const kOnboardingNextButtonKey = Key('onboarding-nav-next-button');
const kOnboardingStepCounterKey = Key('onboarding-step-counter');

/// The top bar's X. Closes the window during the first run and leaves the
/// review in a reopened one — one control, two meanings, so tests address it
/// by key rather than by icon.
@visibleForTesting
const kOnboardingReviewExitButtonKey = Key('onboarding-top-bar-close-button');

/// The revision run's named exit. Deliberately **not** in the navigation row:
/// it is not a third navigation action and not a per-step "skip" — it leaves
/// the whole flow, exactly like reaching the last step does
/// (`internal-notes`). Living in the top bar is what
/// makes "every page has exactly two navigation actions" stay true by
/// construction rather than by a conditional.
@visibleForTesting
const kOnboardingRevisionExitButtonKey = Key('onboarding-revision-exit-button');

/// The secondary text link on the first-dictation page: moves on without a
/// test dictation ("Später ausprobieren").
const kOnboardingTryLaterButtonKey = Key('onboarding-try-out-later-button');

/// Height of the onboarding top bar's control row, and the hit target of the
/// close button that sits in it on the platforms that render one.
///
/// Pinned rather than derived so the bar keeps the exact same height on macOS,
/// where the button is omitted — everything below it must not shift.
///
/// **Deliberate exception to the 48-px hit-target floor** (`DESIGN.md`, "All
/// interactive elements meet the 48px minimum touch target"): the close X is
/// 32×32, the same reasoning that sanctions the status-bar theme toggle
/// (36×32, `lib/app.dart`) and the trigger-list remove button (28×28,
/// `replacements_page.dart`) — a single, rarely-used control in a one-off
/// flow, not a row action hit repeatedly, which is what the floor is for.
/// `WpButton`'s `dense` size (32 px, hit target equal to its visual box) is
/// the established precedent for this shape. The height is also load-bearing
/// in both directions: it *is* the top strip, and growing it pushes every
/// page's header down the fixed 1100×720 window (the 48 → 32 rebalance
/// documented in [_kOnboardingBottomGap] is exactly that trade, paid for
/// once already).
///
/// Note for whoever touches the constraints below: this passes
/// `test/widgets/wp_row_action_squeezed_icon_button_guard_test.dart` only
/// because the guard matches digit literals in `BoxConstraints`, and the
/// button passes this named constant instead. Inlining `32` there would trip
/// the guard — the fix is then to keep the constant, not to add this file to
/// the guard's allowlist, which would blind it to every future `IconButton`
/// here.
const double _kOnboardingTopBarHeight = 52;

/// Distance of the contact launcher from the window corner.
const double _kOnboardingContactInset = WpSpacing.xl;

/// Room the launcher's corner takes from the bottom bar: its 56-px circle,
/// the corner inset and a gap.
const double _kOnboardingContactReserve =
    56 + _kOnboardingContactInset + WpSpacing.md;

/// Hit box of the floating exit X, independent of the top bar's height.
const double _kOnboardingExitBoxSize = 32;

/// Distance from the window edges to the exit *glyph* — the visible X — on
/// both axes.
///
/// One number for top and side on purpose: inside the old top strip the
/// glyph sat 6 px from the top edge (centred in the 32-px band) but 18 px
/// from the side (the strip's 12-px padding plus the button's own 6), which
/// on the frameless Windows/Linux window read as the X hugging the top edge
/// while floating off the corner. The exit controls float in their own
/// corner layer now (see `_buildExitControls`) precisely so this inset can
/// be symmetric without growing the strip or shifting the page below it.
const double _kOnboardingExitGlyphInset = WpSpacing.sm;

/// Where the exit button's *box* is positioned so its glyph lands on
/// [_kOnboardingExitGlyphInset]: the 32-px hit box extends
/// `(32 − WpIconSize.md) / 2 = 6 px` beyond the glyph on every side.
const double _kOnboardingExitBoxInset =
    _kOnboardingExitGlyphInset - (_kOnboardingExitBoxSize - WpIconSize.md) / 2;

/// Air under the step counter, i.e. between the last thing on screen and the
/// window's bottom edge — the counterpart to the empty top bar above the
/// header.
///
/// Both numbers were measured at the fixed 1100×720 window and were 68 px
/// above the header (a 48-px top-bar strip plus the scroll view's 20-px top
/// padding) against 16 px below the counter: the page looked pinned to the
/// bottom of a window with a dead band at the top. The fix splits the
/// difference from both ends — the top bar dropped its own `xs` padding
/// (48 → 32, the strip is now exactly the close button's hit target) and this
/// gap grew from `md` to `xxl` — which lands on 52 px above and 32 px below.
///
/// The two moves were deliberately equal and opposite (−16 / +16), which is
/// what kept the scroll viewport at exactly 551 px through that rebalance.
///
/// That 551 px no longer holds, and deliberately so. The footer stack was the
/// binding constraint behind the flow's one P0 finding: on Try & Go at text
/// scale 1.3 the microphone-bypass button — the only way past the page without
/// a working microphone — sat below the fold, and the footer is what pushed it
/// there. It cost ~85 px at scale 1.0 and *grew* with the text scale it was
/// squeezing the page at, taking the viewport from 551 to 539 px exactly when
/// the page needed it most. Two changes answer that: the step counter moved
/// onto the dots' own line (it restates them, so it never needed a line of its
/// own), and this gap came down `xxl` → `lg`. Together they return ~35 px of
/// viewport at scale 1.0 and ~39 px at 1.3, to every page.
///
/// So the number to re-measure against is no longer 551: the height table in
/// `onboarding_overlay_test.dart` is stale by construction until it is
/// re-measured wholesale (that table's own instruction, and the reason it is
/// flagged rather than patched row by row).
///
/// Still not 1 : 1 with the top gap: the top gap is empty, while these 20 px
/// sit under a footer stack that already carries visual weight — a reading
/// start wants more air above it than trailing meta-text wants below it.
const double _kOnboardingBottomGap = WpSpacing.lg;

/// Whether the round feedback button sits in the corner. On the try-out page
/// it is hidden: it would cover the practice field and the dictation's result
/// (maintainer's live run, 2026-10-30). Elsewhere the intro rule applies.
bool contactLauncherShown({
  required bool fullBleed,
  required bool halfway,
  required OnboardingStepId step,
}) => (!fullBleed || halfway) && step != OnboardingStepId.tryOut;

/// Identifier for each page of the first-run onboarding flow (Onboarding v6,
/// ticket V01).
///
/// Seven pages on every desktop platform. The platform differences live
/// inside the page content, never in the sequence.
enum OnboardingStepId {
  /// 1 — Start: language, the privacy sentence and the short product demo.
  /// Carries no microphone affordance: the microphone is asked for on the
  /// Mic page only, never on appear or on leaving this page.
  welcome,

  /// 2 — About you: first name, roles and how the user found WhisPaste. Every
  /// answer is optional; the name is used in later headings.
  about,

  /// 3 — Access: the text-insertion permission of this platform (macOS
  /// Accessibility, Windows default on, Linux uinput or portal).
  access,

  /// 4 — Mic: one statement, a live level card with the device picker, and
  /// "Weiter" once speech has been heard (ticket V04).
  mic,

  /// 5 — Hotkey: which key starts a recording, and whether it is held or
  /// pressed to toggle.
  hotkey,

  /// 6 — Try: a first guided dictation through the real pipeline.
  tryOut,

  /// 7 — Privacy & Start: the usage-statistics and crash-report switches,
  /// committed on completion. Its main action starts WhisPaste and closes the
  /// onboarding. Without a model it reads "Modell laden" instead, and only a
  /// confirmed hotkey conflict disables it.
  privacy,

  /// Model setup. Not a page of the sequence and without a phase of its own:
  /// opened from Start ("Anderes Modell") or from the last page ("Modell
  /// laden") and left back to the page it came from (see
  /// [buildOnboardingStepIds]).
  speech,
}

/// The telemetry screen of a page; `null` for the model view, which is no
/// page.
@visibleForTesting
OnboardingScreen? onboardingScreenOf(OnboardingStepId step) => switch (step) {
  OnboardingStepId.welcome => OnboardingScreen.welcome,
  OnboardingStepId.about => OnboardingScreen.about,
  OnboardingStepId.access => OnboardingScreen.access,
  OnboardingStepId.mic => OnboardingScreen.mic,
  OnboardingStepId.hotkey => OnboardingScreen.hotkey,
  OnboardingStepId.tryOut => OnboardingScreen.tryOut,
  OnboardingStepId.privacy => OnboardingScreen.privacy,
  OnboardingStepId.speech => null,
};

/// The page a review opens on (Onboarding v6, V08, E1 a). Null means the
/// first page, which is what the Settings entry gets. The one-time notice
/// opens the review on the microphone page. Session state, never persisted,
/// like [onboardingManuallyOpenProvider].
class OnboardingReviewStepNotifier extends Notifier<OnboardingStepId?> {
  @override
  OnboardingStepId? build() => null;

  void set(OnboardingStepId? step) => state = step;
}

final onboardingReviewStepProvider =
    NotifierProvider<OnboardingReviewStepNotifier, OnboardingStepId?>(
      OnboardingReviewStepNotifier.new,
    );

/// Opens a review, never a first run, on [at] (default: the first page).
/// Every entry point goes through here, so a stale page from an earlier
/// review cannot leak into the next one.
void openOnboardingReview(WidgetRef ref, {OnboardingStepId? at}) {
  if (at == null) {
    // From the start it is a new first screen: intro animation and sound
    // run again.
    resetWelcomeIntro();
  }
  ref.read(onboardingReviewStepProvider.notifier).set(at);
  ref.read(onboardingManuallyOpenProvider.notifier).open();
}

/// Subtitle of the Access page's paste card for [platform]. macOS asks for the
/// Accessibility permission, Windows asks for nothing, and Linux has no system
/// dialog at all, so Linux gets its own text instead of the macOS one.
String onboardingPasteSubtitleFor(L10n l10n, TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.windows => l10n.onboardingPasteSubtitleWin,
      TargetPlatform.linux => l10n.onboardingPasteSubtitleLinux,
      _ => l10n.onboardingPasteSubtitle,
    };

/// Returns the ordered onboarding page IDs (flow version 5, Onboarding v6).
///
/// The same seven entries on every platform and build variant. The phase bar
/// shows exactly these. [OnboardingStepId.speech] is not part of the sequence.
@visibleForTesting
List<OnboardingStepId> buildOnboardingStepIds() => const [
  OnboardingStepId.welcome,
  OnboardingStepId.about,
  OnboardingStepId.access,
  OnboardingStepId.mic,
  OnboardingStepId.hotkey,
  OnboardingStepId.tryOut,
  OnboardingStepId.privacy,
];

/// Full-window, edge-to-edge onboarding flow.
///
/// Sits on top of the main app shell in a [Stack] and covers it with the same
/// ambient frame gradient the rest of the app uses — no blur, no dimmed
/// scrim, no floating card.
/// Six pages and the closing page on every platform, with animated
/// transitions, a shell-owned navigation (one centred primary action, Back
/// and the secondary ways as text links), stepper dots, and a step counter. The whole surface doubles as a window drag area (the
/// title bar is hidden during onboarding). On completion persists
/// [AppSettings.onboarding]`.onboardingCompleted` = true.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({
    super.key,
    this.manualReview = false,
    this.revisionRun = false,
  });

  /// Whether this is a review the user reopened from Settings rather than the
  /// first run.
  ///
  /// A review shows the same pages prefilled with the same live settings
  /// — the difference is entirely in what it is allowed to write and how it
  /// ends. It never touches the persisted resume position (that belongs to
  /// the first run and only to it), never re-writes `onboardingCompleted`
  /// (already `true`, and writing it is precisely the accident this mode has
  /// to be incapable of), always starts at step 1, and always offers a
  /// visible way out — the first run deliberately has none, because there
  /// closing the window means quitting the app.
  final bool manualReview;

  /// Whether this is an onboarding revision run
  /// (`internal-notes`) rather than the first run
  /// or a manually reopened review.
  ///
  /// Shares most of a review's shape — same pages prefilled from live
  /// settings, always starts at step 1, never re-writes `onboardingCompleted`
  /// — but differs in what its ending does: completion and the visible exit
  /// (`internal-notes`, not built by this flag) both
  /// stamp `onboardingContentVersion` via [OnboardingRevisionRunNotifier.
  /// complete], because a revision run is offered at most once per version,
  /// while a review — already caught up by definition — never touches that
  /// field. Mutually exclusive with [manualReview] by construction: the two
  /// session flags that drive them are only ever set one at a time.
  final bool revisionRun;

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  static final _log = AppLogger('Onboarding');

  /// The reading measure of every settings-shaped page — one width for the
  /// heading *and* the body underneath it.
  ///
  /// These pages ran two widths at once: the page heading capped its subtitle
  /// at 560 px while the body ran the full 720, so the right edge jumped
  /// 148 px between a page's own head and its own content. Appearance showed
  /// the same break inside its body — three 200-px tiles with `lg` between
  /// them come to exactly 640, sitting under a 720-px autostart row.
  ///
  /// 640 is the width both of those already wanted: it is the tile row's own
  /// measure, so Appearance stops breaking against itself, and it is close
  /// enough to the 560 the headings were tuned for that no subtitle gains a
  /// line. Head and body now end on the same x-edge, and there is one number
  /// to reason about instead of two.
  ///
  /// Deliberately applied here rather than to the 720-px content width: Try & Go
  /// derives its two column widths from the 720-px frame ((720 − 32) × 6/9 and
  /// × 3/9), and narrowing the frame would re-wrap the left column and undo
  /// the height relief that got its escape hatch back above the fold. Try & Go
  /// is not a reading-measure page — it is two columns — so the cap does not
  /// apply to it by construction rather than by exception.
  static const double _readingMeasure = 640;

  /// Page 1 runs a wider frame than the settings-shaped pages behind it — its
  /// composition is a text column *beside* a large media panel, and at 720
  /// the two halves squeeze each other. The width itself is owned by
  /// [kOnboardingWelcomeFrameWidth], because the recorded clip dimensions are
  /// derived from it.
  double _frameWidthFor(OnboardingStepId id) => switch (id) {
    OnboardingStepId.welcome => kOnboardingWelcomeFrameWidth,
    _ => _readingMeasure,
  };

  int _currentStep = 0;
  int _previousStep = 0;

  /// The model page, opened from the closing page via "Modell laden". It is
  /// a detour, not a page of the sequence: the displayed page is the model
  /// page while it is open, see [_openModelDetour] for what is stored.
  bool _modelDetourOpen = false;

  /// Whether the open model page was reached from the start page. Only then
  /// it says the choice can be changed later.
  bool _modelDetourFromWelcome = false;

  /// Whether the other-model page was opened from the start page at least
  /// once. Its selection is then already saved, so the consent downloads that
  /// selection instead of the recommendation.
  bool _welcomeModelVisited = false;

  /// Guards the start page's consent against a second press while the
  /// disk-space warning is open.
  bool _welcomeConsentPending = false;

  /// Guards [_hydrateStepFromSettings] so it only ever jumps the step once —
  /// further settings changes (e.g. the user picking a microphone) must not
  /// re-trigger a step jump.
  bool _stepHydrated = false;

  /// Guards the one-time entry telemetry for the step the overlay first
  /// shows. Separate from [_stepHydrated]: that flag gates the step *jump*,
  /// this one only dedupes the 'step' event for whichever step ends up
  /// visible first. Needed because [_hydrateStepFromSettings] used to skip
  /// tracking entirely whenever the saved position already matched
  /// [_currentStep] (the common case — settings resolve synchronously and a
  /// fresh install starts at step 0 either way) — silently dropping the
  /// onboarding-entry event for most first-time sessions and undercounting
  /// the first step relative to every later one in the funnel (Matomo
  /// product analysis, 2026-09-04).
  bool _entryTracked = false;

  /// Cached notifier references so [dispose] can stop polling without
  /// touching `ref` — Riverpod forbids `ref` access after deactivation.
  /// The overlay owns the provider scope, so sudden window-close (X tapped,
  /// app quit) tears down the widget tree without giving individual steps a
  /// chance to run their own dispose; defending here guarantees no zombie
  /// polling timer survives the overlay — neither the Auto-Paste capability
  /// poller nor the microphone permission poller.
  PasteCapabilityNotifier? _cachedPasteNotifier;
  MicPermissionNotifier? _cachedMicNotifier;

  @override
  void initState() {
    super.initState();
    if (widget.manualReview) {
      // A review starts at the beginning, every time. The persisted resume
      // position belongs to an interrupted *first* run and means nothing
      // here — reading it would drop a returning user into the middle of the
      // flow for no reason they could reconstruct, and the write-back on the
      // next navigation would corrupt a genuinely interrupted first run's
      // position for good.
      _stepHydrated = true;
      // The page a review opens on: the first page, unless the caller asked
      // for another one (the one-time notice opens on the microphone page).
      // Still no write-back: a review never persists its position.
      final steps = _onboardingSteps();
      final start = ref.read(onboardingReviewStepProvider);
      final index = start == null ? 0 : steps.indexOf(start);
      _currentStep = index < 0 ? 0 : index;
      _previousStep = _currentStep;
      _trackShown(steps[_currentStep]);
      return;
    }
    if (widget.revisionRun) {
      // Same reasoning as a review's early return above — a revision run
      // always begins at step one — plus one more: by the time this mounts,
      // OnboardingRevisionRunNotifier.start() has already reset the shared
      // position field to 0, so reading it here would be redundant even if
      // it weren't skipped.
      _stepHydrated = true;
      _trackShown(_onboardingSteps().first);
      return;
    }
    // Resume where the user left off — most relevantly after a required app
    // restart mid-onboarding (e.g. granting the Auto-Paste permission).
    // Without this, onboardingCompleted is still false post-restart and the
    // overlay would otherwise always rebuild at step 0, forcing the user
    // back through every prior step. `fireImmediately` covers the common
    // case where settings already finished loading by the time this overlay
    // mounts; the listener itself covers the case where they're still
    // in-flight (settingsProvider starts as AsyncLoading with no value yet).
    _beginPrivacyHold();
    _listenForSignals();
    ref.listenManual(
      settingsProvider,
      (_, next) => _hydrateStepFromSettings(next.value),
      fireImmediately: true,
    );
    ref.listenManual(
      onboardingModelStepRequestProvider,
      (_, _) => _openModelDetour(),
    );
    if (!_stepHydrated) {
      // Settings weren't loaded synchronously — track the tentative first
      // step; _hydrateStepFromSettings corrects both the step and this
      // telemetry once settings resolve.
      _entryTracked = true;
      _trackShown(_onboardingSteps().first);
    }
  }

  void _hydrateStepFromSettings(AppSettings? loaded) {
    if (_stepHydrated || loaded == null) return;
    _stepHydrated = true;
    final steps = _onboardingSteps();
    final onboarding = loaded.onboarding;
    final int saved;
    // A stored position one past the last page means the model page was open
    // when the app quit (see [_openModelDetour]). Only in the current
    // sequence: a legacy position of the same number (v4 Privacy is 7) is
    // translated below.
    final resumeModelDetour =
        onboarding.onboardingFlowVersion >= kOnboardingFlowVersion &&
        onboarding.onboardingCurrentStep == steps.length;
    if (onboarding.onboardingFlowVersion < kOnboardingFlowVersion &&
        !onboarding.onboardingCompleted) {
      // The persisted position was written against an older sequence — the
      // pre-redesign 7/8-step flow or the six-step one (an interrupted first
      // run that got this update mid-way). Which of the two decides the
      // translation table, so the stored version is threaded in rather than
      // assumed. Applied exactly once, then the flow version is stamped so
      // the translation can never re-run.
      saved = migrateLegacyOnboardingStepIndex(
        legacyIndex: onboarding.onboardingCurrentStep,
        fromVersion: onboarding.onboardingFlowVersion,
        platform: defaultTargetPlatform,
        autoPasteSupported: kAutoPasteSupported,
      );
      // Deferred: with fireImmediately:true this whole method can run
      // synchronously from initState (when settings already have a value at
      // mount time), and writing another provider mid-build throws "Tried to
      // modify a provider while the widget tree was building" (Sentry
      // FLUTTER_WHISPASTE-C7). Scheduling the write lets the current build
      // finish first.
      final migratedStep = saved;
      Future(() {
        if (!mounted) return;
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                onboarding: s.onboarding.copyWith(
                  onboardingCurrentStep: migratedStep,
                  onboardingFlowVersion: kOnboardingFlowVersion,
                ),
              ),
            );
      });
    } else {
      saved = onboarding.onboardingCurrentStep.clamp(0, steps.length - 1);
    }
    if (resumeModelDetour) {
      void openDetour() {
        _modelDetourOpen = true;
        _modelDetourFromWelcome = false;
      }

      if (mounted) {
        setState(openDetour);
      } else {
        openDetour();
      }
    }
    if (saved == _currentStep) {
      // No step jump needed (fresh install: saved defaults to 0, same as
      // _currentStep), but the entry event still needs to fire exactly once —
      // see [_entryTracked].
      if (!_entryTracked) {
        _entryTracked = true;
        _trackShown(steps[saved]);
      }
      return;
    }
    if (mounted) {
      setState(() {
        _previousStep = saved;
        _currentStep = saved;
      });
    } else {
      _previousStep = saved;
      _currentStep = saved;
    }
    _entryTracked = true;
    _trackShown(steps[saved]);
  }

  /// Persists [step] as the current onboarding position so a mid-flow app
  /// restart resumes here instead of restarting the whole flow.
  ///
  /// No-op in a review or a revision run: the resume position is first-run
  /// state, and paging through either must not overwrite where an
  /// interrupted first run got to — nor leave any trace of the run itself.
  /// A revision run's own position starts at 0 (`start()`) and ends at 0
  /// (`complete()`); nothing in between needs to survive a restart.
  void _persistCurrentStep(int step) {
    if (widget.manualReview || widget.revisionRun) return;
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(onboardingCurrentStep: step),
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the notifiers as soon as the provider scope is reachable so the
    // dispose path never needs to touch `ref`.
    _cachedPasteNotifier ??= ref.read(pasteCapabilityNotifierProvider.notifier);
    _cachedMicNotifier ??= ref.read(micPermissionNotifierProvider.notifier);
  }

  @override
  void dispose() {
    // Defensive cleanup: individual steps also stop polling in their own
    // dispose, but the overlay owns the provider scope and is the last line
    // of defence against sudden tear-downs (window close, app quit) that
    // skip individual step disposals.
    _cachedPasteNotifier?.stopPolling();
    _cachedMicNotifier?.stopPolling();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Step sequence
  // ---------------------------------------------------------------------------

  /// Returns the ordered step IDs. Delegates to [buildOnboardingStepIds],
  /// wiring [defaultTargetPlatform] and [kAutoPasteSupported] from the build
  /// environment — the sequence itself is platform-invariant, but keeping
  /// the injection makes that a tested property instead of an assumption.
  List<OnboardingStepId> _onboardingSteps() {
    return buildOnboardingStepIds();
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  /// The rerun this overlay shows, or `null` for a first run.
  OnboardingRerun? get _rerun => widget.manualReview
      ? OnboardingRerun.review
      : widget.revisionRun
      ? OnboardingRerun.revision
      : null;

  /// Fire-and-forget onboarding telemetry (fixed ids only, no PII). Feeds the
  /// per-step abandonment funnel (PRD US30). First-run events are held until
  /// the privacy choice (ticket 01 of `internal-notes`);
  /// the buffer sends them straight through in every other mode. Never throws.
  void _track(void Function(OnboardingTelemetry t) send) {
    try {
      send(ref.read(onboardingTelemetryProvider));
    } catch (e) {
      // Telemetry must never break onboarding — log and move on.
      _log.debug('Telemetry onboarding event skipped: $e');
    }
  }

  /// A page became visible. A returning user re-reading a page is not a
  /// first-run step: mixing the two would quietly inflate the per-step
  /// funnel and read as a first run that never ends, so reruns report their
  /// own `review_step` / `revision_step`.
  void _trackShown(OnboardingStepId step) {
    final screen = onboardingScreenOf(step);
    if (screen == null) return;
    final rerun = _rerun;
    _track(
      (t) => rerun == null
          ? t.stepShown(screen)
          : t.rerun(rerun, OnboardingRerunEvent.step, screen),
    );
  }

  /// A first-run event about [step]; nothing in a review or revision run.
  void _trackFirstRun(
    OnboardingStepId step,
    void Function(OnboardingTelemetry t, OnboardingScreen screen) send,
  ) {
    final screen = onboardingScreenOf(step);
    if (_rerun != null || screen == null) return;
    _track((t) => send(t, screen));
  }

  /// The end of a review or revision run, early ([OnboardingRerunEvent.exit])
  /// or read to the end, on the page it ended on.
  void _trackRerunEnd(OnboardingRerunEvent event) {
    final rerun = _rerun;
    final screen = onboardingScreenOf(_onboardingSteps()[_safeStep()]);
    if (rerun == null || screen == null) return;
    _track((t) => t.rerun(rerun, event, screen));
  }

  /// First-run signals that do not pass through the navigation: the
  /// microphone, the speech-model download and the first dictation.
  void _listenForSignals() {
    ref.listenManual(onboardingMicSpeechHeardProvider, (was, heard) {
      if (heard && was != true) _track((t) => t.micLevel(detected: true));
    });
    ref.listenManual(micPermissionNotifierProvider, (was, next) {
      final result = onboardingMicPermissionResult(was?.status, next.status);
      if (result == null) return;
      _track((t) => t.permission(OnboardingPermission.mic, result));
    });
    ref.listenManual(onboardingTestRecordingSucceededProvider, (was, ok) {
      if (ok && was != true) {
        _track((t) => t.firstDictation(OnboardingFirstDictation.ok));
      }
    });
    ref.listenManual(
      onboardingDownloadStatusProvider.select((s) => s.phase),
      _trackDownload,
    );
  }

  /// Whether a download failed in this run; the next start is a retry.
  bool _downloadFailed = false;

  void _trackDownload(
    OnboardingDownloadPhase? previous,
    OnboardingDownloadPhase next,
  ) {
    final event = onboardingDownloadEvent(
      previous,
      next,
      failedBefore: _downloadFailed,
    );
    if (event == null) return;
    if (event == OnboardingDownloadEvent.failed) _downloadFailed = true;
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    _track((t) => t.download(event, telemetryModelId(settings)));
  }

  /// What a page's answers send when the user moves on from it.
  void _trackAnswers(OnboardingStepId step) {
    if (_rerun != null) return;
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    switch (step) {
      case OnboardingStepId.about:
        final answers = onboardingAboutAnswers(
          settings.onboarding,
          systemName: ref.read(systemFirstNameProvider).value,
        );
        _track(
          (t) => t
            ..roles(answers.roles)
            ..attribution(answers.attribution)
            ..nameEdit(answers.name),
        );
      case OnboardingStepId.access:
        final result = onboardingPasteAccessResult(
          ref.read(pasteCapabilityNotifierProvider),
          defaultTargetPlatform,
        );
        if (result == null) return;
        _track((t) => t.permission(OnboardingPermission.pasteAccess, result));
      case OnboardingStepId.hotkey:
        final mode = onboardingHoldMode(ref)
            ? OnboardingHotkeyMode.hold
            : OnboardingHotkeyMode.toggle;
        final shape = settings.hotkey.hotkeyDoubleTapKey.isEmpty
            ? OnboardingHotkeyShape.combo
            : OnboardingHotkeyShape.modifierOnly;
        _track((t) => t.hotkeyChosen(mode, shape));
      default:
        return;
    }
  }

  /// Opens the privacy-choice hold for a first run (ticket 01, decision 5a):
  /// onboarding events and crash reports wait in memory until
  /// [_commitPrivacyChoice]. Never called for a review or a revision run —
  /// those start on an app whose choice is already made.
  void _beginPrivacyHold() {
    ref.read(onboardingTelemetryBufferProvider).begin();
    CrashReporter.instance?.holdForPrivacyChoice = true;
  }

  /// Applies the privacy choice as it stands right now and releases the hold.
  /// The choice counts as made when the onboarding flow completes, whether or
  /// not the user visited the privacy page first (ticket 01). Held events are
  /// sent when the switches allow it and dropped otherwise. Idempotent: after
  /// the first call the buffer ignores further decisions.
  void _commitPrivacyChoice() {
    if (!ref.read(onboardingTelemetryBufferProvider).isPending) return;
    final shareUsageStats =
        ref.read(settingsProvider).value?.privacy.shareUsageStats ?? false;
    _track((t) => t.consentDecided(shareUsageStats: shareUsageStats));
    CrashReporter.instance?.holdForPrivacyChoice = false;
  }

  void _goNext({bool skip = false}) {
    final steps = _onboardingSteps();
    if (_currentStep < steps.length - 1) {
      final left = steps[_currentStep];
      _trackAnswers(left);
      _trackFirstRun(
        left,
        (t, screen) => skip ? t.stepSkip(screen) : t.stepNext(screen),
      );
      setState(() {
        _previousStep = _currentStep;
        _currentStep++;
      });
      _persistCurrentStep(_currentStep);
      _trackShown(steps[_currentStep]);
    }
  }

  /// "Später" on the microphone and practice pages: moves on like Next, but
  /// counts as skipped. On the microphone page without a grant it is also
  /// the "later" answer to the permission.
  void _skipStep() {
    final step = _onboardingSteps()[_safeStep()];
    final micGranted =
        ref.read(micPermissionNotifierProvider).status ==
        MicPermissionStatus.granted;
    if (step == OnboardingStepId.mic && !micGranted) {
      _trackFirstRun(
        step,
        (t, _) => t.permission(
          OnboardingPermission.mic,
          OnboardingPermissionResult.later,
        ),
      );
    }
    _goNext(skip: true);
  }

  void _goToStep(OnboardingStepId id) {
    final index = _onboardingSteps().indexOf(id);
    if (index < 0 || index == _currentStep) return;
    _trackFirstRun(
      _onboardingSteps()[_safeStep()],
      (t, screen) => t.stepBack(screen),
    );
    _trackFirstRun(id, (t, screen) => t.stepShown(screen));
    setState(() {
      _previousStep = _currentStep;
      _currentStep = index;
    });
    _persistCurrentStep(_currentStep);
  }

  void _goBack() {
    if (_currentStep > 0) {
      final steps = _onboardingSteps();
      _trackFirstRun(steps[_currentStep], (t, screen) => t.stepBack(screen));
      setState(() {
        _previousStep = _currentStep;
        _currentStep--;
      });
      _persistCurrentStep(_currentStep);
      _trackFirstRun(steps[_currentStep], (t, screen) => t.stepShown(screen));
    }
  }

  /// Opens the model page from the closing page ("Modell laden"). The stored
  /// position moves one past the last page while it is open, so a restart
  /// resumes on the model page; leaving it stores the closing page again.
  void _openModelDetour() {
    if (_modelDetourOpen) return;
    final from = _onboardingSteps()[_safeStep()];
    final fromWelcome = from == OnboardingStepId.welcome;
    _trackFirstRun(from, (t, screen) => t.modelSwitchOpened(screen));
    setState(() {
      _modelDetourOpen = true;
      _modelDetourFromWelcome = fromWelcome;
      if (fromWelcome) _welcomeModelVisited = true;
    });
    // Stored one past the last page, so a restart lands back on the model
    // page. The start page's detour is not stored: it resumes on the start page.
    if (!fromWelcome) _persistCurrentStep(_onboardingSteps().length);
  }

  void _closeModelDetour() {
    if (!_modelDetourOpen) return;
    setState(() {
      _modelDetourOpen = false;
      _modelDetourFromWelcome = false;
    });
    _persistCurrentStep(_safeStep());
  }

  /// The start page's main action (Onboarding v6, V02, S6): the user agrees to
  /// the speech-model download, which then runs in the background while the
  /// flow continues.
  Future<void> _consentWelcome() async {
    if (_welcomeConsentPending) return;
    _welcomeConsentPending = true;
    try {
      final proceed = await startWelcomeSpeechDownload(
        context: context,
        ref: ref,
        settingsAlreadySet: _welcomeModelVisited,
      );
      if (proceed && mounted) _goNext();
    } catch (e, st) {
      // Unawaited from the button, so without this the failure would vanish.
      // The flow moves on anyway: the practice page then names the missing
      // model and offers to load it, instead of the user staying stuck here.
      // Handled, so a local warning only: Sentry takes errors and crashes.
      _log.warning('Start page: speech model consent failed', e, st);
      if (mounted) _goNext();
    } finally {
      _welcomeConsentPending = false;
    }
  }

  /// Leaves a review and hands the window back to the Settings page the user
  /// started from.
  ///
  /// Flipping the ephemeral flag is the whole of it: the overlay unmounts on
  /// the next frame and the app shell underneath was never navigated away
  /// from. Nothing persisted is touched — in particular not
  /// `onboardingCompleted`, which is already `true` and whose only other
  /// possible value would mean "this user never set the app up".
  void _exitManualReview() {
    _trackRerunEnd(OnboardingRerunEvent.exit);
    ref.read(onboardingManuallyOpenProvider.notifier).close();
  }

  /// Leaves a revision run early — the visible counterpart to reading it to
  /// the end.
  ///
  /// Both endings are the *same* ending: [OnboardingRevisionRunNotifier.complete]
  /// stamps the target version either way, because a revision run is offered
  /// at most once per version (parent PRD, "Abbruch stempelt ebenfalls").
  /// That is precisely why this route is confirmed and the confirmation says
  /// out loud what stays unconfigured: it is a one-way door, and a one-way
  /// door the user walks through by accident is the failure mode here — not
  /// one extra tap.
  ///
  /// Dismissing the dialog (Esc, barrier tap, "Cancel") returns `false` and
  /// leaves the user exactly where they were, on the step they were reading.
  Future<void> _exitRevisionRun() async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.onboardingRevisionExitConfirmTitle,
      message: l10n.onboardingRevisionExitConfirmBody,
      confirmLabel: l10n.onboardingRevisionExitConfirmAction,
      cancelLabel: l10n.actionCancel,
      cta: WpDialogCta.hero,
    );
    if (!confirmed || !mounted) return;
    // Its own action name, not 'revision_complete': the funnel's whole point
    // here is telling "read to the end" apart from "left on step 2".
    _trackRerunEnd(OnboardingRerunEvent.exit);
    await ref.read(onboardingRevisionRunProvider.notifier).complete();
  }

  /// The first run's close X (Windows, Linux): counted as a quit on the page
  /// it was closed from. Held like every first-run event, so it leaves only
  /// once a later run commits the privacy choice.
  void _quitFirstRun() {
    _trackFirstRun(
      _onboardingSteps()[_safeStep()],
      (t, screen) => t.quit(screen),
    );
    windowManager.close();
  }

  int _safeStep() => _currentStep.clamp(0, _onboardingSteps().length - 1);

  Future<void> _complete() async {
    if (widget.manualReview) {
      // The last step's action in a review *is* the exit — same destination,
      // just reached by reading to the end rather than leaving early.
      _exitManualReview();
      return;
    }
    if (widget.revisionRun) {
      // Same shared ending [_exitRevisionRun] calls — reaching the last step
      // and leaving early are not different outcomes, per the parent PRD
      // ("Abbruch stempelt ebenfalls"). Only the tracked action differs, so
      // the funnel can still tell the two apart.
      _trackRerunEnd(OnboardingRerunEvent.complete);
      await ref.read(onboardingRevisionRunProvider.notifier).complete();
      return;
    }
    // Finishing with the switches visible is the privacy choice too.
    _commitPrivacyChoice();
    _track((t) => t.complete());
    recordOnboardingCompletedOn(DateTime.now());
    // US17: a freshly set-up user is, by construction, caught up on the
    // onboarding content they were just shown — stamping the target version
    // here, in the same write as `onboardingCompleted`, is what keeps them
    // from walking straight into a revision run on their very next start.
    final registry = ref.read(onboardingRevisionRegistryProvider);
    final targetVersion = targetOnboardingContentVersion(
      registry,
      currentOnboardingPlatform(),
    );
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(
              onboardingCompleted: true,
              onboardingCurrentStep: 0,
              onboardingContentVersion: targetVersion,
              // Only the final action arms the "Erste Schritte" card (see
              // OnboardingSettings.firstStepsArmed); existing installs never
              // pass here again.
              firstStepsArmed: true,
              completedInVersion: appVersion,
            ),
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Page builder — merged page contents; navigation stays with the shell.
  // ---------------------------------------------------------------------------

  /// Every page hands its leftover height to its body block
  /// ([OnboardingPageFill] plus the page's own [OnboardingPageBody]).
  ///
  /// Including page 1: its brand lockup is that page's header, and it has to
  /// start at the same height as every other page's heading. Centring the
  /// page as a whole — which is what page 1 used to do — made the lockup's
  /// position depend on how tall the rest of the page was, so the logo sat
  /// visibly lower than page 2's title. Including the tight pages costs
  /// nothing: the fill can never shrink a gap below its minimum, so the
  /// hotkey page's conflict branch simply keeps its minimum gaps.
  /// Try & Go used to be the one exclusion (its heading was the left
  /// column's first block); since the page adopted the shared
  /// [OnboardingPage] header treatment there is no exception left.
  Widget _buildStep(OnboardingStepId id, double availableHeight) {
    return OnboardingPageFill(
      availableHeight: availableHeight,
      child: _buildStepContent(id),
    );
  }

  /// Whether the shell's Next is held on the microphone page until speech has
  /// been heard (Onboarding v6, S3). Never in a review or a revision run.
  bool _micStepBlocked(OnboardingStepId id, bool heard) =>
      !widget.manualReview &&
      !widget.revisionRun &&
      id == OnboardingStepId.mic &&
      !heard;

  /// Whether the shell's Next is held on [id] because the model page has no
  /// model, no running download and no saved cloud key (UIA-RT-01,
  /// UIA-MDL-GATE). Never in a review or a revision run, see the Next gate in
  /// [build].
  bool _modelStepBlocked(OnboardingStepId id) =>
      !widget.manualReview &&
      !widget.revisionRun &&
      id == OnboardingStepId.speech &&
      !ref.watch(onboardingModelStepCanAdvanceProvider);

  /// The nav row's primary action and label for the page on screen. The
  /// order matters: the open model detour, then the start page, then the
  /// regular pages, then the closing page's gates.
  ({VoidCallback? action, String label}) _primaryNav({
    required L10n l10n,
    required OnboardingStepId shownStep,
    required bool isLastStep,
    required bool isReturningRun,
    required bool needsHotkeyFix,
    required bool needsModel,
    required bool hotkeyHoldsNext,
    required bool micHeard,
    required bool practiceDictated,
  }) {
    if (_modelDetourOpen) {
      return (
        action: _modelStepBlocked(OnboardingStepId.speech)
            ? null
            : _closeModelDetour,
        label: l10n.onboardingNext,
      );
    }
    if (shownStep == OnboardingStepId.welcome && !isReturningRun) {
      return (action: _consentWelcome, label: l10n.onboardingWelcomeStart);
    }
    // Practice page (V06): "Weiter" waits for a dictation that landed in the
    // chat field. "Später ausprobieren" in the footer is the way past it.
    if (shownStep == OnboardingStepId.tryOut && !isReturningRun) {
      return (
        action: practiceDictated ? _goNext : null,
        label: practiceDictated
            ? l10n.onboardingNext
            : l10n.onboardingPracticeWaiting,
      );
    }
    if (!isLastStep) {
      return (
        action: hotkeyHoldsNext || _micStepBlocked(shownStep, micHeard)
            ? null
            : _goNext,
        label: l10n.onboardingNext,
      );
    }
    if (needsHotkeyFix) {
      return (
        action: () => _goToStep(OnboardingStepId.hotkey),
        label: l10n.onboardingReadyFixHotkey,
      );
    }
    if (needsModel) {
      return (action: _openModelDetour, label: l10n.onboardingLoadModel);
    }
    return (
      action: _complete,
      label: isReturningRun
          ? l10n.onboardingReviewDone
          : l10n.onboardingStartWhisPaste,
    );
  }

  Widget _buildStepContent(OnboardingStepId id) {
    final l10n = L10n.of(context);
    return switch (id) {
      OnboardingStepId.about => AboutStep(onNext: _goNext),
      OnboardingStepId.welcome => WelcomeStep(
        revisionRun: widget.revisionRun,
        onOpenModel: _openModelDetour,
      ),
      OnboardingStepId.access => PermissionsStep(onNext: _goNext),
      OnboardingStepId.mic => OnboardingPage(
        header: OnboardingPageHeading(
          testId: 'onboarding-mic-heading',
          title: l10n.onboardingMicStatement,
        ),
        body: AccessMicStep(onSkip: _skipStep, onNext: _goNext),
      ),
      // Full bleed in every run; kept for completeness of the switch.
      OnboardingStepId.hotkey => const HotkeyCaptureScope(child: TriggerStep()),
      OnboardingStepId.tryOut => OnboardingPage(
        header: OnboardingPageHeading(
          testId: 'onboarding-tryout-heading',
          title: l10n.onboardingTestRecordingTitle,
          subtitle: onboardingHoldMode(ref)
              ? l10n.onboardingTestRecordingSubtitleHold
              : l10n.onboardingTestRecordingSubtitle,
        ),
        body: const TestRecordingStep(),
      ),
      // Full bleed in every run; kept for completeness of the switch.
      OnboardingStepId.privacy => const PrivacyStep(key: kPrivacyStepPageKey),
      OnboardingStepId.speech => OnboardingPage(
        header: OnboardingPageHeading(
          testId: 'onboarding-model-heading',
          title: l10n.onboardingModelTitle,
          subtitle: _modelDetourFromWelcome
              ? l10n.onboardingWelcomeLaterChangeable
              : l10n.onboardingModelSubtitle,
        ),
        body: OnboardingMotionStep(
          beat: 2,
          testId: 'onboarding-speech-motion',
          child: ModelStep(nextBlocked: _modelStepBlocked(id)),
        ),
      ),
    };
  }

  /// The top strip: a pure drag handle with a fixed height.
  ///
  /// The window runs with `TitleBarStyle.hidden`, so this strip is what
  /// stands in for the title bar as the window's drag area. It is
  /// unconditional and keeps its fixed height in every mode — nothing below
  /// it may shift. The exit controls that used to live inside it (the
  /// close/leave X and the revision run's labelled exit) float in
  /// [_buildExitControls]'s corner layer now; see that method for the
  /// per-platform and per-mode rules of when an exit is drawn at all.
  Widget _buildTopBar({
    required List<String> phaseLabels,
    required int currentPhase,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      // Tight, not a floor: relaxing this to a minHeight pushes every page's
      // header down the window and shifts the layout of all six pages. The
      // strip carries no controls any more: the exit controls float in
      // [_buildExitControls]'s corner layer so their insets never depend on
      // this strip's geometry. The strip is a pure drag handle with the fixed
      // height nothing below may shift for.
      child: Container(
        height: _kOnboardingTopBarHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: WpColors.borderSubtle)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxl),
            child: _PhaseStepper(labels: phaseLabels, current: currentPhase),
          ),
        ),
      ),
    );
  }

  /// The floating exit controls — the revision run's labelled exit and the
  /// close/leave X — as a corner layer above the page (see the [Stack] in
  /// [build]).
  ///
  /// A layer and not children of the 32-px top strip, for one measured
  /// reason: inside the strip the X's glyph sat 6 px from the top edge
  /// (centred in the 32-px band) but 18 px from the side (the strip's 12-px
  /// padding plus the button's own 6), which on the frameless Windows/Linux
  /// window read as the X hugging the top while floating off the corner.
  /// The layer gives the glyph the same [_kOnboardingExitGlyphInset] on both
  /// axes, and — because it overlays instead of occupying — moves nothing
  /// below it. The strip keeps its height and stays the drag handle.
  ///
  /// Returns `null` when no exit control is drawn (the macOS first run: the
  /// native traffic lights are the close affordance there and the custom X
  /// would duplicate them).
  Widget? _buildExitControls(L10n l10n, Color textMuted) {
    // One condition, read twice: the X and the gap that precedes it. Held
    // apart they drifted — the gap hung off `revisionRun` alone and stayed
    // behind on macOS, where the X is not drawn, leaving the revision run's
    // exit button 4 px short of where the review's X sits.
    final showExitIcon =
        widget.manualReview || defaultTargetPlatform != TargetPlatform.macOS;
    if (!showExitIcon && !widget.revisionRun) return null;
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The revision run's named exit, on every step of the flow. A ghost
        // button in the neutral tone: visible and reachable, but never
        // competing with the accent "Next" — leaving is the rarer intent,
        // and the gradient hero button below stays the one obvious way
        // forward.
        if (widget.revisionRun) ...[
          WpButton(
            testId: 'onboarding-nav-revision-exit',
            key: kOnboardingRevisionExitButtonKey,
            label: l10n.onboardingRevisionExit,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            size: WpButtonSize.dense,
            icon: LucideIcons.logOut,
            onPressed: _exitRevisionRun,
          ),
          // Only a separator, never a trailing margin: it exists to keep the
          // labelled exit off the X, so it is drawn under exactly the
          // condition the X is.
          if (showExitIcon) const SizedBox(width: WpSpacing.xxs),
        ],
        if (showExitIcon)
          // One node carries the identifier, the label and the tap action.
          // excludeSemantics drops the IconButton's own duplicate node, which
          // would otherwise have no identifier.
          Semantics(
            button: true,
            identifier: 'onboarding-nav-review-exit',
            label: widget.manualReview
                ? l10n.onboardingReviewExit
                : MaterialLocalizations.of(context).closeButtonTooltip,
            onTap: widget.manualReview ? _exitManualReview : _quitFirstRun,
            excludeSemantics: true,
            child: IconButton(
              key: kOnboardingReviewExitButtonKey,
              onPressed: widget.manualReview
                  ? _exitManualReview
                  : _quitFirstRun,
              icon: Icon(
                LucideIcons.x,
                // `md`, the floor DESIGN.md sets for an interactive icon; 18
                // was off the scale in both directions. The 32-px constraints
                // below set the button's own box.
                size: WpIconSize.md,
                color: textMuted,
              ),
              tooltip: widget.manualReview
                  ? l10n.onboardingReviewExit
                  : MaterialLocalizations.of(context).closeButtonTooltip,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _kOnboardingExitBoxSize,
                minHeight: _kOnboardingExitBoxSize,
              ),
            ),
          ),
      ],
    );
    // A review's (and revision run's) exit sits at the physical right on
    // every platform and in every locale. The physical left is where macOS
    // draws the native traffic lights under TitleBarStyle.hidden — they do
    // not move for Hebrew — and those two modes carry the exit on macOS too,
    // so a *logical* placement would land on top of them in RTL. Only the
    // first run keeps the ambient direction, its X being drawn only where
    // the whole title bar is gone and that leading corner is free.
    return widget.manualReview || widget.revisionRun
        ? Positioned(
            top: _kOnboardingExitBoxInset,
            right: _kOnboardingExitBoxInset,
            child: controls,
          )
        : PositionedDirectional(
            top: _kOnboardingExitBoxInset,
            start: _kOnboardingExitBoxInset,
            child: controls,
          );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Whether a confirmed conflict holds Next on the Hotkey page until
  /// another key is recorded there (E2 a). The page itself waits for a full
  /// start and stop of the key, see [TriggerStep].
  bool _hotkeyHoldsNext(
    OnboardingStepId shownStep,
    HotkeyRegistrationStatus hotkeyStatus,
  ) =>
      !_modelDetourOpen &&
      shownStep == OnboardingStepId.hotkey &&
      hotkeyStatus == HotkeyRegistrationStatus.conflict;

  /// Whether the closing page's main action must read "Modell laden": no
  /// speech model is installed, no download is running and no cloud key is
  /// saved. A download that never started, was aborted or failed counts.
  /// Never in a review or a revision run.
  bool _closingPageNeedsModel(bool isReturningRun) {
    if (isReturningRun) return false;
    return !ref.watch(onboardingModelStepCanAdvanceProvider);
  }

  /// Whether the closing page's main action sends the user to the hotkey
  /// page: a confirmed hotkey conflict, outside review and revision runs.
  bool _closingPageNeedsHotkeyFix(
    HotkeyRegistrationStatus hotkeyStatus,
    bool isReturningRun,
  ) => !isReturningRun && hotkeyStatus == HotkeyRegistrationStatus.conflict;

  /// Stable identifier of the primary action. On the closing page it names
  /// what the action does; elsewhere it is the shell's generic Next.
  String _nextActionTestId(
    OnboardingStepId shownStep, {
    required bool isReturningRun,
    required bool needsHotkeyFix,
    required bool needsModel,
  }) {
    if (shownStep != OnboardingStepId.privacy || isReturningRun) {
      return 'onboarding-nav-next';
    }
    if (needsHotkeyFix) return 'onboarding-ready-fix-hotkey';
    return needsModel
        ? 'onboarding-ready-load-model'
        : 'onboarding-ready-start';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final steps = _onboardingSteps();
    final totalSteps = steps.length;
    final safeCurrent = _currentStep.clamp(0, totalSteps - 1);
    final isLastStep = safeCurrent == totalSteps - 1;
    // The page on screen: the model page while it is open as a detour.
    final shownStep = _modelDetourOpen
        ? OnboardingStepId.speech
        : steps[safeCurrent];
    final direction = _currentStep >= _previousStep ? 1.0 : -1.0;
    // Page content and the nav row below it share one frame width, so the
    // actions always sit on the same margins as the page above. Animated, not
    // switched: page 1 runs a wider frame than the rest, and snapping between
    // the two widths during the cross-fade read as the frame jumping.
    final targetFrameWidth = _frameWidthFor(shownStep);
    Widget frame({required Widget child}) => TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetFrameWidth),
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      curve: WpMotion.smooth_,
      builder: (context, width, child) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
      child: child,
    );

    // The closing page's main action is never grey (no dead button). A
    // confirmed hotkey conflict turns it into "Hotkey ändern", which leads to
    // the hotkey page. A missing speech model turns it into "Modell laden"
    // (no model, no running download, no cloud key). A review or revision run
    // opens on an app that already works and is never gated.
    final hotkeyStatus = ref.watch(hotkeyRegistrationStatusProvider);
    final isReturningRun = widget.manualReview || widget.revisionRun;
    final needsHotkeyFix = _closingPageNeedsHotkeyFix(
      hotkeyStatus,
      isReturningRun,
    );
    final needsModel = _closingPageNeedsModel(isReturningRun);
    final micHeard = ref.watch(onboardingMicSpeechHeardProvider);
    final practiceDictated = ref.watch(
      onboardingTestRecordingSucceededProvider,
    );

    final hotkeyHoldsNext = _hotkeyHoldsNext(shownStep, hotkeyStatus);

    final primary = _primaryNav(
      l10n: l10n,
      shownStep: shownStep,
      isLastStep: isLastStep,
      isReturningRun: isReturningRun,
      needsHotkeyFix: needsHotkeyFix,
      needsModel: needsModel,
      hotkeyHoldsNext: hotkeyHoldsNext,
      micHeard: micHeard,
      practiceDictated: practiceDictated,
    );
    final VoidCallback? nextAction = primary.action;
    final String nextLabel = primary.label;
    final nextTestId = _nextActionTestId(
      shownStep,
      isReturningRun: isReturningRun,
      needsHotkeyFix: needsHotkeyFix,
      needsModel: needsModel,
    );
    final VoidCallback? backAction = _modelDetourOpen
        ? _closeModelDetour
        : (safeCurrent > 0 ? _goBack : null);
    final VoidCallback? laterAction =
        (!_modelDetourOpen && shownStep == OnboardingStepId.tryOut)
        ? _skipStep
        : null;

    // Enter/Escape mirror the primary action and Back so the flow can be
    // walked from the keyboard — except while a text field or the inline
    // hotkey recorder has focus: both need those keys themselves. A focused
    // button keeps its own Enter.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _activateFocusedOr(nextAction),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _activateFocusedOr(nextAction),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _runUnlessTextInputFocused(backAction),
      },
      // Holds the keyboard for the shortcuts above. Its own scope keeps Tab
      // inside the onboarding: without it, Tab ran on into the app behind,
      // whose controls are covered, so the focus vanished from sight.
      child: FocusScope(
        autofocus: true,
        skipTraversal: true,
        child: _buildSurface(
          context: context,
          l10n: l10n,
          totalSteps: totalSteps,
          safeCurrent: safeCurrent,
          shownStep: shownStep,
          direction: direction,
          frame: frame,
          frameWidth: targetFrameWidth,
          textMuted: WpColors.textMuted,
          nextAction: nextAction,
          nextLabel: nextLabel,
          nextTestId: nextTestId,
          backAction: backAction,
          laterAction: laterAction,
        ),
      ),
    );
  }

  /// Enter on a focused control (a button reached with Tab) activates that
  /// control, as everywhere else; this shortcut layer sits between it and the
  /// app's Enter → activate mapping and would otherwise swallow the key.
  void _activateFocusedOr(VoidCallback? next) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null) {
      const intent = ActivateIntent();
      final action = Actions.maybeFind<ActivateIntent>(focused, intent: intent);
      if (action != null && action.isActionEnabled) {
        Actions.invoke(focused, intent);
        return;
      }
    }
    _runUnlessTextInputFocused(next);
  }

  void _runUnlessTextInputFocused(VoidCallback? action) {
    if (action == null) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null ||
            // Its KeyboardListener sees keys without consuming them.
            focused.findAncestorWidgetOfExactType<WpHotkeyRecorderDialog>() !=
                null)) {
      return;
    }
    action();
  }

  /// The full-bleed pages place their own back, primary and later actions.
  Widget _fullBleedPage({
    required OnboardingStepId shownStep,
    required VoidCallback? nextAction,
    required String nextLabel,
    required String nextTestId,
    required VoidCallback? backAction,
    required VoidCallback? laterAction,
  }) => switch (shownStep) {
    OnboardingStepId.about => AboutStep(
      primaryKey: kOnboardingNextButtonKey,
      onNext: _goNext,
      onBack: backAction,
    ),
    OnboardingStepId.access => PermissionsStep(
      primaryKey: kOnboardingNextButtonKey,
      onNext: _goNext,
      onBack: backAction,
    ),
    OnboardingStepId.mic => AccessMicStep(
      primaryKey: kOnboardingNextButtonKey,
      onSkip: _skipStep,
      // Null while S3 holds Weiter until speech is heard; Überspringen is the
      // way on without it.
      onNext: nextAction,
      onBack: backAction,
    ),
    // The capture scope keeps the global hotkey untouched while the page
    // records a new one.
    OnboardingStepId.hotkey => HotkeyCaptureScope(
      child: TriggerStep(
        primaryKey: kOnboardingNextButtonKey,
        onNext: nextAction,
        onBack: backAction,
      ),
    ),
    OnboardingStepId.tryOut => TestRecordingStep(
      primaryKey: kOnboardingNextButtonKey,
      nextLabel: nextLabel,
      onNext: nextAction,
      onLater: laterAction,
      onBack: backAction,
    ),
    OnboardingStepId.privacy => PrivacyStep(
      key: kPrivacyStepPageKey,
      primaryKey: kOnboardingNextButtonKey,
      nextLabel: nextLabel,
      nextTestId: nextTestId,
      onNext: nextAction,
      onBack: backAction,
      needsModel: _closingPageNeedsModel(
        widget.manualReview || widget.revisionRun,
      ),
    ),
    _ => WelcomeStep(
      onOpenModel: _openModelDetour,
      onPrimary: nextAction,
      primaryLabel: nextLabel,
      primaryTestId: nextTestId,
      primaryKey: kOnboardingNextButtonKey,
    ),
  };

  Widget _buildSurface({
    required BuildContext context,
    required L10n l10n,
    required int totalSteps,
    required int safeCurrent,
    required OnboardingStepId shownStep,
    required double direction,
    required Widget Function({required Widget child}) frame,
    required double frameWidth,
    required Color textMuted,
    required VoidCallback? nextAction,
    required String nextLabel,
    required String nextTestId,
    required VoidCallback? backAction,
    required VoidCallback? laterAction,
  }) {
    // Screen 1 runs full bleed: no bottom bar, the page places its own primary
    // action. The model detour and the revision run keep the shell.
    // Screen 2 shares that composition and places its own actions too.
    final fullBleed =
        !_modelDetourOpen &&
        (shownStep == OnboardingStepId.about ||
            shownStep == OnboardingStepId.access ||
            shownStep == OnboardingStepId.mic ||
            shownStep == OnboardingStepId.hotkey ||
            shownStep == OnboardingStepId.tryOut ||
            shownStep == OnboardingStepId.privacy ||
            shownStep == OnboardingStepId.welcome && !widget.revisionRun);
    return BlockSemantics(
      // The whole surface doubles as a window drag area: the title bar is
      // hidden during onboarding, and interactive children win the gesture
      // arena over the pan recognizer, so dragging any empty region moves
      // the window.
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: DecoratedBox(
          // The navy stage of the window frame, as in the main UI (MP-1,
          // V11-01): in the navy look this is the dark frame, in the other
          // looks it equals the content gradient. Deliberately no blur and no
          // dimmed scrim (and therefore no Windows frameless-window blur
          // fallback either).
          decoration: BoxDecoration(gradient: WpColors.frame.frameGradient),
          // A Stack, because the exit controls (revision exit + close X) are
          // a floating corner layer rather than children of the top strip —
          // the one way their glyph can sit symmetrically in the corner
          // without growing the 32-px strip or shifting the page below it
          // (see [_buildExitControls]).
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(
                    phaseLabels: [
                      l10n.onboardingPhaseStart,
                      l10n.onboardingPhasePersonalize,
                      l10n.onboardingPhasePermissions,
                      l10n.onboardingPhaseSetup,
                      l10n.onboardingPhaseTry,
                    ],
                    currentPhase: onboardingPhaseOf(shownStep).index,
                  ),

                  // -- Page content — scrolls when the window shrinks. ----------
                  //
                  // The LayoutBuilder is what lets a page know how much room it
                  // has: inside the scroll view the height is unbounded, so the
                  // measurement has to happen above it and be handed down (see
                  // [OnboardingPageFill]).
                  Expanded(
                    // The full-bleed pages (welcome, about) differ from the
                    // framed ones in shape, so the switch between them cross-
                    // fades instead of jumping; framed pages animate inside.
                    child: AnimatedSwitcher(
                      duration: WpMotion.durationFor(
                        context,
                        WpMotion.dramatic,
                      ),
                      switchInCurve: WpMotion.smooth_,
                      switchOutCurve: WpMotion.smooth_,
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          fullBleed ? shownStep.name : 'framed',
                        ),
                        child: OnboardingPageFocusRoot(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final availableHeight =
                                  constraints.maxHeight - WpSpacing.lg * 2;
                              // Every page anchors to the top: each one carries its own
                              // fixed header and centres its body underneath
                              // ([OnboardingPageBody]), so nothing here needs a
                              // per-page anchor any more — page 1 used to be centred as
                              // a whole and that is exactly what pushed its logo below
                              // the other pages' headings.
                              //
                              // The Align itself is load-bearing and not decoration: it
                              // hands the scroll view *loose* constraints. That is what
                              // lets the page shrink-wrap (so a window smaller than the
                              // fixed one actually reports a scroll extent) and what
                              // lets `frame`'s maxWidth cap bind at all — under the
                              // tight width it would otherwise receive, the
                              // ConstrainedBox is enforced away and page 1's 860-px
                              // frame would silently run the full window width.
                              if (fullBleed) {
                                return _fullBleedPage(
                                  shownStep: shownStep,
                                  nextAction: nextAction,
                                  nextLabel: nextLabel,
                                  nextTestId: nextTestId,
                                  backAction: backAction,
                                  laterAction: laterAction,
                                );
                              }
                              return Align(
                                alignment: Alignment.topCenter,
                                // The affordance owns the one scroll view of the page
                                // and shows its thumb while the page overflows
                                // (UX-049: at large text scale the rows below the
                                // fold were otherwise the only hint).
                                child: SettingsScrollAffordance(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: WpSpacing.xl,
                                    vertical: WpSpacing.lg,
                                  ),
                                  child: frame(
                                    child: AnimatedSwitcher(
                                      duration: WpMotion.durationFor(
                                        context,
                                        WpMotion.smooth,
                                      ),
                                      switchInCurve: WpMotion.smooth_,
                                      switchOutCurve: WpMotion.smooth_,
                                      transitionBuilder: (child, animation) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: Offset(
                                                0.05 * direction,
                                                0,
                                              ),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: KeyedSubtree(
                                        key: ValueKey<OnboardingStepId>(
                                          shownStep,
                                        ),
                                        child: OnboardingPageFocusRoot(
                                          child: _buildStep(
                                            shownStep,
                                            availableHeight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // -- Shell-owned navigation: one primary action, centred. -----
                  // Back and the page's secondary way are text links beneath
                  // it. Toasts rise above this block rather than cover it.
                  if (!fullBleed)
                    WpToastDockReserve(
                      child: Padding(
                        // The primary action stays clear of the launcher's
                        // corner: where the centred frame reaches it, the bar
                        // gives up that room on its end side.
                        padding: EdgeInsetsDirectional.only(
                          start: WpSpacing.xl,
                          end: math.max(
                            WpSpacing.xl,
                            _kOnboardingContactReserve -
                                (MediaQuery.sizeOf(context).width -
                                        frameWidth) /
                                    2,
                          ),
                        ),
                        child: frame(
                          child: Column(
                            key: kOnboardingNavRowKey,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Onboarding v6, V12: the bottom bar. Download status
                              // on the left, Back and the one amber primary action
                              // on the right.
                              Row(
                                children: [
                                  const Expanded(
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: OnboardingDownloadFooter(),
                                    ),
                                  ),
                                  if (backAction != null) ...[
                                    WpButton(
                                      testId: 'onboarding-nav-back',
                                      key: kOnboardingBackButtonKey,
                                      label: l10n.onboardingBack,
                                      variant: WpButtonVariant.ghost,
                                      tone: WpButtonTone.neutral,
                                      onPressed: backAction,
                                    ),
                                    const SizedBox(width: WpSpacing.sm),
                                  ],
                                  SizedBox(
                                    width: 320,
                                    // loam-ignore: a11y-interactive-semantics – semantics provided in WpHeroButton.build
                                    child: WpHeroButton(
                                      testId: nextTestId,
                                      key: kOnboardingNextButtonKey,
                                      label: nextLabel,
                                      onPressed: nextAction,
                                    ),
                                  ),
                                ],
                              ),
                              if (laterAction != null) ...[
                                const SizedBox(height: WpSpacing.xs),
                                WpButton(
                                  testId: 'onboarding-tryout-later',
                                  key: kOnboardingTryLaterButtonKey,
                                  label: l10n.onboardingTryOutLaterCta,
                                  variant: WpButtonVariant.ghost,
                                  tone: WpButtonTone.neutral,
                                  onPressed: laterAction,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                  // -- Stepper dots + step counter, on ONE line. ----------------
                  //
                  // These two say the same thing: N dots with the current one
                  // filled, and then "Step N of M" spelled out directly beneath.
                  // Both earn their place — the dots are the glanceable shape of
                  // the flow, the counter is the part a screen reader and a
                  // text-scaled UI can actually read — but stacked they cost two
                  // lines to say it once, and the second line came out of the
                  // page above. Side by side they read as one caption and cost
                  // one line. See `_kOnboardingBottomGap` for why this stack was
                  // the binding constraint on Try & Go rather than a cosmetic.
                  if (!fullBleed) const SizedBox(height: WpSpacing.md),
                  // The phase stepper above shows the progress; the step
                  // counter is for screen readers only (review round 3).
                  // Its own semantics node: without the boundary it merged
                  // with the contact launcher into one unlabelled button.
                  Semantics(
                    key: kOnboardingStepCounterKey,
                    container: true,
                    liveRegion: true,
                    label: l10n.onboardingStepOf(safeCurrent + 1, totalSteps),
                    child: const SizedBox.shrink(),
                  ),
                  if (!fullBleed) const SizedBox(height: _kOnboardingBottomGap),
                ],
              ),
              ?_buildExitControls(l10n, textMuted),
              // The contact launcher keeps one corner on every page. On the
              // start page it appears once the intro is halfway through.
              PositionedDirectional(
                end: _kOnboardingContactInset,
                bottom: _kOnboardingContactInset,
                child: OnboardingContactLauncher(
                  stepId: shownStep.name,
                  onOpened: () => _trackFirstRun(
                    shownStep,
                    (t, screen) => t.contactOpened(screen),
                  ),
                  visible: contactLauncherShown(
                    fullBleed: fullBleed,
                    halfway: ref.watch(onboardingIntroHalfwayProvider),
                    step: shownStep,
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

/// The five named phases of the flow, shown on top of every page. Setup
/// covers the model page and the hotkey page; the microphone is a permission.
enum OnboardingPhase { start, personalize, permissions, setup, tryOut }

OnboardingPhase onboardingPhaseOf(OnboardingStepId id) => switch (id) {
  OnboardingStepId.welcome => OnboardingPhase.start,
  OnboardingStepId.about => OnboardingPhase.personalize,
  OnboardingStepId.access ||
  OnboardingStepId.mic => OnboardingPhase.permissions,
  OnboardingStepId.hotkey || OnboardingStepId.speech => OnboardingPhase.setup,
  OnboardingStepId.tryOut => OnboardingPhase.tryOut,
  OnboardingStepId.privacy => OnboardingPhase.tryOut,
};

/// The top phase stepper: the current phase in accent, the finished ones with
/// a check, the rest muted. Each phase is a labelled node for assistive
/// technology, and the current one is marked as selected.
class _PhaseStepper extends StatelessWidget {
  const _PhaseStepper({required this.labels, required this.current});

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Onboarding v6, V12 (Q2): from an 800 px window or the 1.3 text scale on,
    // only the active phase keeps its name, with "N von M". Every phase stays
    // a labelled node for assistive technology.
    final narrow =
        MediaQuery.sizeOf(context).width <= 800 ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final shown = narrow
        ? [current]
        : [for (var i = 0; i < labels.length; i++) i];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in shown) ...[
          // Chevrons read as a path through the phases, not as a list.
          if (i != shown.first)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
              child: Icon(
                LucideIcons.chevronRight,
                size: WpIconSize.sm,
                color: WpColors.textMuted,
              ),
            ),
          _phaseNode(i),
        ],
        if (narrow) ...[
          const SizedBox(width: WpSpacing.md),
          Text(
            l10n.onboardingPhaseCounter(current + 1, labels.length),
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textSecondary,
            ),
          ),
        ],
        // The other phases stay in the tree as labelled nodes when they are
        // not shown, so assistive technology still reads the full list.
        if (narrow)
          for (var i = 0; i < labels.length; i++)
            if (i != current)
              Semantics(
                identifier: 'onboarding-phase-$i',
                label: labels[i],
                child: const SizedBox.shrink(),
              ),
      ],
    );
  }

  Widget _phaseNode(int i) {
    final isCurrent = i == current;
    final name = Text(
      labels[i].toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: WpTypography.small - 1,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w600,
        color: isCurrent
            ? WpColors.textPrimary
            : i < current
            ? WpColors.textSecondary
            : WpColors.textMuted,
      ),
    );
    return Semantics(
      identifier: 'onboarding-phase-$i',
      label: labels[i],
      selected: isCurrent,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i < current)
              Icon(
                LucideIcons.check,
                size: WpIconSize.sm,
                color: WpColors.textSecondary,
              ),
            if (i < current) const SizedBox(width: WpSpacing.xxs),
            // The active phase: bold and white with a cyan underline (Q2).
            if (isCurrent)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: WpColors.action, width: 2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
                  child: name,
                ),
              )
            else
              Flexible(child: name),
          ],
        ),
      ),
    );
  }
}
