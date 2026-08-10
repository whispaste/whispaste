/// Structural guard for H1 of Ticket 26: **an autosave run can never open a
/// native file dialog.**
///
/// The behavioural half of that promise is tested in
/// `settings_autosave_service_test.dart` (an unresolvable bookmark ends the
/// run) and in `test/features/settings/settings_portability_section_test.dart`
/// (turning the feature on never touches the export picker). Both would keep
/// passing if someone added a `pickPath` fallback to a code path those tests
/// happen not to reach.
///
/// This one keeps the *shape* instead: the file that performs background runs
/// may not so much as import the dialog library, and the one file that may
/// open a directory panel is reachable from exactly one place — the settings
/// section, from a press. Same idiom as `settings_toggle_guard_test.dart`.
///
/// Comment lines are stripped before scanning, because both files discuss the
/// very names they must not use.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _runtimePath = 'lib/services/settings_autosave_service.dart';
const _chooserPath = 'lib/services/settings_autosave_folder_chooser.dart';

/// Files allowed to reach the folder chooser. A background job appearing in
/// this set is the failure mode the guard exists for.
const _chooserCallers = <String>{
  'lib/features/settings/sections/settings_portability_section.dart',
  _chooserPath,
};

String _code(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  test('the autosave run path cannot reach a file dialog', () {
    final code = _code(_runtimePath);

    for (final forbidden in [
      // The dialog library itself, and the three entry points it offers.
      'file_selector',
      'getSaveLocation',
      'getDirectoryPath',
      'openFile',
      // The manual controller: its documented contract is that *every*
      // bookmark failure falls back to the dialog flow, which is precisely
      // what a background run must not inherit.
      'settings_portability_controller',
      'PickPathFn',
      // The one file in this feature that may prompt.
      'settings_autosave_folder_chooser',
    ]) {
      expect(
        code,
        isNot(contains(forbidden)),
        reason:
            '$_runtimePath references "$forbidden". A background autosave '
            'must abort on an unusable location, never ask for a new one — '
            'an NSSavePanel appearing mid-dictation with no user action '
            'behind it is a bug, not a fallback (Ticket 26, H1).',
      );
    }
  });

  test('the folder chooser is reachable only from the settings section', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (_chooserCallers.contains(relPath)) continue;
      if (_code(relPath).contains('settings_autosave_folder_chooser')) {
        offenders.add(relPath);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The directory dialog may only be opened from a user gesture in '
          'the settings section: ${offenders.join(', ')}',
    );
  });

  test('the allowlist has no stale entries', () {
    for (final path in _chooserCallers) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path is allowlisted but no longer exists',
      );
    }
    expect(
      _code('lib/features/settings/sections/settings_portability_section.dart'),
      contains('settings_autosave_folder_chooser'),
      reason:
          'the settings section is allowlisted as the chooser\'s one call '
          'site — if it no longer calls it, the allowlist is lying',
    );
  });
}
