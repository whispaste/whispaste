import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../../core/app_info.dart';
import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/feedback_submission_service.dart';
import '../../services/shared_prefs_safe_read.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../widgets/wp_focus_ring.dart';
import '../../widgets/wp_text_field.dart';

/// Supabase URL — injected at build time via `--dart-define`.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');

/// Supabase publishable key — injected at build time via `--dart-define`.
/// Public key (replaces legacy anon key), safe for client-side use.
/// RLS enforces all access control server-side.
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: '',
);

/// Override for testing. When non-null, the Thank-You-View review CTAs use
/// this value instead of [Platform.isWindows] to decide whether the
/// Store-Review button is shown alongside the GitHub-Stern button.
@visibleForTesting
bool? feedbackPlatformIsWindowsOverride;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Computes a stable 12-character hex device identifier hash from [hostname].
///
/// The result is always exactly 12 lowercase hex characters — matching the
/// `length(device_id_hash) = 12` constraint in the RLS policy.
/// Exposed via [visibleForTesting] so unit tests can verify the hash logic
/// without going through the full widget submit flow.
@visibleForTesting
String computeFeedbackDeviceIdHash(String hostname) {
  final bytes = utf8.encode('${hostname}_whispaste');
  return md5.convert(bytes).toString().substring(0, 12);
}

/// Invisible slack a [WpFilterChip] carries above and below its pill.
///
/// The chip centres a ~28px pill inside a [WpLayout.minTouchTarget]-tall tap
/// surface, so ~10px of each chip's box is empty on either side of the only
/// part the eye can see. In History's and Notes' filter bars that never shows —
/// nothing is aligned across those rows. On this form it does: measured from
/// the pill, the category label sat 26px above its chips while every other
/// label on the page sits 16px above its control, and the gap down to the next
/// section came out 10px wider than every other section gap.
///
/// So the two gaps bracketing the chip row are stated one `xs` step short, and
/// the chip's own slack fills that step back in. One rung of the spacing scale
/// rather than a hand-measured number: measured from the pill it lands at 18px
/// against the form's 16px at the default text size, and hits it exactly at
/// around 1.35× — beyond that the pill keeps growing into its tap surface, the
/// slack keeps shrinking, and the gap runs slightly tighter than the rest of
/// the form rather than looser. Tight is the harmless direction here: the
/// label stays bound to the control it names.
const _chipRowSlack = WpSpacing.xs;

const _kLastFeedbackKey = 'feedback_last_submitted_ms';
const _kClientRateLimitHours = 24;

/// Mirrors the server-side CHECK constraint on `user_feedback.contact_email`
/// (`supabase/migrations/20260717_add_feedback_contact_email.sql`) — a
/// deliberately loose format check, not full RFC validation. Client-side
/// only blocks obvious typos; the server is the source of truth.
final _emailFormat = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

@visibleForTesting
bool isValidFeedbackContactEmail(String value) => _emailFormat.hasMatch(value);

/// Returns true if the user has submitted feedback within the last 24 hours.
/// Prevents unnecessary network calls before the server-side check.
Future<bool> _isClientRateLimited() async {
  final prefs = await SharedPreferences.getInstance();
  // Safe read: this key can be a bundle-ID-migrated String (see
  // shared_prefs_safe_read.dart).
  final lastMs = readIntPrefSafe(prefs, _kLastFeedbackKey);
  if (lastMs == null) return false;
  final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
  return elapsed < const Duration(hours: _kClientRateLimitHours).inMilliseconds;
}

Future<void> _recordFeedbackSubmission() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastFeedbackKey, DateTime.now().millisecondsSinceEpoch);
}

