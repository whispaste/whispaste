/// What the onboarding contact panel decides, kept apart from its widgets so
/// the hand-over points are testable: which kind leads where, what a message
/// sends, and how the server's answer maps to what the panel shows
/// (`onboarding_contact_launcher.dart` is the UI).
library;

import 'dart:io' show Platform;

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

/// Whether the panel may send messages itself via `POST /v1/contact`. Only tests
/// turn it off, to check the fallback that shows the contact e-mail address.
final onboardingContactSendEnabledProvider = Provider<bool>((ref) => true);

/// Shortest message the panel sends, as on the website.
const kOnboardingContactMinLength = 10;

/// The longest message the panel accepts.
const kOnboardingContactMaxMessageLength = 4000;

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

/// [stepId] as the contact API takes it (`^[a-z_]{1,32}$`): the step enum
/// name in snake case (`tryOut` → `try_out`), `null` when nothing is left.
/// The API drops a value it does not accept without failing the message.
String? contactStepId(String stepId) {
  final snake = stepId
      .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')
      .replaceAll(RegExp('[^a-z_]'), '_');
  final trimmed = snake.replaceAll(RegExp('^_+|_+\$'), '');
  if (trimmed.isEmpty) return null;
  return trimmed.length > 32 ? trimmed.substring(0, 32) : trimmed;
}

/// Builds what the panel sends for [message]. Without the opt-in
/// ([OnboardingContactMessage.includeDiagnostics]) the message goes out alone:
/// no app version, no system, no step, no logs, and [readDiagnostics] is not
/// called, so no log file is read. With it, version, system, step and the
/// cleaned diagnostics attachment travel along. Never a rating or the quote
/// consent.
ContactPayload buildOnboardingContactPayload({
  required OnboardingContactMessage message,
  required String locale,
  required String installHash,
  required String appVersion,
  required String operatingSystem,
  required String Function() readDiagnostics,
}) {
  final withDiagnostics = message.includeDiagnostics;
  return ContactPayload(
    kind: message.kind.name,
    message: message.message.trim(),
    email: message.email.trim(),
    lang: locale,
    elapsedMs: message.elapsed.inMilliseconds,
    installHash: installHash,
    appVersion: withDiagnostics ? appVersion : null,
    os: withDiagnostics ? contactOsName(operatingSystem) : null,
    stepId: withDiagnostics ? contactStepId(message.stepId) : null,
    diagnostics: withDiagnostics ? readDiagnostics() : null,
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
/// the contact API, with diagnostics sent separately from the message.
final onboardingContactSenderProvider = Provider<OnboardingContactSender>((
  ref,
) {
  return (message) async {
    if (onboardingContactCategory(message.kind) == null) {
      return OnboardingContactOutcome.unavailable;
    }
    try {
      if (message.includeDiagnostics) {
        ref.invalidate(feedbackDiagnosticAttachmentProvider);
      }
      final payload = buildOnboardingContactPayload(
        message: message,
        locale: ref.read(localeProvider).languageCode,
        installHash: consentTokenHash(readInstallId()),
        appVersion: appVersion,
        operatingSystem: Platform.operatingSystem,
        readDiagnostics: () => ref.read(feedbackDiagnosticAttachmentProvider),
      );
      final result = await ref
          .read(feedbackSubmissionServiceProvider)
          .submitContact(payload);
      return onboardingContactOutcome(result);
    } catch (_) {
      return OnboardingContactOutcome.retry;
    }
  };
});
