/// UIA-SHL-14: the manual says that Esc is caught system-wide while a
/// dictation runs, and names F12 as the alternative, in every app language.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

void main() {
  test(
    'the shortcuts chapter explains the Esc cancel key in all languages',
    () async {
      for (final code in ['de', 'en', 'es', 'pt', 'he', 'ru']) {
        final l = await L10n.delegate.load(Locale(code));
        final text = l.manualC15S5B1('Esc', 'F12');
        expect(l.manualC15S5Heading, isNotEmpty, reason: code);
        expect(text, contains('Esc'), reason: code);
        expect(text, contains('F12'), reason: code);
      }
    },
  );

  test('the chapter renders the cancel-key section', () {
    final chapters = File(
      'lib/features/help/manual/manual_chapters.dart',
    ).readAsStringSync();
    expect(chapters, contains('manualC15S5Heading'));
    expect(chapters, contains('manualC15S5B1'));
  });
}
