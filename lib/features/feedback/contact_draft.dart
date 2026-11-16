import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feedback_type.dart';

/// What the user has typed into the contact form so far.
///
/// Lives in a provider that is never auto-disposed, so leaving the page, a
/// failed send or a dropped connection keeps the message. Only a successful
/// send or a confirmed discard clears it.
@immutable
class ContactDraft {
  const ContactDraft({
    this.type,
    this.message = '',
    this.email = '',
    this.contactLocale,
    this.rating,
    this.attachDiagnostics = false,
    this.publishConsent = false,
    this.startedAt,
  });

  final FeedbackType? type;
  final String message;
  final String email;
  final String? contactLocale;
  final int? rating;
  final bool attachDiagnostics;
  final bool publishConsent;

  /// When the user first opened the empty form; the API's `elapsed` field
  /// counts from here.
  final DateTime? startedAt;

  /// True when there is anything the user would lose on a discard.
  bool get hasText => message.trim().isNotEmpty || email.trim().isNotEmpty;
}

class ContactDraftNotifier extends Notifier<ContactDraft> {
  @override
  ContactDraft build() => const ContactDraft();

  void save(ContactDraft draft) => state = draft;

  void clear() => state = const ContactDraft();
}

final contactDraftProvider =
    NotifierProvider<ContactDraftNotifier, ContactDraft>(
      ContactDraftNotifier.new,
    );
