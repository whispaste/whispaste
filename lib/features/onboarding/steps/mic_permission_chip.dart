/// Ambient microphone permission status chip, shown beside the guided test
/// recording on the final onboarding page.
///
/// Replaces the old full-screen `MicrophoneStep` probe: this chip only
/// answers "may WhisPaste use the microphone?" by consuming
/// [MicPermissionNotifier] — no live audio, no waveform, no device picker
/// (the device choice lives in Settings → Recording). The "does it actually
/// work?" question is answered right next to it, by the test recording.
///
/// It sat on page 1 until the third redesign round: a permission status has
/// nothing to say on a page that neither records nor asks for one, and the
/// chip put the word "microphone" in front of the user before the product
/// had been introduced.
///
/// One platform-independent vocabulary, three states:
///   ready (granted) / pending (unknown or requesting) / action needed
///   (denied). A fresh install must never read "action needed" before the
///   first request — `unknown` maps to pending by design.
///
/// Tapping ALWAYS calls [MicPermissionNotifier.request]: the notifier itself
/// decides between the one-time OS dialog and the Settings deep-link + poll
/// recovery path, so the widget carries no denied-handling of its own.
///
/// Hidden entirely on Linux: there is no Settings deep-link there, and the
/// chip must not promise an action the platform cannot deliver.
///
/// **Deliberate exception to the 48-px hit-target floor** (`DESIGN.md`,
/// "All interactive elements meet the 48px minimum touch target"): the pill
/// comes to ~30 px (`WpSpacing.xxs` top and bottom around a body-size label).
/// That 30 px is not a free choice: the chip sits in one `Wrap` row beside
/// [HotkeyDisplay] on Try & Go, and [HotkeyDisplay]'s key caps are built from
/// exactly the same two values (`WpTypography.body` over `WpSpacing.xxs`).
/// The row used to stack three different heights — an 18 px caption, 30 px
/// caps and a 38 px pill — which is why it read as three things that happened
/// to be adjacent rather than as one status line. Matching the caps is the
/// whole point; changing either padding value in isolation re-opens the gap.
/// The same reasoning that sanctions the status-bar theme toggle (36×32,
/// `lib/app.dart`) and the trigger-list remove button (28×28,
/// `replacements_page.dart`) applies here — this is a one-off control in a
/// one-off flow, not a row action a user hits repeatedly, and the 48-px rule
/// exists for the latter. `WpButton`'s `dense` size (32 px, hit target equal
/// to its visual box) is the established precedent for exactly this shape.
/// Growth is not free either: the chip shares its `Wrap` row with the hotkey
/// caps on Try & Go, the tallest page of the flow (519 of the fixed window's
/// 551 px in German), so 14 px of pill would come straight out of a budget
/// measured page by page in `onboarding_overlay_test.dart`. This does not
/// trip
/// `test/widgets/wp_row_action_squeezed_icon_button_guard_test.dart` — the
/// chip is an `InkWell`, never an `IconButton` with hand-set constraints, so
/// it is out of that guard's scope by construction and needs no allowlist
/// entry.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/permissions/mic_permission_notifier.dart';

class MicPermissionChip extends ConsumerStatefulWidget {
  const MicPermissionChip({super.key});

  @override
  ConsumerState<MicPermissionChip> createState() => _MicPermissionChipState();
}

class _MicPermissionChipState extends ConsumerState<MicPermissionChip> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // Side-effect-free status read only — never request() on appear. The OS
    // permission dialog fires either on an explicit tap or when *leaving*
    // page 1 (shell-owned, see `_goNext` in onboarding_overlay.dart), long
    // before this chip mounts; firing it on appear would drop a modal on top
    // of the page the user is meant to record on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (defaultTargetPlatform == TargetPlatform.linux) return;
      unawaited(ref.read(micPermissionNotifierProvider.notifier).check());
    });
  }

  @override
  Widget build(BuildContext context) {
    // No chip on Linux — the status alone would work, but the tap promises
    // a recovery action (Settings deep-link) that does not exist there.
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context);
    final status = ref.watch(micPermissionNotifierProvider).status;

    // Ticket 15: the card material, in its pre-composited spelling. See
    // [_PermissionStatusCard] in `auto_paste_step.dart` for why onboarding
    // takes `floatingSurface` rather than the translucent `cardFill` the rest
    // of the app uses — the flow paints its own opaque ground, and a 3–5 %
    // tint over near-black is a rounding error, not a frost. Retires a
    // hand-rolled `withValues(alpha: 0.55)` the tint ladder forbids at a call
    // site.
    const surface = WpColors.floatingSurface;
    const hover = WpColors.hover;
    const border = WpColors.borderSubtle;
    const textPrimary = WpColors.textPrimary;

    // Status is carried by the tinted leading glyph and the copy — the pill
    // itself stays neutral (same quiet register as the Auto-Paste indicator).
    final (String label, IconData? icon, Color statusColor) = switch (status) {
      // Accent, not `success` (Ticket 15, *The Earned-Green Rule*). A granted
      // microphone permission is a state at rest: it is still granted the next
      // time the page is opened, and it was very likely granted by an OS
      // dialog the user answered on the way *out* of page 1. Green is what the
      // app has left for "that worked just now"; a permission that is simply
      // in order is the succeeding-flow register, which is accent.
      MicPermissionStatus.granted => (
        l10n.onboardingMicChipReady,
        LucideIcons.circleCheck,
        WpColors.accent,
      ),
      MicPermissionStatus.denied => (
        l10n.onboardingMicChipAction,
        LucideIcons.shieldAlert,
        WpColors.warning,
      ),
      // unknown & requesting both read "pending": a fresh install has simply
      // not been asked yet and must never claim "action needed".
      //
      // Muted, since Ticket 15 moved `granted` off green and onto the accent:
      // pending held the accent, and two of three states wearing one hue is a
      // status chip that no longer reports status at a glance. Neutral is also
      // the more honest of the two — pending is the state in which *nothing
      // has happened yet*, and the pill's own affordance, not the glyph's hue,
      // is what says it can be tapped.
      MicPermissionStatus.unknown || MicPermissionStatus.requesting => (
        l10n.onboardingMicChipPending,
        status == MicPermissionStatus.requesting ? null : LucideIcons.mic,
        WpColors.textMuted,
      ),
    };

    // `MergeSemantics` + a label-less `Semantics`, the same idiom the theme
    // swatches and the welcome beats use: the `Text` below already carries
    // the chip's label, so spelling it out here as well announced it twice.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            // Always request() — the notifier alone decides between the real
            // one-time OS dialog and the Settings deep-link + poll recovery.
            onTap: () => unawaited(
              ref.read(micPermissionNotifierProvider.notifier).request(),
            ),
            borderRadius: WpRadius.borderFull,
            onHover: (hovering) => setState(() => _hovered = hovering),
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              // Same trailing-slot height as the key caps it stands next to.
              constraints: const BoxConstraints(
                minHeight: WpLayout.denseControlHeight,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: _hovered ? hover : surface,
                borderRadius: WpRadius.borderFull,
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: WpMotion.durationFor(context, WpMotion.fast),
                    child: icon == null
                        ? SizedBox(
                            key: const ValueKey('micChipSpinner'),
                            width: WpIconSize.sm,
                            height: WpIconSize.sm,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: statusColor,
                            ),
                          )
                        : Icon(
                            icon,
                            key: ValueKey(icon),
                            size: WpIconSize.sm,
                            color: statusColor,
                          ),
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: WpTypography.body,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
