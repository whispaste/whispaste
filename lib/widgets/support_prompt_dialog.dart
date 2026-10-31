/// Support prompt dialog — surfaces a support/sponsor nudge, fully
/// independent of the rating ask (own provider, own watcher, own dismissal
/// semantics).
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
import '../core/navigation/help_target.dart';
import '../core/navigation/page_state.dart';
import '../services/nudge_gate.dart';
import '../services/prompt_display_arbiter.dart';
import '../services/prompt_timing.dart';
import '../services/support/support_capabilities.dart';
import '../services/support/support_state.dart';
import '../services/support_prompt_service.dart';
import '../services/telemetry_service.dart';
import 'dialog.dart';
import 'support_purchase_sheet.dart';

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
    final actions = offeredPromptActions(
      asks: ref.read(supportCapabilitiesProvider),
      coffee: ref.read(coffeeSupportTargetProvider),
      buyMeACoffeeFirst:
          ref.read(coffeeBuyMeACoffeeFirstProvider).value ?? false,
      kind: kind,
    );
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

    try {
      if (!context.mounted) return;
      final l10n = L10n.of(context);
      final isRecurringFollowUp = kind == SupportPromptKind.recurringFollowUp;
      final closed = showWpDialog<WpSupportPromptAction>(
        context: context,
        title: isRecurringFollowUp
            ? l10n.supportPromptRecurringTitle
            : l10n.aboutSupportTitle,
        content: Text(
          isRecurringFollowUp
              ? l10n.supportPromptRecurringDescription
              : l10n.aboutSupportDescription,
        ),
        actions: [
          for (final action in actions)
            WpDialogAction(
              label: _supportPromptLabel(l10n, action),
              testId: action.testId,
              role: WpDialogActionRole.alternative,
              value: action,
            ),
          WpDialogAction(
            label: l10n.supportPromptSnooze,
            testId: WpSupportPromptAction.dismiss.testId,
            role: WpDialogActionRole.cancel,
            value: WpSupportPromptAction.dismiss,
          ),
        ],
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
      final chosen = await closed;
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
    WpSupportPromptAction? action, {
    required bool closedByHotkey,
    required SupportPromptNotifier notifier,
    required TelemetryService telemetry,
  }) async {
    switch (action) {
      case null when closedByHotkey:
        notifier.cancelPresentation();
      case null || WpSupportPromptAction.dismiss:
        recordSupportEvent(telemetry, SupportTelemetryEvent.promptDismissed);
        await notifier.dismiss();
      case WpSupportPromptAction.coffeeStore:
        // The store sheet takes over from the prompt, so the prompt counts as
        // closed (snooze), like the dismiss button does.
        await notifier.dismiss();
        if (mounted) await showWpSupportPurchaseDialog(context);
      case WpSupportPromptAction.gitHubSponsors:
        await _openLink(
          kGitHubSponsorsUrl,
          target: 'github',
          notifier: notifier,
          telemetry: telemetry,
        );
      case WpSupportPromptAction.kofi:
        await _openLink(
          kKofiUrl,
          target: 'kofi',
          coffee: true,
          notifier: notifier,
          telemetry: telemetry,
        );
      case WpSupportPromptAction.buyMeACoffee:
        await _openLink(
          kBuyMeACoffeeUrl,
          target: 'buymeacoffee',
          coffee: true,
          notifier: notifier,
          telemetry: telemetry,
        );
      case WpSupportPromptAction.moreWays:
        // Leaves the prompt for the Support tab, which counts as a snooze like
        // the close button. The tab itself lists every other way.
        await notifier.dismiss();
        if (mounted) _openSupportTab();
      case WpSupportPromptAction.paypal:
        await _openLink(
          kPayPalUrl,
          target: 'paypal',
          notifier: notifier,
          telemetry: telemetry,
        );
    }
  }

  /// Opens Help › Unterstützen (the Support tab).
  void _openSupportTab() {
    ref
        .read(helpTargetProvider.notifier)
        .set(const HelpTarget(tab: HelpTab.support));
    ref.read(activePageProvider.notifier).setPage('help');
  }

  /// Records the link only after the browser launch succeeded. A failed
  /// launch shows the address in a toast (UIA-FBK-08) and counts as a
  /// dismissal, so the prompt does not come back at once.
  Future<void> _openLink(
    String url, {
    required String target,
    required SupportPromptNotifier notifier,
    required TelemetryService telemetry,
    bool coffee = false,
  }) async {
    if (await openExternalUrl(context, url)) {
      recordLinkOpened(telemetry, SupportLinkSurface.prompt, target);
      // A coffee page starts the quiet period but never the monthly follow-up.
      if (coffee) {
        await notifier.markCoffeeLinkOpened();
      } else {
        await notifier.markLinkOpened();
      }
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

/// Offered actions in display order (pure, so every prompt kind is testable).
/// The automatic prompt offers the coffee pair in the drawn order plus "Weitere
/// Wege" (GR-024, GR-025). The recurring follow-up keeps its monthly route.
List<WpSupportPromptAction> offeredPromptActions({
  required List<SupportAsk> asks,
  required CoffeeSupportTarget coffee,
  required bool buyMeACoffeeFirst,
  required SupportPromptKind kind,
}) {
  final store = [
    if (coffee == CoffeeSupportTarget.storePurchase)
      WpSupportPromptAction.coffeeStore,
  ];
  final pair = !asks.contains(SupportAsk.kofi)
      ? const <WpSupportPromptAction>[]
      : buyMeACoffeeFirst
      ? const [WpSupportPromptAction.buyMeACoffee, WpSupportPromptAction.kofi]
      : const [WpSupportPromptAction.kofi, WpSupportPromptAction.buyMeACoffee];
  if (kind == SupportPromptKind.recurringFollowUp) {
    return [
      ...store,
      ...pair,
      if (asks.contains(SupportAsk.githubSponsors))
        WpSupportPromptAction.gitHubSponsors,
      if (asks.contains(SupportAsk.paypal)) WpSupportPromptAction.paypal,
    ];
  }
  return [...store, ...pair, WpSupportPromptAction.moreWays];
}

// ---------------------------------------------------------------------------
// Action enum
// ---------------------------------------------------------------------------

enum WpSupportPromptAction {
  coffeeStore('support-prompt-coffee-button'),
  gitHubSponsors('supportPromptGitHubButton'),
  kofi('supportPromptKofiButton'),
  buyMeACoffee('supportPromptBuyMeACoffeeButton'),
  paypal('supportPromptPayPalButton'),
  moreWays('supportPromptMoreWaysButton'),
  dismiss('supportPromptSnoozeButton');

  const WpSupportPromptAction(this.testId);

  final String testId;
}

/// Button text for each offered action.
String _supportPromptLabel(L10n l10n, WpSupportPromptAction action) =>
    switch (action) {
      WpSupportPromptAction.gitHubSponsors => l10n.aboutGitHubSponsors,
      WpSupportPromptAction.coffeeStore => l10n.coffeeButtonLabel,
      WpSupportPromptAction.kofi => l10n.aboutKofi,
      WpSupportPromptAction.moreWays => l10n.supportSectionOthers,
      WpSupportPromptAction.buyMeACoffee => l10n.coffeeBuyMeACoffeeLabel,
      WpSupportPromptAction.paypal => l10n.supportPayPalLabel,
      WpSupportPromptAction.dismiss => l10n.supportPromptSnooze,
    };
