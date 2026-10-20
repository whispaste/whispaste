import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_info.dart';
import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/install_id.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/feedback_diagnostics.dart';
import '../../services/feedback_submission_service.dart';
import '../../services/shared_prefs_safe_read.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/wp_row_checkbox.dart';
import '../../widgets/wp_voice_input_button.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../widgets/wp_focus_ring.dart';
import '../../widgets/wp_text_field.dart';
import '../../widgets/external_link.dart';
import '../notes/voice_insert.dart' show insertDictation;
import 'feedback_type.dart';

/// Supabase URL — injected at build time via `--dart-define`.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');

/// Supabase publishable key — injected at build time via `--dart-define`.
/// Public key (replaces legacy anon key), safe for client-side use.
/// RLS enforces all access control server-side.
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: '',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

/// The prompt bubble that opens the text step, per type.
String _promptFor(L10n l10n, FeedbackType type) => switch (type) {
  FeedbackType.problem => l10n.feedbackPromptProblem,
  FeedbackType.idea => l10n.feedbackPromptIdea,
  FeedbackType.praise => l10n.feedbackPromptPraise,
  FeedbackType.question => l10n.feedbackPromptQuestion,
};

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

/// Feedback page — polished, chat-inspired feedback form.
///
/// Top-aligned, responsive: narrow form column on wide screens with generous
/// padding so it breathes on maximized desktop windows.
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key, this._submissionService});

  final FeedbackSubmissionService? _submissionService;

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  static final _log = AppLogger('FeedbackPage');

  FeedbackType? _type;
  // Optional: null until the user picks one, and back to null on a second tap.
  int? _rating;
  bool _attachDiagnostics = false;
  bool _showDiagnosticsPreview = false;
  final _commentController = TextEditingController();
  final _emailController = TextEditingController();
  String? _contactLocale;
  bool _submitted = false;
  bool _submitting = false;
  String? _error;
  // Set when a feedback was sent within the last 24 h. Checked when the form
  // opens, so the user learns it before typing a long message (UIA-FBK-04).
  bool _clientLimited = false;

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
    _isClientRateLimited().then((limited) {
      if (mounted && limited) setState(() => _clientLimited = true);
    });
    // An entry point may have preset the type ("Idee vorschlagen…").
    final preset = ref.read(feedbackPresetTypeProvider);
    if (preset != null) {
      _type = preset;
      // Cleared after the frame: a provider may not change while the tree is
      // being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(feedbackPresetTypeProvider.notifier).set(null);
      });
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _emailOk {
    final email = _emailController.text.trim();
    return email.isEmpty || isValidFeedbackContactEmail(email);
  }

  /// The message as typed, trimmed.
  String get _message => _commentController.text.trim();

  /// The diagnostics block, when attached (read live: the engine may change).
  String get _diagnosticBlock => ref.read(feedbackDiagnosticBlockProvider);

  /// A neutral tag for praise and questions, so the analysis can tell them
  /// apart: both are stored as category `general`. Problem and idea carry
  /// their category already.
  String? get _typeTag => switch (_type) {
    FeedbackType.praise => '[praise]',
    FeedbackType.question => '[question]',
    _ => null,
  };

  String get _taggedMessage =>
      _typeTag == null ? _message : '${_typeTag!} $_message';

  /// The text the server receives: the tagged message, plus the opt-in block.
  String get _composedText => _attachDiagnostics
      ? '$_taggedMessage\n\n$_diagnosticBlock'
      : _taggedMessage;

  bool get _textFits => _composedText.length <= kFeedbackTextMaxLength;

  /// The longest message the field accepts: the server limit minus the tag
  /// and, when attached, the diagnostics block.
  int get _commentMaxLength =>
      kFeedbackTextMaxLength -
      (_typeTag == null ? 0 : _typeTag!.length + 1) -
      (_attachDiagnostics ? _diagnosticBlock.length + 2 : 0);

  /// The star rating is a required field of the form.
  bool get _ratingOk => _rating != null;

  bool get _canSubmit =>
      _type != null &&
      _message.isNotEmpty &&
      _ratingOk &&
      _emailOk &&
      _textFits;

  /// The first missing item as a sentence, or null when the form can be sent
  /// (UIA-FBK-03). Shown as visible text so it reaches everyone, not only
  /// the hover tooltip a disabled button would need.
  String? _missingHint(L10n l10n) {
    final String what;
    if (_type == null) {
      what = l10n.feedbackMissingCategory;
    } else if (_message.isEmpty) {
      what = l10n.feedbackMissingComment;
    } else if (!_ratingOk) {
      what = l10n.feedbackMissingRating;
    } else if (!_emailOk) {
      what = l10n.feedbackMissingEmail;
    } else if (!_textFits) {
      return l10n.feedbackTextTooLong;
    } else {
      return null;
    }
    return l10n.feedbackSubmitMissing(what);
  }

  /// A dictated transcript lands at the caret, like in the notes editor, and
  /// is clipped to the field's limit (the controller bypasses the field's
  /// own length formatter).
  void _insertDictation(String transcript) {
    final next = insertDictation(_commentController.value, transcript);
    final max = _commentMaxLength;
    final clipped = next.text.length > max
        ? next.copyWith(
            text: next.text.substring(0, max),
            selection: TextSelection.collapsed(offset: max),
          )
        : next;
    setState(() => _commentController.value = clipped);
  }

  /// A section label with a visible marker: "Pflicht" or "Optional".
  Widget _fieldLabel(String text, TextTheme ts, String marker) {
    return Row(
      children: [
        Flexible(child: Text(text, style: ts.titleSmall)),
        const SizedBox(width: WpSpacing.xs),
        Text(marker, style: ts.bodySmall?.copyWith(color: WpColors.textMuted)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The form may already be open when another entry point presets a type.
    ref.listen<FeedbackType?>(feedbackPresetTypeProvider, (_, next) {
      if (next == null) return;
      setState(() => _type = next);
      ref.read(feedbackPresetTypeProvider.notifier).set(null);
    });
    final ts = Theme.of(context).textTheme;
    final l10n = L10n.of(context);

    if (_submitted) {
      return WpPageShell(
        child: _ThankYouView(ts: ts, onReset: _reset),
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
                      // Step one: what is it about. A chat-like prompt, then
                      // the types as chips (FB-03).
                      _ChatPrompt(text: l10n.feedbackCategoryLabel),
                      // `- _chipRowSlack` on both sides of the row: the chips'
                      // tap surfaces are taller than their pills, and the eye
                      // measures from the pill. See [_chipRowSlack].
                      const SizedBox(height: WpSpacing.md - _chipRowSlack),
                      Wrap(
                        spacing: WpSpacing.sm,
                        // Zero leaves 12px within a run and ~20px between runs,
                        // see the note on [_chipRowSlack].
                        runSpacing: 0,
                        children: [
                          for (final (type, icon, label)
                              in <(FeedbackType, IconData, String)>[
                                (
                                  FeedbackType.problem,
                                  LucideIcons.bug,
                                  l10n.feedbackTypeProblem,
                                ),
                                (
                                  FeedbackType.idea,
                                  LucideIcons.lightbulb,
                                  l10n.feedbackTypeIdea,
                                ),
                                (
                                  FeedbackType.praise,
                                  LucideIcons.thumbsUp,
                                  l10n.feedbackTypePraise,
                                ),
                                (
                                  FeedbackType.question,
                                  LucideIcons.circleHelp,
                                  l10n.feedbackTypeQuestion,
                                ),
                              ])
                            Semantics(
                              identifier: 'feedback-type-${type.name}',
                              child: WpFilterChip(
                                icon: icon,
                                label: label,
                                isActive: _type == type,
                                onTap: () => setState(() => _type = type),
                              ),
                            ),
                        ],
                      ),

                      // Step two, once a type is chosen: the text, with a
                      // dictation button in the field (FB-05).
                      if (_type != null) ...[
                        const SizedBox(height: WpSpacing.xxl - _chipRowSlack),
                        _ChatPrompt(text: _promptFor(l10n, _type!)),
                        const SizedBox(height: WpSpacing.md),
                        Semantics(
                          identifier: 'feedback-text-field',
                          child: WpTextField(
                            key: const Key('feedbackCommentField'),
                            controller: _commentController,
                            variant: WpTextFieldVariant.form,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: _commentMaxLength,
                            // The app's own dictation button, as in the notes
                            // editor: the transcript lands in this field.
                            suffix: Semantics(
                              identifier: 'feedback-dictate-button',
                              child: WpVoiceInputButton(
                                onTranscript: _insertDictation,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (_type == FeedbackType.idea) ...[
                          const SizedBox(height: WpSpacing.md),
                          Text(
                            l10n.feedbackIdeaBoardHint,
                            style: ts.bodySmall?.copyWith(
                              color: WpColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: WpSpacing.xs),
                          Semantics(
                            identifier: 'feedback-idea-board-link',
                            child: WpButton(
                              label: l10n.feedbackIdeasLink,
                              variant: WpButtonVariant.ghost,
                              icon: LucideIcons.externalLink,
                              onPressed: () =>
                                  openExternalUrl(context, kVotepitBoardUrl),
                            ),
                          ),
                        ],

                        const SizedBox(height: WpSpacing.xxl),

                        // Rating: optional. Until the server accepts an empty
                        // rating, a skipped one is sent as the default.
                        _fieldLabel(
                          l10n.feedbackRatingLabel,
                          ts,
                          l10n.feedbackRequiredMarker,
                        ),
                        const SizedBox(height: WpSpacing.md),
                        _EmojiRatingRow(
                          rating: _rating ?? 0,
                          onChanged: (v) =>
                              setState(() => _rating = _rating == v ? null : v),
                        ),

                        const SizedBox(height: WpSpacing.xxl),

                        // Optional contact e-mail + preferred reply language
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

                        const SizedBox(height: WpSpacing.xxl),

                        // Opt-in diagnostics, off by default, with a preview of
                        // the exact text that is added (FB-04).
                        _DiagnosticsOption(
                          attached: _attachDiagnostics,
                          previewOpen: _showDiagnosticsPreview,
                          block: _diagnosticBlock,
                          onAttachedChanged: (value) => setState(() {
                            _attachDiagnostics = value;
                            if (!value) _showDiagnosticsPreview = false;
                          }),
                          onPreviewToggled: () => setState(
                            () => _showDiagnosticsPreview =
                                !_showDiagnosticsPreview,
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: WpSpacing.xxl),

                  // Error message
                  if (_error != null || _clientLimited) ...[
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
                  Semantics(
                    identifier: 'feedback-submit',
                    child: WpButton(
                      label: _submitting
                          ? l10n.feedbackSubmitting
                          : l10n.feedbackSubmit,
                      variant: WpButtonVariant.primary,
                      icon: LucideIcons.send,
                      isLoading: _submitting,
                      expanded: true,
                      onPressed: _canSubmit && !_clientLimited ? _submit : null,
                    ),
                  ),
                  if (!_canSubmit &&
                      !_submitting &&
                      _missingHint(l10n) != null) ...[
                    const SizedBox(height: WpSpacing.xs),
                    Text(
                      _missingHint(l10n)!,
                      style: ts.bodySmall?.copyWith(color: WpColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: WpSpacing.lg),

                  // Privacy note
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
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
    return switch (_error ?? 'rate_limited') {
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
        rating: _rating!,
        feedbackText: _composedText,
        category: feedbackCategoryFor(_type!),
        appVersion: appVersion,
        deviceIdHash: readInstallId(),
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
    } catch (e, st) {
      // Any error, not only Exception: a Dart Error must also end the sending
      // state instead of leaving the spinner up (UIA-FBK-05).
      _log.warning('Feedback submission failed unexpectedly: $e\n$st');
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
      _rating = null;
      _type = null;
      _attachDiagnostics = false;
      _showDiagnosticsPreview = false;
      _commentController.clear();
      _emailController.clear();
      _contactLocale = null;
    });
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
  const _FeedbackCard({required this.children});

  final List<Widget> children;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
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
        Semantics(
          identifier: 'feedback-email-field',
          child: WpTextField(
            key: const Key('feedbackEmailField'),
            controller: emailController,
            variant: WpTextFieldVariant.form,
            hintText: l10n.feedbackContactEmailPlaceholder,
            // An address is never a word the dictionary should second-guess.
            autocorrect: false,
            onChanged: (_) => onEmailChanged(),
          ),
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

/// A chat-style prompt: the question the next step answers, in a quiet bubble.
class _ChatPrompt extends StatelessWidget {
  const _ChatPrompt({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: WpColors.surfaceVariant,
        borderRadius: WpRadius.borderMd,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// The opt-in diagnostics switch (FB-04). Off by default. The preview shows
/// the exact block that is added to the message, nothing more.
class _DiagnosticsOption extends StatelessWidget {
  const _DiagnosticsOption({
    required this.attached,
    required this.previewOpen,
    required this.block,
    required this.onAttachedChanged,
    required this.onPreviewToggled,
  });

  final bool attached;
  final bool previewOpen;
  final String block;
  final ValueChanged<bool> onAttachedChanged;
  final VoidCallback onPreviewToggled;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final ts = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          identifier: 'feedback-diagnostics-checkbox',
          child: InkWell(
            borderRadius: WpRadius.borderMd,
            onTap: () => onAttachedChanged(!attached),
            child: Row(
              children: [
                WpRowCheckbox(
                  value: attached,
                  semanticsLabel: l10n.feedbackDiagnosticsLabel,
                  onChanged: () => onAttachedChanged(!attached),
                ),
                const SizedBox(width: WpSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.feedbackDiagnosticsLabel,
                    style: ts.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: WpRowCheckbox.extent),
          child: Text(
            l10n.feedbackDiagnosticsExplanation,
            style: ts.bodySmall?.copyWith(color: WpColors.textSecondary),
          ),
        ),
        if (attached) ...[
          const SizedBox(height: WpSpacing.xs),
          Semantics(
            identifier: 'feedback-diagnostics-preview-toggle',
            child: WpButton(
              label: previewOpen
                  ? l10n.feedbackDiagnosticsPreviewHide
                  : l10n.feedbackDiagnosticsPreview,
              variant: WpButtonVariant.ghost,
              icon: previewOpen ? LucideIcons.eyeOff : LucideIcons.eye,
              onPressed: onPreviewToggled,
            ),
          ),
          if (previewOpen)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: WpSpacing.xs),
              padding: const EdgeInsets.all(WpSpacing.md),
              decoration: BoxDecoration(
                color: WpColors.surfaceVariant,
                borderRadius: WpRadius.borderMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.feedbackDiagnosticsPreviewHeading,
                    style: ts.bodySmall?.copyWith(
                      color: WpColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  Semantics(
                    identifier: 'feedback-diagnostics-preview',
                    child: SelectableText(
                      block,
                      style: ts.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
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
  const _ThankYouView({required this.ts, required this.onReset});

  final TextTheme ts;
  final VoidCallback onReset;

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
                  decoration: BoxDecoration(
                    color: WpColors.accentSubtle,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    LucideIcons.heart,
                    size: WpIconSize.xl,
                    color: WpColors.accent,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxl),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(l10n.feedbackThankYou, style: ts.headlineMedium),
                ),
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
                  variant: WpButtonVariant.primary,
                  icon: LucideIcons.messageSquarePlus,
                  onPressed: onReset,
                ),
                const SizedBox(height: WpSpacing.xxxl),
                // Quietest element on the page, on purpose: the reader just
                // finished giving feedback, so a link to the public ideas
                // board is a natural next step. It is the only extra action on
                // this screen, so it gets no card and no fill: just the ghost
                // variant's plain text-button register.
                // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                WpButton(
                  label: l10n.feedbackIdeasLink,
                  variant: WpButtonVariant.ghost,
                  icon: LucideIcons.lightbulb,
                  onPressed: () => openExternalUrl(context, kVotepitBoardUrl),
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
          child: Semantics(
            identifier: 'feedback-rating-${i + 1}',
            child: _EmojiRatingOption(
              emoji: _emojis[i],
              label: labels[i],
              isSelected: rating == i + 1,
              isLast: i == 4,
              onTap: () => onChanged(i + 1),
            ),
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
    final accentSubtle = WpColors.accentSubtle;
    final surfaceVariant = WpColors.surfaceVariant;

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
