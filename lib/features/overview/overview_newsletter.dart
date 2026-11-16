/// The newsletter sign-up inside "Mitmachen": a [WpCard] like the other
/// Übersicht cards, with an address field, the consent checkbox with the
/// versioned wording, the privacy link and "Anmelden".
///
/// Double opt-in: a successful send only means the confirmation mail is on
/// its way, and the form says exactly that. The address stays in the field
/// until it is sent and is cleared afterwards; the app never stores it.
/// Request and answer rules live in `newsletter_logic.dart`.
///
/// While the confirmation is pending the card keeps saying so, also after a
/// restart, and asks whether it was confirmed when it shows and whenever the
/// window gets the focus back (the link back from the confirmation page asks
/// as well, see service_bootstrap.dart). Once confirmed it shows the date.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/accessibility/announce.dart';
import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/newsletter/newsletter_logic.dart';
import '../../services/newsletter/newsletter_service.dart';
import '../../widgets/external_link.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_consent_checkbox.dart';
import '../../widgets/wp_control_row.dart';
import '../../widgets/wp_error_notice.dart';
import '../../widgets/wp_text_field.dart';
import '../../widgets/wp_text_link.dart';

class OverviewNewsletterSignup extends ConsumerStatefulWidget {
  const OverviewNewsletterSignup({super.key});

  @override
  ConsumerState<OverviewNewsletterSignup> createState() =>
      _OverviewNewsletterSignupState();
}

