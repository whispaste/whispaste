/// ARB key-parity gate: every `app_<locale>.arb` must carry exactly the
/// message keys of the template `app_en.arb`.
///
/// A missing key silently falls back to English at runtime, an extra key is
/// dead weight that no code reads. Both fail the gate. Gaps that are known
/// and accepted (an intentional English fallback, or a partial new language)
/// are frozen per locale in the ratchet baseline
/// (`lib/core/l10n/arb_parity_baseline.json`, `{"<locale>": ["<key>", ...]}`).
/// The baseline can only shrink: an entry whose key is translated or gone
/// from the template is reported as stale, so a closed gap cannot reopen.
///
/// Run from the repo root (pre-commit hook and CI do):
///   dart tool/check_arb_parity.dart
library;

import 'dart:convert';
import 'dart:io';

const defaultArbDir = 'lib/core/l10n';
const defaultBaselinePath = 'lib/core/l10n/arb_parity_baseline.json';
const _templateLocale = 'en';

/// Message keys of a decoded ARB file, without `@`-metadata and `@@locale`.
Set<String> messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

/// Compares [localeKeys] (locale -> message keys) against [templateKeys],
/// tolerating only the gaps frozen in [baseline]. Returns one human-readable
/// error per violation; empty means the gate passes.
List<String> checkArbParity({
  required Set<String> templateKeys,
  required Map<String, Set<String>> localeKeys,
  required Map<String, Set<String>> baseline,
}) {
  final errors = <String>[];
  for (final locale in localeKeys.keys.toList()..sort()) {
    final keys = localeKeys[locale]!;
    final frozen = baseline[locale] ?? const <String>{};
    for (final key in _sorted(templateKeys.difference(keys))) {
      if (!frozen.contains(key)) {
        errors.add('app_$locale.arb: missing key "$key"');
      }
    }
    for (final key in _sorted(keys.difference(templateKeys))) {
      errors.add('app_$locale.arb: key "$key" is not in app_en.arb');
    }
    for (final key in _sorted(frozen)) {
      if (keys.contains(key) || !templateKeys.contains(key)) {
        errors.add(
          'baseline: stale entry "$key" for "$locale" — remove it, the gap '
          'is closed',
        );
      }
    }
  }
  for (final locale in _sorted(baseline.keys)) {
    if (!localeKeys.containsKey(locale)) {
      errors.add('baseline: locale "$locale" has no app_$locale.arb');
    }
  }
  return errors;
}

/// Loads `app_*.arb` from [arbDir] and the baseline from [baselinePath]
/// (a missing baseline file counts as empty), then runs [checkArbParity].
List<String> runArbParityCheck({
  required String arbDir,
  required String baselinePath,
}) {
  final arbName = RegExp(r'^app_(.+)\.arb$');
  final localeKeys = <String, Set<String>>{};
  for (final entity in Directory(arbDir).listSync()) {
    final match = arbName.firstMatch(entity.uri.pathSegments.last);
    if (entity is! File || match == null) continue;
    localeKeys[match.group(1)!] = messageKeys(_readJson(entity));
  }
  final templateKeys = localeKeys.remove(_templateLocale);
  if (templateKeys == null) {
    return ['$arbDir/app_$_templateLocale.arb not found'];
  }

  final baselineFile = File(baselinePath);
  final baseline = <String, Set<String>>{
    if (baselineFile.existsSync())
      for (final entry in _readJson(baselineFile).entries)
        entry.key: (entry.value as List<dynamic>).cast<String>().toSet(),
  };

  return checkArbParity(
    templateKeys: templateKeys,
    localeKeys: localeKeys,
    baseline: baseline,
  );
}

Map<String, dynamic> _readJson(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

List<String> _sorted(Iterable<String> keys) => keys.toList()..sort();

void main() {
  final errors = runArbParityCheck(
    arbDir: defaultArbDir,
    baselinePath: defaultBaselinePath,
  );
  if (errors.isEmpty) {
    stdout.writeln('ARB key parity: OK');
    return;
  }
  errors.forEach(stderr.writeln);
  stderr.writeln(
    '\nARB key parity failed (${errors.length} issue(s)). Add the missing '
    'translations (see CONTRIBUTING_TRANSLATIONS.md) or, for an intentional '
    'English fallback, list the key in $defaultBaselinePath.',
  );
  exitCode = 1;
}
