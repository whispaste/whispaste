import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

/// A recorded consent is only evidence if the version names the exact text
/// the user saw. So a changed consent text must come with a new version
/// (GS-051).
void main() {
  String textHash(Locale locale) {
    final l10n = lookupL10n(locale);
    final text =
        '${l10n.feedbackPublishConsentLabel}\n'
        '${l10n.feedbackPublishConsentExplanation}';
    return sha256.convert(utf8.encode(text)).toString();
  }

  final current = kFeedbackConsentTextHashes[kFeedbackConsentTextVersion];

  test('the current consent text version has recorded text hashes', () {
    expect(
      current,
      isNotNull,
      reason:
          'Add an entry for $kFeedbackConsentTextVersion to '
          'kFeedbackConsentTextHashes.',
    );
  });

  for (final locale in L10n.supportedLocales) {
    test('the ${locale.languageCode} consent text matches its version', () {
      expect(
        textHash(locale),
        current?[locale.languageCode],
        reason:
            'The ${locale.languageCode} consent text changed without a new '
            'version. Bump kFeedbackConsentTextVersion, add a new entry to '
            'kFeedbackConsentTextHashes and add the version to the server '
            'allowlist in a new migration. Never edit an existing entry.',
      );
    });
  }

  test('the frozen file allows "_comment" as its only extra key', () {
    expect(
      frozenVersions({
        '_comment': 'note',
        'feedback-quote-v1': {'en': 'x'},
      }).keys,
      ['feedback-quote-v1'],
    );
    expect(
      () => frozenVersions({'_note': 'hides a version'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('released versions are frozen', () {
    final frozen = frozenVersions(
      jsonDecode(
            File(
              'test/fixtures/feedback_consent_hashes_frozen.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    const advice =
        'Never edit a released entry of kFeedbackConsentTextHashes. For a '
        'changed text add a new version; extend the frozen file in its own '
        'commit once that version is released.';

    for (final MapEntry(key: version, value: hashes) in frozen.entries) {
      expect(
        kFeedbackConsentTextHashes[version],
        hashes,
        reason: '$version changed or was removed. $advice',
      );
    }

    int number(String version) => int.parse(version.split('-v').last);
    final highestFrozen = frozen.keys.map(number).fold(0, max);
    for (final version in kFeedbackConsentTextHashes.keys) {
      if (frozen.containsKey(version)) continue;
      expect(
        number(version),
        greaterThan(highestFrozen),
        reason:
            'New version $version must be higher than every frozen one. '
            '$advice',
      );
    }
  });

  test('every version covers every locale and differs from all others', () {
    final locales = {for (final l in L10n.supportedLocales) l.languageCode};
    final entries = kFeedbackConsentTextHashes.entries.toList();
    for (final entry in entries) {
      expect(entry.value.keys.toSet(), locales, reason: entry.key);
    }
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        // A new version changes the text in at least one locale.
        expect(
          locales.any((l) => entries[i].value[l] != entries[j].value[l]),
          isTrue,
          reason:
              '${entries[i].key} and ${entries[j].key} record the same text',
        );
      }
    }
  });

  test('versions count up and the current one is the newest', () {
    final pattern = RegExp(r'^feedback-quote-v(\d+)$');
    final numbers = [
      for (final version in kFeedbackConsentTextHashes.keys)
        int.parse(pattern.firstMatch(version)!.group(1)!),
    ];
    expect(numbers, [for (var n = 1; n <= numbers.length; n++) n]);
    expect(kFeedbackConsentTextVersion, kFeedbackConsentTextHashes.keys.last);
  });

  test('the server allowlist accepts exactly the known versions', () {
    final files =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final lists = consentAllowlists(
      [for (final f in files) f.readAsStringSync()].join('\n'),
    );

    final known = kFeedbackConsentTextHashes.keys.toSet();
    expect(lists.check, known, reason: 'CHECK constraint allowlist');
    expect(lists.trigger, known, reason: 'trigger allowlist');
  });

  test('only CHECK constraints and consent functions count', () {
    const sql = """
ALTER TABLE t ADD COLUMN consent_text_version text
  CHECK (consent_text_version IS NULL
         OR consent_text_version IN ('feedback-quote-v1'));
CREATE OR REPLACE FUNCTION public.stamp_feedback_publish_consent()
RETURNS trigger LANGUAGE plpgsql AS \$function\$
BEGIN
  IF NEW.consent_text_version NOT IN ('feedback-quote-v1') THEN
    NEW.consent_text_version := NULL;
  END IF;
  RETURN NEW;
END;
\$function\$;
-- ALTER TABLE t ADD CONSTRAINT c CHECK (consent_text_version IN ('old'));
/* CHECK (consent_text_version IN ('old')) */
-- Later backfills and queries must not count as allowlists.
UPDATE t SET x = 1 WHERE consent_text_version NOT IN ('other');
SELECT count(*) FROM t WHERE consent_text_version IN ('other');
CREATE FUNCTION public.unrelated() RETURNS void AS \$function\$
BEGIN
  PERFORM 1 WHERE 'a' NOT IN ('b');
END;
\$function\$;
""";
    final lists = consentAllowlists(sql);
    expect(lists.check, {'feedback-quote-v1'});
    expect(lists.trigger, {'feedback-quote-v1'});
  });
}

/// The consent text version allowlists as the database enforces them: the
/// last CHECK constraint on consent_text_version and the last NOT IN list in
/// the body of a function whose name mentions consent. Backfills, queries and
/// other functions are ignored (DEV-258).
({Set<String>? check, Set<String>? trigger}) consentAllowlists(String sql) {
  // Commented-out SQL is not enforced.
  sql = sql
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'--[^\n]*'), ' ');

  Set<String>? quoted(String? list) => list == null
      ? null
      : {for (final m in RegExp(r"'([^']+)'").allMatches(list)) m.group(1)!};

  final checks = RegExp(
    r'CHECK\s*\((?:(?!CHECK)[^;])*?consent_text_version\s+IN\s*\(([^)]*)\)',
    caseSensitive: false,
  ).allMatches(sql);

  String? triggerList;
  final functions = RegExp(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+[\w.]*consent\w*\s*\([^)]*\)'
    r'.*?\$function\$(.*?)\$function\$',
    caseSensitive: false,
    dotAll: true,
  );
  for (final function in functions.allMatches(sql)) {
    final lists = RegExp(
      r'consent_text_version\s+NOT\s+IN\s*\(([^)]*)\)',
      caseSensitive: false,
    ).allMatches(function.group(1)!);
    if (lists.isNotEmpty) triggerList = lists.last.group(1);
  }

  return (
    check: quoted(checks.isEmpty ? null : checks.last.group(1)),
    trigger: quoted(triggerList),
  );
}

/// Released versions from the frozen file. "_comment" is its only non-version
/// key; any other key starting with "_" would silently drop a version from the
/// check, so it fails instead.
Map<String, Map<String, String>> frozenVersions(Map<String, dynamic> raw) {
  final unknown = raw.keys.where((k) => k.startsWith('_') && k != '_comment');
  if (unknown.isNotEmpty) {
    throw FormatException('Unexpected keys in the frozen file: $unknown');
  }
  return {
    for (final MapEntry(:key, :value) in raw.entries)
      if (key != '_comment') key: Map<String, String>.from(value as Map),
  };
}
