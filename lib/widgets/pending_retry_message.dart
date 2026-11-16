import '../core/l10n/generated/app_localizations.dart';
import '../services/pending_audio/pending_audio_queue.dart'
    show PendingRetryOutcome;

/// The toast text for the outcome of transcribing a kept recording again, or
/// null when nothing needs to be said (a success lands in the history, an
/// empty transcript is silence, null means there was nothing to retry).
///
/// A named recording that is no longer kept gets a message too, so its retry
/// button never just stops working without a word.
String? pendingRetryMessage(L10n l10n, PendingRetryOutcome? outcome) =>
    switch (outcome) {
      PendingRetryOutcome.failed => l10n.pendingRetryFailed,
      PendingRetryOutcome.expired => l10n.pendingRetryExpired,
      PendingRetryOutcome.missing => l10n.pendingRetryMissing,
      PendingRetryOutcome.saved || PendingRetryOutcome.empty || null => null,
    };
