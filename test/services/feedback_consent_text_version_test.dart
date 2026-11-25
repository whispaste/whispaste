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

  test('the current version covers every locale, every version differs '
      'from all others', () {
    final locales = {for (final l in L10n.supportedLocales) l.languageCode};
    final entries = kFeedbackConsentTextHashes.entries.toList();
    // A new app language adds its hash to the current version only: no text
    // a user saw changes, and older versions keep the languages they had
    // (#1951).
    expect(current?.keys.toSet(), locales, reason: kFeedbackConsentTextVersion);
    for (final entry in entries) {
      expect(locales.containsAll(entry.value.keys), isTrue, reason: entry.key);
    }
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final shared = entries[i].value.keys.toSet().intersection(
          entries[j].value.keys.toSet(),
        );
        // A new version changes the text in at least one shared locale.
        expect(
          shared.any((l) => entries[i].value[l] != entries[j].value[l]),
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
