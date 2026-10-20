/// Support prompt dialog — surfaces a support/sponsor nudge mirroring the
/// structure of `review_prompt_dialog.dart`, but fully independent of it
/// (own provider, own watcher, own dismissal semantics).
///
/// The offered links follow [supportCapabilities] for this build, so the Mac
/// App Store build never shows an external payment link (guideline 3.1.1).
/// Every close path (button, Escape, click outside) ends in one resolution
/// step: a link launch records its link only after the launch succeeded, the
/// snooze button and the outside/Escape close both start the 90-day snooze,
/// and a hotkey press cancels without recording anything.
library;

import 'dart:async';

import 'external_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_urls.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/nudge_gate.dart';
import '../services/prompt_display_arbiter.dart';
import '../services/prompt_timing.dart';
import '../services/support/support_capabilities.dart';
import '../services/support/support_state.dart';
import '../services/support_prompt_service.dart';
import '../services/telemetry_service.dart';
import 'wp_button.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Listens to [supportPromptProvider] and shows the support dialog when
/// [SupportPromptState.shouldShowPrompt] becomes `true`.
///
/// Place this widget anywhere in the widget tree — it renders no visible UI
/// of its own and waits [kPostRecordingPromptDelay] before showing, so it
/// never interrupts a recording's completion moment.
class WpSupportPromptWatcher extends ConsumerStatefulWidget {
  const WpSupportPromptWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpSupportPromptWatcher> createState() =>
      _WpSupportPromptWatcherState();
}

class _WpSupportPromptWatcherState
    extends ConsumerState<WpSupportPromptWatcher> {
  Timer? _delay;
  bool _dialogShowing = false;

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  void _maybeShow(SupportPromptState state, BuildContext context) {
    if (!state.shouldShowPrompt || _dialogShowing) return;
    _dialogShowing = true;
    _delay = Timer(kPostRecordingPromptDelay, () {
      if (!mounted) {
        _dialogShowing = false;
        return;
      }
      // Central nudge gate (R-11): no dictation running, 30 s idle in the app.
      unawaited(
        ref.read(nudgeGateProvider).whenAllowed().then((_) {
          if (!mounted || !context.mounted) {
            _dialogShowing = false;
            return;
          }
          unawaited(_present(context, state.kind));
        }),
      );
    });
  }

  /// Claims the shared display window, shows the dialog, and resolves it.
  /// The impression is counted only once the dialog is on screen.
  Future<void> _present(BuildContext context, SupportPromptKind kind) async {
    final notifier = ref.read(supportPromptProvider.notifier);
    final arbiter = ref.read(promptDisplayArbiterProvider);
    final telemetry = ref.read(telemetryProvider);
    final actions = _offeredActions(ref.read(supportCapabilitiesProvider));
    final barrierLabel = MaterialLocalizations.of(
      context,
    ).modalBarrierDismissLabel;
    final transitionDuration = WpMotion.durationFor(context, WpMotion.smooth);
    var closedByHotkey = false;

    final claimed = arbiter.tryClaim(
      PromptOwner.support,
      close: () {
        closedByHotkey = true;
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      },
    );
    if (!claimed || actions.isEmpty) {
      notifier.cancelPresentation();
      _dialogShowing = false;
      return;
    }

    _SupportAction? chosen;
    try {
      if (!context.mounted) return;
      final closed = showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: barrierLabel,
        barrierColor: Colors.transparent,
        transitionDuration: transitionDuration,
        pageBuilder: (_, _, _) => const SizedBox.shrink(),
        transitionBuilder: (ctx, animation, _, _) {
          final opacity = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );

          return FadeTransition(
            opacity: opacity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: wpDialogBarrierColor()),
                ),
                _SupportPromptDialog(
                  animation: animation,
                  kind: kind,
                  actions: actions,
                  onResult: (action) {
                    chosen = action;
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          );
        },
      );
      // Count the impression only once the dialog is painted (UIA-FBK-09): a
      // prompt that never reaches the screen must not use up the 3-impression cap.
      unawaited(
        WidgetsBinding.instance.endOfFrame.then((_) async {
          await notifier.markPresented();
          recordSupportEvent(
            telemetry,
            SupportTelemetryEvent.promptShown,
            name: kind.name,
          );
        }),
      );
      await closed;
      await _resolve(
        chosen,
        closedByHotkey: closedByHotkey,
        notifier: notifier,
        telemetry: telemetry,
      );
    } finally {
      arbiter.release(PromptOwner.support);
      _dialogShowing = false;
    }
  }

  /// The single resolution step for every close path.
  Future<void> _resolve(
    _SupportAction? action, {
    required bool closedByHotkey,
    required SupportPromptNotifier notifier,
    required TelemetryService telemetry,
  }) async {
    switch (action) {
      case null when closedByHotkey:
        notifier.cancelPresentation();
      case null || _SupportAction.dismiss:
        recordSupportEvent(telemetry, SupportTelemetryEvent.promptDismissed);
        await notifier.dismiss();
      case _SupportAction.gitHubSponsors:
        await _openLink(
          kGitHubSponsorsUrl,
          target: 'github',
          notifier: notifier,
          telemetry: telemetry,
        );
      case _SupportAction.kofi:
        await _openLink(
          kKofiUrl,
          target: 'kofi',
          notifier: notifier,
          telemetry: telemetry,
        );
      case _SupportAction.paypal:
        await _openLink(
          kPayPalUrl,
          target: 'paypal',
          notifier: notifier,
          telemetry: telemetry,
        );
    }
  }

  /// Records the link only after the browser launch succeeded. A failed
  /// launch shows the address in a toast (UIA-FBK-08) and counts as a
  /// dismissal, so the prompt does not come back at once.
  Future<void> _openLink(
    String url, {
    required String target,
    required SupportPromptNotifier notifier,
    required TelemetryService telemetry,
  }) async {
    if (await openExternalUrl(context, url)) {
      recordSupportEvent(
        telemetry,
        SupportTelemetryEvent.linkOpened,
        name: target,
      );
      await notifier.markLinkOpened();
    } else {
      await notifier.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SupportPromptState>(supportPromptProvider, (_, next) {
      _maybeShow(next, context);
    });
    return widget.child;
  }
}

