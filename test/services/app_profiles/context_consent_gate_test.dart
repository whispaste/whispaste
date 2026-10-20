// Pipeline-level consent gate for app-profile context (R7-7).
//
// planContext() decides whether a recording may read the selection or the
// clipboard and hand it to a cloud provider. Its unit tests live in
// app_profile_resolver_test.dart. This file guards the pipeline side: no
// code path may read a profile's context source without going through the
// gate, so a cloud provider never receives context the user did not consent
// to.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that define the profile model, its storage and the gate itself.
/// A settings page that only edits the source belongs here too, added by
/// name with its reason, never by directory.
const _profileModelFiles = {
  'lib/services/app_profiles/app_profile.dart',
  'lib/services/app_profiles/app_profile_consent.dart',
  'lib/services/app_profiles/app_profile_context_source.dart',
  'lib/services/app_profiles/app_profile_resolver.dart',
  'lib/services/app_profiles/app_profile_storage.dart',
  'lib/core/data/tables.dart',
  'lib/core/data/database.g.dart',
};

/// Reading a profile's context source: the field, or a branch on its values.
final _readsContextSource = RegExp(
  r'\.contextSource\b|AppProfileContextSource\.(selection|clipboard)\b',
);

void main() {
  test('code outside the profile model reads the context source only next '
      'to planContext()', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_profileModelFiles.contains(path)) continue;
      final source = entity.readAsStringSync();
      if (!_readsContextSource.hasMatch(source)) continue;
      if (!source.contains('planContext(')) offenders.add(path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These files act on an app profile\'s context source without '
          'planContext(). Route the decision through planContext() so a '
          'cloud provider never gets context without a current consent '
          '(R7-7).',
    );
  });

  test(
    'a recording with a cloud provider and no consent sends no context',
    () {
      // Acceptance once the recording pipeline resolves app profiles:
      // profile with source selection (and clipboard), cloud post-processing
      // provider, no consent on the profile → the selection and clipboard
      // readers are never called, the provider request carries no context,
      // and the dock indicator shows "blocked: consent missing". The same
      // recording with a matching consent sends the context; with a local
      // provider it sends it without consent.
      fail('wire app-profile context into the recording pipeline first');
    },
    skip:
        'R7-7: planContext() has no caller yet, so no context reaches any '
        'provider today. Replace this skip with the pipeline test when the '
        'recording orchestrator starts resolving app profiles.',
  );
}
