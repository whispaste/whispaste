import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/install_id.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/feedback_diagnostics.dart';
import '../../services/feedback_consent_store.dart';
import '../../services/feedback_submission_service.dart';
import '../../services/shared_prefs_safe_read.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/wp_voice_input_button.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_consent_checkbox.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../widgets/wp_focus_ring.dart';
import '../../widgets/wp_text_field.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_copy_feedback.dart';
import '../../widgets/external_link.dart';
import '../notes/voice_insert.dart' show insertDictation;
import 'contact_draft.dart';
import 'feedback_type.dart';
import '../../widgets/wp_text_link.dart';

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

/// The prompt bubble that opens the text step, per type.
String _promptFor(L10n l10n, FeedbackType type) => switch (type) {
  FeedbackType.problem => l10n.feedbackPromptProblem,
  FeedbackType.idea => l10n.feedbackPromptIdea,
  FeedbackType.praise => l10n.feedbackPromptPraise,
  FeedbackType.question => l10n.feedbackPromptQuestion,
  FeedbackType.other => l10n.feedbackPromptOther,
};

/// Mirrors the server-side format check on the contact e-mail of the
/// WhisPaste API — a deliberately loose format check, not full RFC
/// validation. Client-side
/// only blocks obvious typos; the server is the source of truth.
final _emailFormat = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

@visibleForTesting
bool isValidFeedbackContactEmail(String value) => _emailFormat.hasMatch(value);

Future<void> _recordFeedbackSubmission() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastFeedbackKey, DateTime.now().millisecondsSinceEpoch);
}

