import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Deleting a file here is an ordinary unlink. It does not overwrite the
/// data, so UI text must not promise that a deleted file is irrecoverable.
/// These keys describe file or model deletion and must not claim it.
const _fileDeletionKeys = {
  'modelDeleteConfirmMessage',
  'settingsFactoryResetMessage',
};

/// Per language: wording that claims a deletion cannot be undone or is
/// permanent in the disk sense.
final _irreversibleClaims = <String, RegExp>{
  'de': RegExp('dauerhaft|endgültig|unwiderruflich|unwiederbringlich'),
  'en': RegExp('permanent|cannot be undone|can\'t be undone|irreversib'),
  'es': RegExp('permanente|definitiv|no se puede deshacer'),
  'pt': RegExp('permanente|definitiv|não pode ser desfeit'),
  'ru': RegExp('навсегда|окончательно|нельзя отменить'),
  'he': RegExp('לצמיתות|אין דרך לבטל'),
};

void main() {
  for (final entry in _irreversibleClaims.entries) {
    final lang = entry.key;
    test('file deletion texts in $lang make no irreversibility claim', () {
      final values =
          (jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                  as Map)
              .cast<String, Object?>();
      final offenders = <String>[
        for (final key in _fileDeletionKeys)
          if (values[key] is String &&
              entry.value.hasMatch(values[key]! as String))
            key,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'Deleting files is a plain unlink, not a secure erase. Say the '
            'file is deleted or removed from this device, and do not claim '
            'it is permanent or cannot be recovered.',
      );
    });
  }
}