/// Opens [url] in the external handler (store app or browser). Used by the
/// Thank-You-View review CTAs — URLs come from the single-source
/// `app_urls.dart` constants.
Future<void> _launchExternalUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Feedback page — polished, chat-inspired feedback form.
///
/// Top-aligned, responsive: narrow form column on wide screens with generous
/// padding so it breathes on maximized desktop windows.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this._submissionService});

  final FeedbackSubmissionService? _submissionService;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static final _log = AppLogger('FeedbackPage');

  int _rating = 0;
  String _category = '';
  final _commentController = TextEditingController();
  final _emailController = TextEditingController();
  String? _contactLocale;
  bool _submitted = false;
  bool _submitting = false;
  String? _error;

  late final FeedbackSubmissionService _service;

  @override
  void initState() {
    super.initState();
    _service =
        widget._submissionService ??
        FeedbackSubmissionService(
          client: http.Client(),
          supabaseUrl: _supabaseUrl,
          supabasePublishableKey: _supabasePublishableKey,
        );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _rating > 0 &&
      _category.isNotEmpty &&
      _commentController.text.isNotEmpty &&
      (_emailController.text.trim().isEmpty ||
          isValidFeedbackContactEmail(_emailController.text.trim()));

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final l10n = L10n.of(context);

    if (_submitted) {
      final isWindows = feedbackPlatformIsWindowsOverride ?? Platform.isWindows;
      return WpPageShell(
        child: _ThankYouView(ts: ts, onReset: _reset, isWindows: isWindows),
      );
    }

    return WpPageShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Deliberate exception to the full-panel width every other area
          // uses: this page is a form with long free-text fields, and a
          // reading measure keeps those lines legible on wide windows.
          final maxFormWidth = constraints.maxWidth > 720
              ? 560.0
              : double.infinity;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxFormWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // No in-page H1 — the app shell's page header is the one
                  // place the page title is rendered. What stays is the
                  // intro line, which says something the title doesn't.
                  Text(
                    l10n.feedbackSubtitle,
                    style: ts.bodyMedium?.copyWith(
                      color: WpColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: WpSpacing.xxl),

                  _FeedbackCard(
                    children: [
                      // Category selection
                      Text(l10n.feedbackCategoryLabel, style: ts.titleSmall),
                      // `- _chipRowSlack` on both sides of the row: the chips'
                      // tap surfaces are taller than their pills, and the eye
                      // measures from the pill. See [_chipRowSlack].
                      const SizedBox(height: WpSpacing.md - _chipRowSlack),
                      // `WpFilterChip`, not a local chip class: this row picks one
                      // of a set, which is exactly the job History, Notes and the
                      // analytics period selector already use it for. The private
                      // `_CategoryChip` it replaces was the fifth reimplementation
                      // of that widget and repeated the same two defects the
                      // analytics one had — a bare `GestureDetector`, so the
                      // control was unreachable by keyboard, and a `label:` on a
                      // `Semantics` whose child renders the same text, so each chip
                      // announced its name twice. It also hand-mixed its active
                      // border at `accent` 30%, which is the `accentBorder30` rung
                      // spelled out longhand.
                      Wrap(
                        spacing: WpSpacing.sm,
                        // Not `sm` again: horizontally the gap is measured pill to
                        // pill, vertically it would be measured box to box, and
                        // the two boxes bring ~20px of slack between them on their
                        // own. Spelling both tokens the same would have put 32px
                        // between two runs against 12px inside one — and the four
                        // German labels do wrap onto a second run once the OS text
                        // size is turned up. Zero leaves 12px within a run and
                        // ~20px between them: a step up, which is what separates
                        // runs from each other, but a far smaller one than 32.
                        runSpacing: 0,
                        children: [
                          for (final (value, icon, label)
                              in <(String, IconData, String)>[
                                (
                                  'bug',
                                  LucideIcons.bug,
                                  l10n.feedbackCategoryBug,
                                ),
                                (
                                  'feature',
                                  LucideIcons.lightbulb,
                                  l10n.feedbackCategoryFeature,
                                ),
                                (
                                  'general',
                                  LucideIcons.messageCircle,
                                  l10n.feedbackCategoryGeneral,
                                ),
                                (
                                  'ai',
                                  LucideIcons.sparkles,
                                  l10n.feedbackCategoryAiQuality,
                                ),
                              ])
                            WpFilterChip(
                              icon: icon,
                              label: label,
                              isActive: _category == value,
                              onTap: () => setState(() => _category = value),
                            ),
                        ],
                      ),

                      const SizedBox(height: WpSpacing.xxxl - _chipRowSlack),

                      // Emoji rating
                      Text(l10n.feedbackRatingLabel, style: ts.titleSmall),
                      const SizedBox(height: WpSpacing.md),
                      _EmojiRatingRow(
                        rating: _rating,
                        onChanged: (v) => setState(() => _rating = v),
                      ),

                      const SizedBox(height: WpSpacing.xxxl),

                      // Comment field — chat-styled
                      Text(l10n.feedbackCommentsLabel, style: ts.titleSmall),
                      const SizedBox(height: WpSpacing.md),
                      // A form field, so it looks like every other form field —
                      // it used to sit borderless inside a warm-gradient box of
                      // its own, which gave it a third field look *and* no focus
                      // indicator at all.
                      WpTextField(
                        key: const Key('feedbackCommentField'),
                        controller: _commentController,
                        variant: WpTextFieldVariant.form,
                        hintText: _category == 'bug'
                            ? l10n.feedbackPlaceholderBug
                            : _category == 'feature'
                            ? l10n.feedbackPlaceholderFeature
                            : _category == 'ai'
                            ? l10n.feedbackPlaceholderAi
                            : l10n.feedbackPlaceholderGeneral,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 1000,
                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: WpSpacing.xxl),

                      // Optional contact email + preferred reply language
                      _ContactEmailSection(
                        emailController: _emailController,
                        contactLocale: _contactLocale,
                        // The email text lives on the parent's controller and
                        // feeds _canSubmit + the submit payload, so a change
                        // must re-run the parent's build, not just the child's.
                        onEmailChanged: () => setState(() {}),
                        onContactLocaleChanged: (code) =>
                            setState(() => _contactLocale = code),
                      ),
                    ],
                  ),

                  const SizedBox(height: WpSpacing.xxl),

                  // Error message
                  if (_error != null) ...[
                    Text(
                      _errorText(l10n),
                      style: ts.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: WpSpacing.sm),
                  ],

                  // Submit button
                  // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                  WpButton(
                    label: _submitting
                        ? l10n.feedbackSubmitting
                        : l10n.feedbackSubmit,
                    variant: WpButtonVariant.primary,
                    icon: LucideIcons.send,
                    isLoading: _submitting,
                    expanded: true,
                    onPressed: _canSubmit ? _submit : null,
                  ),

                  const SizedBox(height: WpSpacing.lg),

                  // Privacy note
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.lock,
                        size: WpIconSize.xs,
                        color: WpColors.textMuted,
                      ),
                      const SizedBox(width: WpSpacing.xxs),
                      Flexible(
                        child: Text(
                          l10n.feedbackPrivacyNote,
                          textAlign: TextAlign.center,
                          style: ts.bodySmall?.copyWith(
                            color: WpColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: WpSpacing.xxxl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _errorText(L10n l10n) {
    return switch (_error) {
      'rate_limited' => l10n.feedbackErrorRateLimited,
      'network_error' => l10n.feedbackErrorNetwork,
      'not_configured' => l10n.feedbackErrorNotConfigured,
      _ => l10n.feedbackErrorServer,
    };
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Capture locale before the first await to avoid using BuildContext across
    // an async gap (lint: use_build_context_synchronously).
    final locale = Localizations.localeOf(context).languageCode;

    try {
      // Client-side rate limit check — avoids unnecessary network round-trips.
      if (await _isClientRateLimited()) {
        _log.info('Feedback blocked by client-side rate limit (24h cooldown)');
        if (mounted) {
          setState(() {
            _submitting = false;
            _error = 'rate_limited';
          });
        }
        return;
      }

      final email = _emailController.text.trim();
      final payload = FeedbackPayload(
        rating: _rating,
        feedbackText: _commentController.text.trim(),
        category: _category,
        appVersion: appVersion,
        deviceIdHash: _deriveDeviceId(),
        locale: locale,
        contactEmail: email.isEmpty ? null : email,
        contactLocale: email.isEmpty ? null : (_contactLocale ?? locale),
      );

      final result = await _service.submit(payload);

      if (!mounted) return;

      switch (result) {
        case FeedbackSent():
          await _recordFeedbackSubmission();
          setState(() => _submitted = true);
        case FeedbackSkippedNotConfigured():
          setState(() {
            _submitting = false;
            _error = 'not_configured';
          });
        case FeedbackRateLimitedServer():
          setState(() {
            _submitting = false;
            _error = 'rate_limited';
          });
        case FeedbackServerError():
          setState(() {
            _submitting = false;
            _error = 'server_error';
          });
        case FeedbackNetworkError():
          setState(() {
            _submitting = false;
            _error = 'network_error';
          });
      }
    } on Exception catch (e) {
      _log.warning('Feedback submission failed unexpectedly: $e');
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'server_error';
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _submitted = false;
      _submitting = false;
      _error = null;
      _rating = 0;
      _category = '';
      _commentController.clear();
      _emailController.clear();
      _contactLocale = null;
    });
  }

  static String _deriveDeviceId() {
    try {
      return computeFeedbackDeviceIdHash(Platform.localHostname);
    } on Exception {
      return computeFeedbackDeviceIdHash('fallback_device');
    }
  }
}

// ---------------------------------------------------------------------------
// Optional contact email + preferred reply language — extracted out of
// _FeedbackPageState.build to keep its cyclomatic complexity down.
// ---------------------------------------------------------------------------

/// The card the feedback form stands on.
///
/// Same recipe as `_AboutCard` and the settings sections: translucent
/// [WpColors.cardFill] because it sits inside the content panel rather than on
/// its own ground, a [WpColors.cardEdgeHighlight] rim, no shadow (the
/// Depth-Source Rule, `lib/DESIGN.md`).
///
/// One card, not one per group. The four groups inside it — category, rating,
/// comment, contact — are not four things a reader chooses between; they are
/// four questions in a single act, and the act ends at the submit button below
/// the card. Boxing each group would have drawn three boundaries where the
/// form has none, and the submit stays outside because a form's action is what
/// you do *to* the form, not one more field in it.
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.lg),
      decoration: BoxDecoration(
        color: WpColors.cardFill,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: WpColors.cardEdgeHighlight),
      ),
      child: Column(crossAxisAlignment: crossAxisAlignment, children: children),
    );
  }
}

