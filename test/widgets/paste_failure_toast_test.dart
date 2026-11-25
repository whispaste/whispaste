/// The secure-field sentence of an unconfirmed paste (W-E4). Which message
/// and button a paste failure raises is covered in
/// `dictation_message_actions_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  late L10n lDe;
  setUpAll(() async {
    lDe = await L10n.delegate.load(const Locale('de'));
  });

  group('unconfirmed paste: secure-field hint (W-E4)', () {
    test('macOS adds the password and PIN sentence with the manual step', () {
      expect(
        pasteSecureFieldHint(lDe, isMacOS: true),
        lDe.pasteHintSecureField,
      );
      expect(pasteSecureFieldHint(lDe, isMacOS: true), contains('von Hand'));
    });

    test('a known field type drops the general hint (#949)', () {
      expect(
        pasteSecureFieldHint(
          lDe,
          isMacOS: true,
          fieldType: FocusedFieldType.normal,
        ),
        isNull,
      );
    });

    test('other platforms add no secure-field sentence', () {
      expect(pasteSecureFieldHint(lDe, isMacOS: false), isNull);
    });

    test('every app language has a non-empty secure-field sentence', () async {
      for (final code in [
        'de',
        'en',
        'es',
        'pt',
        'ru',
        'he',
        'fr',
        'it',
        'zh',
      ]) {
        final l = await L10n.delegate.load(Locale(code));
        expect(l.pasteHintSecureField.trim(), isNotEmpty, reason: code);
      }
    });
  });
}