class _OverviewNewsletterSignupState
    extends ConsumerState<OverviewNewsletterSignup>
    with WindowListener {
  final TextEditingController _email = TextEditingController();
  DateTime _shownAt = clock.now();
  bool _consent = false;
  bool _sending = false;

  /// The sign-up ran out of time without a confirmation (a calm note, not an error).
  bool _lapsed = false;

  /// The answer of the last attempt; null before the first one and after
  /// the address was edited.
  NewsletterOutcome? _outcome;

  /// "Weitere Adresse anmelden" was chosen: the form shows even though a
  /// sign-up is pending or confirmed.
  bool _showForm = false;

  bool get _canSend => !_sending && _consent && _email.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // The card showing is one of the moments to ask (the rules decide).
    WidgetsBinding.instance.addPostFrameCallback((_) => _askStatus());
  }

  @override
  void onWindowFocus() => _askStatus();

  void _askStatus() {
    if (!mounted) return;
    unawaited(ref.read(newsletterSignupProvider.notifier).ask());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final l10n = L10n.of(context);
    final email = _email.text.trim();
    if (!looksLikeNewsletterEmail(email)) {
      _show(NewsletterOutcome.invalidEmail, l10n);
      return;
    }
    setState(() {
      _sending = true;
      _lapsed = false;
    });
    // Sent too early, the server would drop the form as automated: wait the
    // rest of the fill-in bar, the button shows the sending state meanwhile.
    final wait = newsletterSendDelay(shownAt: _shownAt, now: clock.now());
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
      if (!mounted) return;
    }
    final statusSecret = newNewsletterStatusSecret();
    final outcome = await ref
        .read(newsletterSubscriberProvider)
        .subscribe(
          email: email,
          languageCode: Localizations.localeOf(context).languageCode,
          elapsedMs: newsletterElapsedMs(shownAt: _shownAt, now: clock.now()),
          statusSecret: statusSecret,
        );
    if (!mounted) return;
    if (outcome == NewsletterOutcome.accepted) {
      _email.clear();
      _consent = false;
      _showForm = false;
      await ref.read(newsletterSignupProvider.notifier).sent(statusSecret);
      if (!mounted) return;
    }
    _sending = false;
    _show(outcome, l10n);
  }

  void _show(NewsletterOutcome outcome, L10n l10n) {
    setState(() => _outcome = outcome);
    final (cause, nextStep) = _texts(l10n, outcome);
    announce(
      View.of(context),
      nextStep == null ? cause : '$cause $nextStep',
      Directionality.of(context),
    );
  }

  /// Back to an empty form for another address.
  void _again() => setState(() {
    _lapsed = false;
    _outcome = null;
    _showForm = true;
    _shownAt = clock.now();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // The confirmation usually arrives while the user looks elsewhere (the
    // link back, window focus): say it once it is known.
    ref.listen(newsletterSignupProvider, (previous, next) {
      // A sign-up that waited for its link and now has neither a link nor a
      // confirmation ran out of time: say so calmly, it is not an error.
      final before = previous?.value;
      final after = next.value;
      if (before != null &&
          after != null &&
          before.statusSecret != null &&
          after.statusSecret == null &&
          after.confirmedAt == before.confirmedAt) {
        setState(() => _lapsed = true);
      }
      final confirmedAt = next.value?.confirmedAt;
      if (confirmedAt != null && previous?.value?.confirmedAt != confirmedAt) {
        announce(
          View.of(context),
          _confirmedText(l10n, confirmedAt),
          Directionality.of(context),
        );
      }
    });
    return WpCard(
      key: const ValueKey('overview-newsletter'),
      title: l10n.overviewNewsletterTitle,
      titleTestId: 'overview-newsletter-title',
      // Decorative, like a mark beside the title; the title says it all.
      trailing: ExcludeSemantics(
        child: Icon(
          LucideIcons.mail,
          size: WpIconSize.md,
          color: WpColors.textMuted,
        ),
      ),
      child: _body(l10n),
    );
  }

  String _confirmedText(L10n l10n, DateTime confirmedAt) =>
      l10n.overviewNewsletterConfirmed(
        DateFormat.yMMMMd(
          Localizations.localeOf(context).toString(),
        ).format(confirmedAt),
      );

  Widget _body(L10n l10n) {
    final signup =
        ref.watch(newsletterSignupProvider).value ?? NewsletterSignup.none;
    final confirmedAt = signup.confirmedAt;
    final pending =
        signup.isPending(clock.now()) ||
        _outcome == NewsletterOutcome.accepted && confirmedAt == null;
    if (!_showForm && !pending && confirmedAt != null) {
      return Semantics(
        identifier: 'overview-newsletter-confirmed',
        child: WpBanner(
          tone: WpBannerTone.info,
          message: _confirmedText(l10n, confirmedAt),
          action: WpTextLink(
            testID: 'overview-newsletter-again',
            label: l10n.overviewNewsletterAgain,
            onPressed: _again,
          ),
        ),
      );
    }
    if (!_showForm && pending) {
      return Semantics(
        identifier: 'overview-newsletter-sent',
        child: WpBanner(
          tone: WpBannerTone.info,
          message: l10n.overviewNewsletterSent,
          action: WpTextLink(
            testID: 'overview-newsletter-again',
            label: l10n.overviewNewsletterAgain,
            onPressed: _again,
          ),
        ),
      );
    }
    final outcome = _outcome;
    final languageCode = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lapsed) ...[
          Semantics(
            identifier: 'overview-newsletter-lapsed',
            liveRegion: true,
            child: WpBanner(
              tone: WpBannerTone.info,
              message: l10n.overviewNewsletterLapsed,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        Text(l10n.overviewNewsletterBenefit, style: WpTextStyles.rowNote),
        const SizedBox(height: WpSpacing.sm),
        WpControlRow(
          children: [
            Expanded(
              child: Semantics(
                identifier: 'overview-newsletter-email',
                child: WpTextField(
                  key: const ValueKey('overview-newsletter-email'),
                  controller: _email,
                  variant: WpTextFieldVariant.form,
                  hintText: l10n.overviewNewsletterEmailHint,
                  semanticsLabel: l10n.overviewNewsletterEmailLabel,
                  keyboardType: TextInputType.emailAddress,
                  // An address is never a word the dictionary should
                  // second-guess.
                  autocorrect: false,
                  // The longest valid address. A limit, not a readout: a
                  // visible counter would make the field taller than the
                  // button beside it.
                  inputFormatters: [LengthLimitingTextInputFormatter(254)],
                  onChanged: (_) => setState(() => _outcome = null),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            WpButton(
              testId: 'overview-newsletter-submit',
              label: l10n.overviewNewsletterSubmit,
              variant: WpButtonVariant.primary,
              isLoading: _sending,
              onPressed: _canSend ? _send : null,
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.sm),
        Semantics(
          identifier: 'overview-newsletter-consent',
          child: WpConsentCheckbox(
            key: const ValueKey('overview-newsletter-consent'),
            value: _consent,
            // The versioned wording (kNewsletterConsentVersion), unchanged.
            label: l10n.newsletterConsent,
            explanation: l10n.overviewNewsletterDoubleOptIn,
            onChanged: (value) => setState(() => _consent = value),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: WpTextLink(
            testID: 'overview-newsletter-privacy',
            label: l10n.overviewNewsletterPrivacy,
            kind: WpLinkKind.web,
            onPressed: () =>
                openExternalUrl(context, newsletterPrivacyUrl(languageCode)),
          ),
        ),
        if (outcome != null) ...[
          const SizedBox(height: WpSpacing.sm),
          Semantics(
            identifier: 'overview-newsletter-error',
            child: Builder(
              builder: (context) {
                final (cause, nextStep) = _texts(l10n, outcome);
                return WpErrorNotice(cause: cause, nextStep: nextStep);
              },
            ),
          ),
        ],
      ],
    );
  }
}

(String, String?) _texts(L10n l10n, NewsletterOutcome outcome) =>
    switch (outcome) {
      NewsletterOutcome.accepted => (l10n.overviewNewsletterSent, null),
      NewsletterOutcome.invalidEmail => (
        l10n.overviewNewsletterInvalid,
        l10n.overviewNewsletterInvalidNext,
      ),
      NewsletterOutcome.tooManyAttempts => (
        l10n.overviewNewsletterTooMany,
        l10n.overviewNewsletterLater,
      ),
      NewsletterOutcome.offline => (
        l10n.overviewNewsletterOffline,
        l10n.overviewNewsletterOfflineNext,
      ),
      NewsletterOutcome.outdatedApp => (
        l10n.overviewNewsletterOutdated,
        l10n.overviewNewsletterOutdatedNext,
      ),
      NewsletterOutcome.unavailable => (
        l10n.overviewNewsletterUnavailable,
        l10n.overviewNewsletterLater,
      ),
    };