class _ContactEmailSection extends StatelessWidget {
  const _ContactEmailSection({
    required this.emailController,
    required this.contactLocale,
    required this.onEmailChanged,
    required this.onContactLocaleChanged,
  });

  final TextEditingController emailController;
  final String? contactLocale;
  final VoidCallback onEmailChanged;
  final ValueChanged<String> onContactLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final l10n = L10n.of(context);
    final email = emailController.text.trim();
    final showInvalidEmail =
        email.isNotEmpty && !isValidFeedbackContactEmail(email);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.feedbackContactEmailLabel, style: ts.titleSmall),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.feedbackContactEmailExplanation,
          style: ts.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        const SizedBox(height: WpSpacing.sm),
        WpTextField(
          key: const Key('feedbackEmailField'),
          controller: emailController,
          variant: WpTextFieldVariant.form,
          hintText: l10n.feedbackContactEmailPlaceholder,
          // An address is never a word the dictionary should second-guess.
          autocorrect: false,
          onChanged: (_) => onEmailChanged(),
        ),
        if (showInvalidEmail) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.feedbackContactEmailInvalid,
            style: ts.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],

        // Preferred reply language — only relevant once there is a way to
        // reply, so it only appears once an email is given.
        if (email.isNotEmpty) ...[
          const SizedBox(height: WpSpacing.lg),
          Text(l10n.feedbackContactLanguageLabel, style: ts.titleSmall),
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.feedbackContactLanguageHint,
            style: ts.bodySmall?.copyWith(color: WpColors.textSecondary),
          ),
          const SizedBox(height: WpSpacing.sm),
          WpLanguageSelector(
            currentLocale:
                contactLocale ?? Localizations.localeOf(context).languageCode,
            onChanged: onContactLocaleChanged,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Thank-you state — shown after submission
// ---------------------------------------------------------------------------

class _ThankYouView extends StatelessWidget {
  const _ThankYouView({
    required this.ts,
    required this.onReset,
    required this.isWindows,
  });

  final TextTheme ts;
  final VoidCallback onReset;
  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 720 ? 480.0 : double.infinity;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: WpSpacing.xxxl * 1.5),
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: WpColors.accentSubtle,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    LucideIcons.heart,
                    size: WpIconSize.xl,
                    color: WpColors.accent,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxl),
                Text(l10n.feedbackThankYou, style: ts.headlineMedium),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.feedbackThankYouMessage,
                  textAlign: TextAlign.center,
                  style: ts.bodyMedium?.copyWith(color: WpColors.textSecondary),
                ),
                const SizedBox(height: WpSpacing.xxxl),
                // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                WpButton(
                  label: l10n.feedbackSendAnother,
                  variant: WpButtonVariant.secondary,
                  icon: LucideIcons.messageSquarePlus,
                  onPressed: onReset,
                ),
                const SizedBox(height: WpSpacing.xxxl),
                // The one group on this screen that is a bounded offer rather
                // than a sentence addressed to the reader, so it is the one
                // that gets card material. The celebration above it — mark,
                // headline, message, "send another" — is narrative and stands
                // on the page ground, the way the onboarding steps do.
                _FeedbackCard(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [_ReviewSupportCtas(ts: ts, isWindows: isWindows)],
                ),
                const SizedBox(height: WpSpacing.lg),
                // Quietest element on the page, on purpose: the reader just
                // finished giving feedback, so a link to the public ideas
                // board is a natural next step — but it must not compete with
                // the review/support card above it, so it gets no card, no
                // fill, just the ghost variant's plain text-button register.
                // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                WpButton(
                  label: l10n.feedbackIdeasLink,
                  variant: WpButtonVariant.ghost,
                  icon: LucideIcons.lightbulb,
                  onPressed: () => _launchExternalUrl(kVotepitBoardUrl),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Review-CTA section — discrete "Rate & support WhisPaste" actions shown only
