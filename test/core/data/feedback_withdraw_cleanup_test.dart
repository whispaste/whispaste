import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A withdrawal removes the quote and the hash, so the archival cron deletes
/// the row (BIZ, hash retention).
void main() {
  String read(String name) =>
      File('supabase/migrations/$name').readAsStringSync();

  final migration = read('20261020110000_feedback_withdraw_clears_hash.sql');
  final body = migration.substring(
    migration.indexOf('CREATE OR REPLACE FUNCTION'),
    migration.indexOf(r'$function$;'),
  );

  test('the withdrawal clears the quote approval and the hash', () {
    expect(body, contains('approved_for_display = false'));
    expect(body, contains('withdraw_token_hash = NULL'));
    expect(body, contains('publish_consent = false'));
  });

  test('a repeated withdrawal is a harmless no-op', () {
    // Matched by hash only: no condition on the consent state, so a call
    // after the hash is gone matches nothing and does not fail.
    final where = body.substring(body.indexOf('WHERE'));
    expect(where, isNot(contains('publish_consent')));
    expect(body, contains('withdrawn_at = coalesce(withdrawn_at, now())'));
    expect(body, isNot(contains('RAISE')));
  });

  test('the cron deletes unapproved rows and the view hides them', () {
    final cron = read('20260717_add_feedback_contact_email.sql');
    expect(cron, contains('AND approved_for_display IS NOT TRUE'));
    final view = read('20261020100000_feedback_publish_consent.sql');
    expect(view, contains('WHERE approved_for_display = true'));
    expect(view, contains("(source <> 'in_app' OR publish_consent = true)"));
  });
}