/// Offered actions in display order. Only links the build allows appear.
List<_SupportAction> _offeredActions(List<SupportAsk> asks) => [
  if (asks.contains(SupportAsk.githubSponsors)) _SupportAction.gitHubSponsors,
  if (asks.contains(SupportAsk.kofi)) _SupportAction.kofi,
  if (asks.contains(SupportAsk.paypal)) _SupportAction.paypal,
];

// ---------------------------------------------------------------------------
// Action enum
// ---------------------------------------------------------------------------

enum _SupportAction {
  gitHubSponsors('supportPromptGitHubButton'),
  kofi('supportPromptKofiButton'),
  paypal('supportPromptPayPalButton'),
  dismiss('supportPromptSnoozeButton');

  const _SupportAction(this.testId);

  final String testId;
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _SupportPromptDialog extends StatelessWidget {
  const _SupportPromptDialog({
    required this.animation,
    required this.kind,
    required this.actions,
    required this.onResult,
  });

  final Animation<double> animation;
  final SupportPromptKind kind;
  final List<_SupportAction> actions;
  final void Function(_SupportAction) onResult;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isRecurringFollowUp = kind == SupportPromptKind.recurringFollowUp;
    final title = isRecurringFollowUp
        ? l10n.supportPromptRecurringTitle
        : l10n.aboutSupportTitle;
    final description = isRecurringFollowUp
        ? l10n.supportPromptRecurringDescription
        : l10n.aboutSupportDescription;

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(WpSpacing.lg),
            decoration: BoxDecoration(
              color: WpColors.surfaceElevated,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: WpColors.borderSubtle),
              boxShadow: WpShadows.elevated,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: WpColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0) const SizedBox(height: WpSpacing.xs),
                  WpButton(
                    key: ValueKey(action.testId),
                    label: _label(l10n, action),
                    variant: index == 0
                        ? WpButtonVariant.primary
                        : WpButtonVariant.secondary,
                    onPressed: () => onResult(action),
                  ),
                ],
                const SizedBox(height: WpSpacing.sm),
                WpButton(
                  key: ValueKey(_SupportAction.dismiss.testId),
                  label: l10n.supportPromptSnooze,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  // Focus starts on "later": Enter must not open a browser (UIA-FBK-01).
                  autofocus: true,
                  onPressed: () => onResult(_SupportAction.dismiss),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _label(L10n l10n, _SupportAction action) => switch (action) {
    _SupportAction.gitHubSponsors => l10n.aboutGitHubSponsors,
    _SupportAction.kofi => l10n.aboutKofi,
    _SupportAction.paypal => l10n.supportPayPalLabel,
    _SupportAction.dismiss => l10n.supportPromptSnooze,
  };
}