// in the Thank-You-View, so they never compete with the feedback submit. URLs
// come from the single-source app_urls.dart constants; l10n keys + button
// language mirror the review-prompt dialog and the settings entry.
// ---------------------------------------------------------------------------

class _ReviewSupportCtas extends StatelessWidget {
  const _ReviewSupportCtas({required this.ts, required this.isWindows});

  final TextTheme ts;
  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(l10n.reviewSupportEntry, style: ts.titleSmall),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.reviewSupportSubtitle,
          textAlign: TextAlign.center,
          style: ts.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        const SizedBox(height: WpSpacing.md),
        // Windows has a store listing → offer the Store-Review deep-link as the
        // primary action; macOS/Linux have no store, so only GitHub is offered.
        if (isWindows) ...[
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          WpButton(
            label: l10n.reviewPromptRateStore,
            variant: WpButtonVariant.primary,
            onPressed: () => _launchExternalUrl(kWindowsStoreReviewUrl),
          ),
          const SizedBox(height: WpSpacing.xs),
        ],
        // The loud action of the thank-you state on the platforms that have no
        // store listing. It used to be `secondary` on all three, which meant a
        // Windows reader met a screen with one obvious next step and a macOS
        // reader met the same screen with none — the same code branch quietly
        // deciding whether the page had a point (the One-Loud-Action Rule,
        // `lib/DESIGN.md`, and `one_loud_action_test.dart` pins both branches).
        // Windows keeps GitHub as the quieter second option, because there the
        // store rating is the bigger ask and two loud buttons are none.
        // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
        WpButton(
          label: l10n.reviewPromptStarGitHub,
          variant: isWindows
              ? WpButtonVariant.secondary
              : WpButtonVariant.primary,
          onPressed: () => _launchExternalUrl(kGitHubRepoUrl),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji rating row — modern, chat-app-like rating
// ---------------------------------------------------------------------------

class _EmojiRatingRow extends StatelessWidget {
  const _EmojiRatingRow({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  static const _emojis = ['😟', '😐', '🙂', '😊', '🤩'];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final labels = [
      l10n.feedbackRatingFrustrated,
      l10n.feedbackRatingMeh,
      l10n.feedbackRatingOkay,
      l10n.feedbackRatingHappy,
      l10n.feedbackRatingLoveIt,
    ];
    return Row(
      children: List.generate(5, (i) {
        return Expanded(
          child: _EmojiRatingOption(
            emoji: _emojis[i],
            label: labels[i],
            isSelected: rating == i + 1,
            isLast: i == 4,
            onTap: () => onChanged(i + 1),
          ),
        );
      }),
    );
  }
}

/// One face in [_EmojiRatingRow].
///
/// Stateful only to own a [FocusNode]: the row used to be five bare
/// `GestureDetector`s, so the rating — one of the three inputs on this form —
/// could not be reached, seen or operated from the keyboard at all, and
/// carried no semantics whatsoever, leaving a screen reader with five
/// unlabelled faces and no way to tell which one was chosen. The structure
/// below is the same one `WpFilterChip` uses for the chips higher up this
/// page, so both of this form's pickers now behave identically.
class _EmojiRatingOption extends StatefulWidget {
  const _EmojiRatingOption({
    required this.emoji,
    required this.label,
    required this.isSelected,
    required this.isLast,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool isSelected;
  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_EmojiRatingOption> createState() => _EmojiRatingOptionState();
}

class _EmojiRatingOptionState extends State<_EmojiRatingOption> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'EmojiRatingOption');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentSubtle = WpColors.accentSubtle;
    const surfaceVariant = WpColors.surfaceVariant;

    final tile = AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.fast),
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
      decoration: BoxDecoration(
        color: widget.isSelected ? accentSubtle : surfaceVariant,
        borderRadius: WpRadius.borderMd,
        border: Border.all(
          // `accentBorder30`, the same rung the chips at the top of this form
          // use for the same job. It used to be a hand-mixed `accent` at 40% —
          // the one place on this page where picking something drew a
          // different outline than picking something one section above it.
          color: widget.isSelected
              ? (WpColors.accentBorder30)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          // Scaled, not resized. The face used to jump from 22 px to 28 px on
          // selection, which grew the row and pushed the comment field below
          // it down — a layout shift under the pointer every time the user
          // compared two ratings. `AnimatedScale` is paint-only, so the
          // emphasis survives and the reflow does not. It also keeps a single
          // font size, which the OS text scaler can still act on.
          ExcludeSemantics(
            // The label underneath already names this option. Without this,
            // a screen reader reads the glyph too ("worried face, Frustrated").
            child: AnimatedScale(
              scale: widget.isSelected ? 1.25 : 1.0,
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WpTypography.micro,
              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
              color: widget.isSelected
                  ? (WpColors.textPrimary)
                  : (WpColors.textMuted),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(right: widget.isLast ? 0 : WpSpacing.xs),
      child: MergeSemantics(
        // `inMutuallyExclusiveGroup` is the honest role: this is one of five,
        // and picking it unpicks the rest. `selected` is what tells a screen
        // reader which face is currently chosen — the visual fill was the only
        // carrier of that before.
        child: Semantics(
          button: true,
          selected: widget.isSelected,
          inMutuallyExclusiveGroup: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: widget.onTap,
              focusNode: _focusNode,
              borderRadius: WpRadius.borderMd,
              // WpFocusRing owns all focus visuals — suppress InkWell's own.
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: WpFocusRing(
                focusNode: _focusNode,
                radius: WpRadius.md,
                child: tile,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
