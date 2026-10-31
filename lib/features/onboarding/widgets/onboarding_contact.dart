/// What the onboarding contact panel decides, kept apart from its widgets so
/// the hand-over points are testable: which kind leads where, what a message
/// sends, and how the server's answer maps to what the panel shows
/// (`onboarding_contact_launcher.dart` is the UI).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/logging/install_id.dart';
import '../../../services/feedback_diagnostics.dart';
import '../../../services/feedback_submission_service.dart';

/// What the user wants to write about. Chosen as a chip in the panel, in the
/// same order as the website contact widget.
enum OnboardingContactKind { idea, problem, question, other }

/// Ideas are collected in public: the idea chip opens this board instead of
/// a form, as on the website.
const kOnboardingIdeaBoardUrl =
    'https://app.votepit.com/silvio-und-maik/whispaste';

/// Whether the panel may send messages itself. Off until the server accepts
/// feedback without a star rating: migration
/// `20261025120000_feedback_rating_optional` is not on production yet
/// (checked 2026-10-30, `supabase migration list --linked`). While off,
/// problem, question and other show the contact e-mail address instead of
/// the form. Turn on together with that migration.
final onboardingContactSendEnabledProvider = Provider<bool>((ref) => false);

/// Shortest message the panel sends, as on the website.
const kOnboardingContactMinLength = 10;

/// The longest message the panel accepts.
const kOnboardingContactMaxMessageLength = 4000;

/// The server stores at most 1000 characters of `feedback_text`, the
/// optional technical details included. The legacy feedback path keeps that
/// limit until the website contact API takes over.
const kOnboardingContactMaxTextLength = 1000;

/// Room the technical details block may take on the legacy path.
const kOnboardingContactDiagnosticsReserve = 120;

/// The longest message the legacy feedback path can carry.
const kOnboardingContactLegacyMessageLength =
    kOnboardingContactMaxTextLength - kOnboardingContactDiagnosticsReserve;

/// The server category for [kind]; `null` for the idea, which never sends.
/// Same mapping as the feedback form (`feedbackCategoryFor`): question and
/// other share `general`.
String? onboardingContactCategory(OnboardingContactKind kind) => switch (kind) {
  OnboardingContactKind.idea => null,
  OnboardingContactKind.problem => 'bug',
  OnboardingContactKind.question => 'general',
  OnboardingContactKind.other => 'general',
};

/// Same shape the server's CHECK accepts, so a typo is caught in the panel
/// instead of failing as a server error.
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// True when [email] is empty (it is optional) or looks like an address.
bool isAcceptableContactEmail(String email) {
  final trimmed = email.trim();
  return trimmed.isEmpty ||
      (trimmed.length <= 254 && _emailPattern.hasMatch(trimmed));
}

/// True when [message] is long enough to send.
bool isSendableContactMessage(String message) =>
    message.trim().length >= kOnboardingContactMinLength;

/// The technical details a message carries only after the opt-in: the
/// onboarding step, the app version and the operating system. Nothing else.
String onboardingContactDiagnostics({
  required String stepId,
  required String appVersion,
  required String os,
}) {
  final block =
      '--- diagnostics ---\n'
      'Step $stepId · App $appVersion · OS $os';
  return block.length > kOnboardingContactDiagnosticsReserve
      ? block.substring(0, kOnboardingContactDiagnosticsReserve)
      : block;
}

/// Builds what the legacy path sends for [kind]. Without [includeDiagnostics]
/// the text is the message alone: no step, no OS. The quote consent is never
/// given here (only praise in the feedback form can carry it), and there is
/// no star rating. [appVersion], [deviceIdHash] and [locale] are the fields
/// every feedback row carries.
FeedbackPayload buildOnboardingContactPayload({
  required OnboardingContactKind kind,
  required String message,
  required String email,
  required bool includeDiagnostics,
  required String stepId,
  required String appVersion,
  required String os,
  required String deviceIdHash,
  required String locale,
}) {
  final category = onboardingContactCategory(kind);
  if (category == null) {
    throw ArgumentError.value(kind, 'kind', 'ideas go to the board');
  }
  final trimmedEmail = email.trim();
  var text = message.trim();
  if (text.length > kOnboardingContactLegacyMessageLength) {
    text = text.substring(0, kOnboardingContactLegacyMessageLength);
  }
  if (includeDiagnostics) {
    text =
        '$text\n\n'
        '${onboardingContactDiagnostics(stepId: stepId, appVersion: appVersion, os: os)}';
  }
  return FeedbackPayload(
    feedbackText: text,
    category: category,
    appVersion: appVersion,
    deviceIdHash: deviceIdHash,
    locale: locale,
    contactEmail: trimmedEmail.isEmpty ? null : trimmedEmail,
    contactLocale: trimmedEmail.isEmpty ? null : locale,
  );
}

/// What the panel shows after a send.
enum OnboardingContactOutcome {
  /// Arrived: the thank-you shows, with a Done action that closes the panel.
  sent,

  /// Offline, timed out or a server error: the text stays, "Try again".
  retry,

  /// The server's rate limit: the text stays, try later.
  rateLimited,

  /// This build has no feedback backend: the panel says so.
  unavailable,
}

/// Maps the service result to what the panel shows.
OnboardingContactOutcome onboardingContactOutcome(
  FeedbackSubmissionResult result,
) => switch (result) {
  FeedbackSent() => OnboardingContactOutcome.sent,
  FeedbackRateLimitedServer() => OnboardingContactOutcome.rateLimited,
  FeedbackSkippedNotConfigured() => OnboardingContactOutcome.unavailable,
  FeedbackServerError() ||
  FeedbackNetworkError() => OnboardingContactOutcome.retry,
};

/// One message as the panel hands it over. [email] is empty when the user
/// gave no reply address; the panel allows that, and then we cannot answer.
/// [elapsed] is the time since the panel opened.
final class OnboardingContactMessage {
  const OnboardingContactMessage({
    required this.kind,
    required this.message,
    this.email = '',
    this.includeDiagnostics = false,
    required this.stepId,
    required this.elapsed,
  });

  final OnboardingContactKind kind;
  final String message;
  final String email;
  final bool includeDiagnostics;
  final String stepId;
  final Duration elapsed;
}

/// Sends one [OnboardingContactMessage]. Never throws; failures come back as
/// an outcome.
typedef OnboardingContactSender =
    Future<OnboardingContactOutcome> Function(OnboardingContactMessage);

/// The sender the panel uses. This is the one place the transport is chosen:
/// the legacy feedback path for now, the website contact API later.
final onboardingContactSenderProvider = Provider<OnboardingContactSender>((
  ref,
) {
  return (message) async {
    if (onboardingContactCategory(message.kind) == null) {
      return OnboardingContactOutcome.unavailable;
    }
    try {
      final payload = buildOnboardingContactPayload(
        kind: message.kind,
        message: message.message,
        email: message.email,
        includeDiagnostics: message.includeDiagnostics,
        stepId: message.stepId,
        appVersion: appVersion,
        os: feedbackShortOs(),
        deviceIdHash: readInstallId(),
        locale: ref.read(localeProvider).languageCode,
      );
      final result = await ref
          .read(feedbackSubmissionServiceProvider)
          .submit(payload);
      return onboardingContactOutcome(result);
    } catch (_) {
      return OnboardingContactOutcome.retry;
    }
  };
});