/// Contact and feedback page: sends through `POST /v1/contact`, like the
/// website's form. The draft lives in [contactDraftProvider], so navigation,
/// errors and outages never lose a message.
///
/// Top-aligned, responsive: narrow form column on wide screens with generous
/// padding so it breathes on maximized desktop windows.
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key, this._submissionService, this._consentStore});

  final FeedbackSubmissionService? _submissionService;
  final FeedbackConsentStore? _consentStore;

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

  /// When the draft was started; `elapsed` for the API counts from here.
  late DateTime _startedAt;

  /// Publication opt-in of this submission; never implied by anything else.
  bool _publishConsent = false;
  late final FeedbackConsentStore _consentStore =
      widget._consentStore ?? FeedbackConsentStore();
  ConsentState _consentState = const ConsentState();
  bool _hasSubmittedBefore = false;
  String? _withdrawMessage;
  bool _withdrawing = false;

  /// The mail app opened. Opening is not sending, so undelivered entries are
  /// only deleted once the user confirms the mail went out.
  bool _mailOpened = false;

  /// Prepared mail, shown for copying when no mail app could be opened.
  String? _mailFallback;

  late final FeedbackSubmissionService _service;

  @override
  void initState() {
    super.initState();
    _service =
        widget._submissionService ??
        ref.read(feedbackSubmissionServiceProvider);
    unawaited(_refreshConsent());
    final draft = ref.read(contactDraftProvider);
    _type = draft.type;
    _rating = draft.rating;
    _attachDiagnostics = draft.attachDiagnostics;
    _publishConsent = draft.publishConsent;
    _contactLocale = draft.contactLocale;
    _commentController.text = draft.message;
    _emailController.text = draft.email;
    _startedAt = draft.startedAt ?? DateTime.now();
    _commentController.addListener(_saveDraft);
    _emailController.addListener(_saveDraft);
    // An entry point may have preset the type ("Idee vorschlagen…").
    final preset = ref.read(feedbackPresetTypeProvider);
    if (preset != null) _type = preset;
    // After the frame: a provider may not change while the tree is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (preset != null) {
        ref.read(feedbackPresetTypeProvider.notifier).set(null);
      }
      _saveDraft();
    });
  }

  /// Mirrors the form into [contactDraftProvider], which outlives this page.
  void _saveDraft() {
    if (!mounted) return;
    ref
        .read(contactDraftProvider.notifier)
        .save(
          ContactDraft(
            type: _type,
            message: _commentController.text,
            email: _emailController.text,
            contactLocale: _contactLocale,
            rating: _rating,
            attachDiagnostics: _attachDiagnostics,
            publishConsent: _publishConsent,
            startedAt: _startedAt,
          ),
        );
  }

  /// setState for a field the draft keeps.
  void _update(VoidCallback change) {
    setState(change);
    _saveDraft();
  }

  bool get _hasText =>
      _commentController.text.trim().isNotEmpty ||
      _emailController.text.trim().isNotEmpty;

  /// Escape with text asks before the draft is thrown away; an empty form
  /// has nothing to lose.
  Future<void> _confirmDiscard() async {
    if (!_hasText || _submitting) return;
    final l10n = L10n.of(context);
    final discard = await showWpConfirmDialog(
      context: context,
      title: l10n.contactDiscardTitle,
      message: l10n.contactDiscardMessage,
      confirmLabel: l10n.contactDiscardConfirm,
      cancelLabel: l10n.contactDiscardCancel,
      destructive: true,
    );
    if (discard && mounted) _reset();
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

  String get _diagnosticAttachment =>
      ref.read(feedbackDiagnosticAttachmentProvider);

  /// The text the server receives: the message, plus the opt-in block. The
  /// type travels as `kind`, so the text carries no tag.
  String get _composedText =>
      _attachDiagnostics ? '$_message\n\n$_diagnosticBlock' : _message;

  bool get _textFits => _composedText.length <= kContactMessageMaxLength;

  bool get _messageLongEnough => _message.length >= kContactMessageMinLength;

  /// The longest message the field accepts: the server limit minus the
  /// diagnostics block when it is attached.
  int get _commentMaxLength =>
      kContactMessageMaxLength -
      (_attachDiagnostics ? _diagnosticBlock.length + 2 : 0);

  /// Type and rating are optional: only the message is required.
  bool get _canSubmit => _messageLongEnough && _emailOk && _textFits;

  /// The first missing item as a sentence, or null when the form can be sent
  /// (UIA-FBK-03). Shown as visible text so it reaches everyone, not only
  /// the hover tooltip a disabled button would need.
  String? _missingHint(L10n l10n) {
    final String what;
    if (_message.isEmpty) {
      what = l10n.feedbackMissingComment;
    } else if (!_messageLongEnough) {
      what = l10n.contactMessageTooShort(kContactMessageMinLength);
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

  /// Retries pending withdrawals (offline earlier) and reads the local state
  /// that decides which withdrawal options the screen shows.
  Future<void> _refreshConsent() async {
    try {
      await _consentStore.flushPending(_service);
      final consent = await _consentStore.state();
      final prefs = await SharedPreferences.getInstance();
      final lastMs = readIntPrefSafe(prefs, _kLastFeedbackKey);
      if (!mounted) return;
      setState(() {
        _consentState = consent;
        _hasSubmittedBefore = lastMs != null;
      });
    } on Exception catch (e) {
      _log.warning('Could not read the consent state: $e');
    }
  }

  /// One click: the server withdraws the quotes of this device. Until the server
  /// confirms, the withdrawal stays pending and is retried later.
  Future<void> _withdrawConsent() async {
    if (_withdrawing) return;
    setState(() {
      _withdrawing = true;
      _withdrawMessage = null;
    });
    final done = await _consentStore.withdrawAll(_service);
    if (!done) feedbackWithdrawalRetry.retryLater();
    final consent = await _consentStore.state();
    if (!mounted) return;
    final l10n = L10n.of(context);
    // Without a backend, or after a final rejection, nothing will be sent:
    // point to the e-mail route instead of promising a later delivery.
    final undeliverable =
        !_service.isConfigured || consent.pending.any((p) => p.failed);
    setState(() {
      _withdrawing = false;
      _consentState = consent;
      _withdrawMessage = done && !undeliverable
          ? l10n.feedbackWithdrawConsentDone
          : undeliverable
          ? l10n.feedbackWithdrawConsentUndelivered
          : l10n.feedbackWithdrawConsentPending;
    });
  }

  /// E-mail route for consents without a stored code and for withdrawals
  /// the app could not deliver. The mail carries the feedback date when the
  /// device knows it, and for each undelivered withdrawal the hash the server
  /// stores (withdraw_token_hash), never the secret itself.
  Future<void> _withdrawByEmail() async {
    final l10n = L10n.of(context);
    final prefs = await SharedPreferences.getInstance();
    final lastMs = readIntPrefSafe(prefs, _kLastFeedbackKey);
    final body = StringBuffer(l10n.feedbackWithdrawEmailBody);
    if (lastMs != null) {
      body.write(
        '\n${l10n.feedbackWithdrawEmailDateLabel} '
        '${_formatDate(DateTime.fromMillisecondsSinceEpoch(lastMs))}',
      );
    }
    // Undelivered withdrawals, plus whatever only the unreadable credential
    // store holds (GS-124), known by hash from the prefs mirror.
    final references = [
      for (final entry in _consentState.pending.where((p) => p.failed))
        consentTokenHash(entry.token),
      for (final ref in _consentState.locked) ref.hash,
    ];
    for (final reference in references) {
      body.write('\n${l10n.feedbackWithdrawEmailReferenceLabel} $reference');
    }
    final subject = l10n.feedbackWithdrawEmailSubject;
    final opened = await _launchMail(
      consentWithdrawalMailUri(subject: subject, body: '$body').toString(),
    );
    if (!mounted) return;
    setState(() {
      _mailOpened = opened;
      _mailFallback = opened
          ? null
          : '$kConsentWithdrawalContact\n\n$subject\n\n$body';
    });
  }

  /// The user says the mail went out: it now covers the undelivered
  /// withdrawals, so their secrets are deleted from the device.
  Future<void> _confirmMailSent() async {
    await _consentStore.acknowledgeFailed();
    if (!mounted) return;
    setState(() {
      _mailOpened = false;
      _mailFallback = null;
    });
    await _refreshConsent();
  }

  Future<void> _copyMail() async {
    final text = _mailFallback;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(
      () => _withdrawMessage = L10n.of(context).feedbackWithdrawEmailCopied,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The form may already be open when another entry point presets a type.
    ref.listen<FeedbackType?>(feedbackPresetTypeProvider, (_, next) {
      if (next == null) return;
      _update(() => _type = next);
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
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(_confirmDiscard()),
        },
        // This page is a form with long free-text fields: the shared reading
        // measure keeps those lines legible on wide windows (#197).
        child: WpReadingWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // No in-page H1 — the app shell's page header is the one
              // place the page title is rendered. What stays is the
              // intro line, which says something the title doesn't.
              Text(
                l10n.feedbackSubtitle,
                style: ts.bodyMedium?.copyWith(color: WpColors.textSecondary),
              ),

              const SizedBox(height: WpSpacing.xxl),

              // One card, not one per group: category, rating, comment and
              // contact are four questions in a single act, and the act ends
              // at the submit button below the card, outside it.
              WpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                FeedbackType.question,
                                LucideIcons.circleHelp,
                                l10n.feedbackTypeQuestion,
                              ),
                              (
                                FeedbackType.other,
                                LucideIcons.messageCircle,
                                l10n.feedbackTypeOther,
                              ),
                              (
                                FeedbackType.praise,
                                LucideIcons.thumbsUp,
                                l10n.feedbackTypePraise,
                              ),
                            ])
                          Semantics(
                            identifier: 'feedback-type-${type.name}',
                            child: WpFilterChip(
                              icon: icon,
                              label: label,
                              isActive: _type == type,
                              // Optional and never preselected: a second
                              // tap on the active chip clears the choice.
                              onTap: () => _update(() {
                                _type = _type == type ? null : type;
                                // The quote consent belongs to praise only:
                                // a switch drops a consent given before.
                                if (_type != FeedbackType.praise) {
                                  _publishConsent = false;
                                }
                              }),
                            ),
                          ),
                      ],
                    ),

                    // The text, with a dictation button in the field
                    // (FB-05). Always shown: the type is optional.
                    const SizedBox(height: WpSpacing.xxl - _chipRowSlack),
                    // Without a chosen type the field still says what goes
                    // in it; an empty box gave no clue (#1845).
                    _ChatPrompt(
                      text: _type == null
                          ? l10n.feedbackPromptOther
                          : _promptFor(l10n, _type!),
                    ),
                    const SizedBox(height: WpSpacing.md),
                    ...[
                      if (_type == FeedbackType.idea) ...[
                        Text(
                          l10n.feedbackIdeaBoardHint,
                          style: ts.bodySmall?.copyWith(
                            color: WpColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: WpSpacing.xs),
                        WpTextLink(
                          testID: 'feedback-idea-board-link',
                          label: l10n.feedbackIdeasLink,
                          kind: WpLinkKind.web,
                          onPressed: () =>
                              openExternalUrl(context, kVotepitBoardUrl),
                        ),
                      ],
                      if (_type == FeedbackType.idea)
                        const SizedBox(height: WpSpacing.md),
                      WpTextField(
                        testId: 'feedback-text-field',
                        key: const Key('feedbackCommentField'),
                        controller: _commentController,
                        semanticsLabel: _type == null
                            ? l10n.feedbackPromptOther
                            : _promptFor(l10n, _type!),
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

                      const SizedBox(height: WpSpacing.xxl),

                      // Rating: optional. Never invented.
                      _fieldLabel(
                        l10n.feedbackRatingLabel,
                        ts,
                        l10n.feedbackOptionalMarker,
                      ),
                      const SizedBox(height: WpSpacing.md),
                      _EmojiRatingRow(
                        rating: _rating ?? 0,
                        onChanged: (v) =>
                            _update(() => _rating = _rating == v ? null : v),
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
                            _update(() => _contactLocale = code),
                      ),

                      const SizedBox(height: WpSpacing.xxl),

                      // Opt-in diagnostics, off by default, with a preview of
                      // the exact text that is added (FB-04).
                      _DiagnosticsOption(
                        attached: _attachDiagnostics,
                        previewOpen: _showDiagnosticsPreview,
                        block: _attachDiagnostics
                            ? _diagnosticAttachment
                            : _diagnosticBlock,
                        onAttachedChanged: (value) => _update(() {
                          if (value) {
                            ref.invalidate(
                              feedbackDiagnosticAttachmentProvider,
                            );
                          }
                          _attachDiagnostics = value;
                          if (!value) _showDiagnosticsPreview = false;
                        }),
                        onPreviewToggled: () => setState(
                          () => _showDiagnosticsPreview =
                              !_showDiagnosticsPreview,
                        ),
                      ),

                      const SizedBox(height: WpSpacing.xxl),

                      // Quotes are written like a rating, so only praise
                      // offers the consent. Problems and ideas are never
                      // published (decision 24, CONTEXT 6.7a).
                      if (_type == FeedbackType.praise) ...[
                        Text(
                          l10n.feedbackPublishReviewHint,
                          style: ts.bodySmall?.copyWith(
                            color: WpColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: WpSpacing.md),
                        // Opt-in to quote this text on the website. Off by
                        // default and never implied by the rating or by
                        // sending.
                        WpConsentCheckbox(
                          key: const Key('feedbackPublishConsent'),
                          value: _publishConsent,
                          label: l10n.feedbackPublishConsentLabel,
                          explanation: l10n.feedbackPublishConsentExplanation,
                          onChanged: (v) => _update(() => _publishConsent = v),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: WpSpacing.xxl),

              // Error message
              // The draft stays; the button below turns into "send
              // again".
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
              WpButton(
                testId: 'contact-form-submit',
                label: _submitting
                    ? l10n.feedbackSubmitting
                    : _error != null
                    ? l10n.contactRetry
                    : l10n.feedbackSubmit,
                variant: WpButtonVariant.primary,
                icon: _error != null ? LucideIcons.rotateCw : LucideIcons.send,
                isLoading: _submitting,
                expanded: true,
                onPressed: _canSubmit ? _submit : null,
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
                      style: ts.bodySmall?.copyWith(color: WpColors.textMuted),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: WpSpacing.lg),

              // The way around the form: the address as text to copy.
              _ContactFallback(ts: ts),

              // Outside the type gate: withdrawing must not depend on
              // filling in the form.
              _ConsentWithdrawalSection(
                consent: _consentState,
                canDeliver: _service.isConfigured,
                hasSubmittedBefore: _hasSubmittedBefore,
                withdrawing: _withdrawing,
                message: _withdrawMessage,
                onWithdraw: _withdrawConsent,
                onWithdrawByEmail: _withdrawByEmail,
                mailOpened: _mailOpened,
                mailFallback: _mailFallback,
                onConfirmMailSent: _confirmMailSent,
                onCopyMail: _copyMail,
              ),

              const SizedBox(height: WpSpacing.xxxl),
            ],
          ),
        ),
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
      final email = _emailController.text.trim();
      // A fresh secret per consented submission; only its hash is sent.
      // Only praise can carry the quote consent (decision 24).
      final publish = _publishConsent && _type == FeedbackType.praise;
      final consentToken = publish ? newConsentToken() : null;
      final payload = ContactPayload(
        // Without a choice the message goes out as "other".
        kind: (_type ?? FeedbackType.other).name,
        message: _composedText,
        lang: email.isEmpty ? locale : (_contactLocale ?? locale),
        elapsedMs: DateTime.now().difference(_startedAt).inMilliseconds,
        installHash: consentTokenHash(readInstallId()),
        email: email,
        rating: _rating,
        diagnostics: _attachDiagnostics ? _diagnosticAttachment : null,
        // Version and system only travel with the opt-in diagnostics.
        appVersion: _attachDiagnostics ? appVersion : null,
        os: _attachDiagnostics ? contactOsName(Platform.operatingSystem) : null,
        publishConsent: publish,
        withdrawTokenHash: consentToken == null
            ? null
            : consentTokenHash(consentToken),
      );

      final result = await _service.submitContact(payload);

      if (!mounted) return;

      switch (result) {
        case FeedbackSent():
          ref.read(contactDraftProvider.notifier).clear();
          await _recordFeedbackSubmission();
          if (mounted) setState(() => _submitted = true);
          if (consentToken != null) {
            await _consentStore.addConsent(consentToken);
            unawaited(_refreshConsent());
          }
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
      _publishConsent = false;
      _startedAt = DateTime.now();
    });
    ref.read(contactDraftProvider.notifier).clear();
  }
}

