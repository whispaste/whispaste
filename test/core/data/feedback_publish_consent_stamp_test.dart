import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

/// The database, not the client, stamps the consent time, and only a known
/// consent text version counts (GS-051).
void main() {
  test('consent is stamped by the database, with an allowlisted version', () {
    final original = File(
      'supabase/migrations/20261020100000_feedback_publish_consent.sql',
    ).readAsStringSync();
    // The allowlist is widened by a later migration; released migrations are
    // never edited, so the newest allowlist is the one that must match.
    final allowlist = File(
      'supabase/migrations/20261020120000_feedback_quote_v2.sql',
    ).readAsStringSync();

    expect(
      original,
      contains('CREATE TRIGGER trg_feedback_publish_consent'),
      reason: 'consent_at must be set by the database, not the client.',
    );
    expect(original, contains('NEW.consent_at := now();'));
    expect(
      allowlist,
      contains("IN ('feedback-quote-v1', 'feedback-quote-v2')"),
      reason: 'The SQL allowlist and the Dart constant must match.',
    );
    expect(kFeedbackConsentTextVersion, 'feedback-quote-v2');
  });
}