// ---------------------------------------------------------------------------
// Optional contact email + preferred reply language — extracted out of
// _FeedbackPageState.build to keep its cyclomatic complexity down.
// ---------------------------------------------------------------------------

/// Opens a `mailto:` link. True when a mail app took it; the caller shows the
/// prepared mail for copying otherwise.
Future<bool> _launchMail(String url) async {
  final uri = Uri.parse(url);
  try {
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } on Exception catch (e) {
    // Scheme only: a mail link carries the withdrawal reference.
    _FeedbackPageState._log.warning(
      'Could not open a ${uri.scheme} link: ${e.runtimeType}',
    );
  }
  return false;
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _ConsentWithdrawalSection extends StatelessWidget {
  const _ConsentWithdrawalSection({
    required this.consent,
    required this.canDeliver,
    required this.hasSubmittedBefore,
    required this.withdrawing,
    required this.message,
    required this.onWithdraw,
    required this.onWithdrawByEmail,
    required this.mailOpened,
    required this.mailFallback,
    required this.onConfirmMailSent,
    required this.onCopyMail,
  });

  final ConsentState consent;

  /// False without a backend: nothing will ever be sent.
  final bool canDeliver;
  final bool hasSubmittedBefore;
  final bool withdrawing;
  final String? message;
  final VoidCallback onWithdraw;
  final VoidCallback onWithdrawByEmail;
  final bool mailOpened;
  final String? mailFallback;
  final VoidCallback onConfirmMailSent;
  final VoidCallback onCopyMail;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final muted = Theme.of(context).textTheme.bodySmall;
    final pending = consent.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (consent.active.isNotEmpty) ...[
          WpButton(
            key: const Key('feedback-withdraw-consent'),
            label: l10n.feedbackWithdrawConsentLabel,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            isLoading: withdrawing,
            onPressed: onWithdraw,
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(l10n.feedbackWithdrawConsentHelp, style: muted),
        ] else if (pending.isEmpty &&
            consent.locked.isEmpty &&
            hasSubmittedBefore)
          Text(l10n.feedbackWithdrawNoCode, style: muted),
        if (consent.locked.isNotEmpty) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.feedbackWithdrawLocked,
            key: const Key('feedback-withdraw-locked'),
            style: muted,
          ),
        ],
        // One line per withdrawal the server has not confirmed yet.
        for (final (i, entry) in pending.indexed) ...[
          const SizedBox(height: WpSpacing.xs),
          if (entry.failed || !canDeliver)
            Text(
              l10n.feedbackWithdrawEntryFailed(_formatDate(entry.since)),
              key: Key('feedback-withdraw-entry-failed-$i'),
              style: muted,
            )
          else
            Text(
              l10n.feedbackWithdrawEntrySending(_formatDate(entry.since)),
              key: Key('feedback-withdraw-entry-sending-$i'),
              style: muted,
            ),
        ],
        if (message != null) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            message!,
            key: const Key('feedback-withdraw-consent-message'),
            style: muted,
          ),
        ],
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          key: const Key('feedback-withdraw-email'),
          label: l10n.feedbackWithdrawEmailLabel,
          variant: WpButtonVariant.ghost,
          tone: WpButtonTone.neutral,
          onPressed: onWithdrawByEmail,
        ),
        if (mailFallback != null) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(l10n.feedbackWithdrawEmailLaunchFailed, style: muted),
          const SelectableText(
            kConsentWithdrawalContact,
            key: Key('feedback-withdraw-email-address'),
          ),
          WpButton(
            key: const Key('feedback-withdraw-email-copy'),
            label: l10n.feedbackWithdrawEmailCopyLabel,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            onPressed: onCopyMail,
          ),
        ],
        if ((mailOpened || mailFallback != null) &&
            pending.any((p) => p.failed)) ...[
          const SizedBox(height: WpSpacing.xs),
          WpButton(
            key: const Key('feedback-withdraw-email-sent'),
            label: l10n.feedbackWithdrawEmailSentLabel,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            onPressed: onConfirmMailSent,
          ),
        ],
      ],
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
        // The field below carries this name; read once, on the field.
        ExcludeSemantics(
          child: Text(l10n.feedbackContactEmailLabel, style: ts.titleSmall),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.feedbackContactEmailExplanation,
          style: ts.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        const SizedBox(height: WpSpacing.sm),
        WpTextField(
          testId: 'feedback-email-field',
          key: const Key('feedbackEmailField'),
          controller: emailController,
          variant: WpTextFieldVariant.form,
          // Named like its visible heading, not only by the placeholder
          // (#1916); the address itself is the field's purpose.
          semanticsLabel: l10n.feedbackContactEmailLabel,
          hintText: l10n.feedbackContactEmailPlaceholder,
          autofillHints: const [AutofillHints.email],
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

/// The contact address as selectable text with a copy button: works without a
/// mail app and without the API.
class _ContactFallback extends StatelessWidget {
  const _ContactFallback({required this.ts});

  final TextTheme ts;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.sm,
      runSpacing: WpSpacing.xs,
      children: [
        Text(
          l10n.contactFallbackLabel,
          style: ts.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        SelectableText(
          kContactEmail,
          style: ts.bodySmall?.copyWith(color: WpColors.textPrimary),
        ),
        WpCopyButton(
          testId: 'contact-form-copy-address',
          label: l10n.contactCopyAddress,
          text: () => kContactEmail,
          variant: WpButtonVariant.ghost,
          size: WpButtonSize.dense,
        ),
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
        // The shared consent checkbox: same box, label and focus ring as the
        // other optional choices in the form. Its own InkWell drew only the
        // default grey focus halo, about 1.2:1 on the page (#1845).
        Semantics(
          identifier: 'feedback-diagnostics-checkbox',
          child: WpConsentCheckbox(
            key: const Key('feedback-diagnostics-attach'),
            value: attached,
            label: l10n.feedbackDiagnosticsLabel,
            explanation: l10n.feedbackDiagnosticsExplanation,
            onChanged: onAttachedChanged,
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
    return WpReadingWidth(
      alignment: AlignmentDirectional.topCenter,
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
            l10n.contactSentMessage,
            textAlign: TextAlign.center,
            style: ts.bodyMedium?.copyWith(color: WpColors.textSecondary),
          ),
          const SizedBox(height: WpSpacing.xxxl),
          WpButton(
            testId: 'contact-form-send-another',
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
          WpButton(
            testId: 'contact-form-ideas-board',
            label: l10n.feedbackIdeasLink,
            variant: WpButtonVariant.ghost,
            icon: LucideIcons.lightbulb,
            onPressed: () => openExternalUrl(context, kVotepitBoardUrl),
          ),
        ],
      ),
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

  // Lucide faces, not emoji: emoji need a colour-emoji font, which Linux
  // installs often lack (empty boxes, UX-034).
  static const _icons = <IconData>[
    LucideIcons.frown,
    LucideIcons.meh,
    LucideIcons.smile,
    LucideIcons.smilePlus,
    LucideIcons.laugh,
  ];

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
              icon: _icons[i],
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
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isLast,
    required this.onTap,
  });

  final IconData icon;
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
            // a screen reader would also announce the icon's own name.
            child: AnimatedScale(
              scale: widget.isSelected ? 1.25 : 1.0,
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              child: Icon(
                widget.icon,
                size: WpIconSize.lg,
                color: widget.isSelected
                    ? WpColors.textPrimary
                    : WpColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WpTypography.caption,
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
