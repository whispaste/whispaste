import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that every writing/query surface in `lib/` is built through one
/// of the app's three text-input components — never a raw `TextField` or
/// `TextFormField` constructed at the call site.
///
/// The family this closes: [WpSearchField] owns every field that *narrows a
/// list by typing*, `WpTextField` owns every field that *holds a value the
/// user authors* (History title/transcript, the Notes editor), and
/// `WpTagInput` owns the one committed-with-Enter, width-constrained value
/// field inside a `Wrap`. `WpTextField`'s own library comment names the
/// historical divergence this closes on the writing-surface side: the
/// History transcript, the History title and the Notes editor each hand-
/// rolled their own font, line-height, border and insets, so the same app
/// looked like three different programs depending on which field a user's
/// cursor was in.
///
/// The rest of that divergence is closed too. Six files used to hand-roll a
/// `TextField` with their own `style`/`decoration` — the two Settings field
/// helpers, the custom-vocabulary box, the Snippets and Replacements dialogs,
/// the feedback form and History's note rows — in five different geometries.
/// They now render `WpTextField`'s `form` variant (a field standing alone
/// under its own label) or `embedded` (a field inside a row the caller draws
/// because that row also holds its save/cancel buttons), and their shared
/// geometry is measured in `form_field_geometry_consistency_test.dart`.
///
/// What is left below is therefore the whole list, not a to-do: the three
/// components and a debug-only entry point. A new name here is a regression
/// and needs a reason that is about *behaviour*, because appearance is no
/// longer a reason — `WpTextField` has a variant for every shape a field in
/// this app takes.
void main() {
  test('no source file outside WpTextField/WpSearchField/WpTagInput builds a '
      'raw TextField or TextFormField', () {
    const allowedFiles = <String, String>{
      // The three canonical components — they are what every entry below
      // delegates to, not offenders.
      'lib/widgets/wp_text_field.dart': 'the WpTextField component',
      'lib/widgets/wp_search_field.dart': 'the WpSearchField component',
      'lib/widgets/tag_input.dart': 'the WpTagInput component',

      // Debug-only entry point, never shipped in a user-facing build (same
      // exemption as the dialog guard).
      'lib/main_smart_mode_debug.dart': 'debug harness, exempt by design',
    };

    // Constructor-shaped: `\b` keeps this off identifiers that merely
    // contain "TextField"/"TextFormField" (a controller field named
    // `titleTextField`, for instance) and off comments referencing the
    // class name without constructing it.
    final rawTextFieldPattern = RegExp(
      r'\bTextField\s*\(|\bTextFormField\s*\(',
    );

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();
      if (rawTextFieldPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw TextField/TextFormField built outside WpTextField / '
          'WpSearchField / WpTagInput. Route it through the matching '
          'component (WpTextField for an authored value, WpSearchField for '
          'a query, WpTagInput for an in-progress tag), or add it to the '
          'allowlist above with a reason: ${offenders.join(', ')}',
    );
  });

  test('the allowlist has no stale entries', () {
    // A path that stops existing, or stops matching, means the allowlist is
    // lying about why it exists — and a stale entry silently re-opens the
    // hole it was meant to document.
    const allowedFiles = <String>{
      'lib/widgets/wp_text_field.dart',
      'lib/widgets/wp_search_field.dart',
      'lib/widgets/tag_input.dart',
      'lib/main_smart_mode_debug.dart',
    };

    final rawTextFieldPattern = RegExp(
      r'\bTextField\s*\(|\bTextFormField\s*\(',
    );

    final stale = <String>[];
    for (final path in allowedFiles) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        continue;
      }
      if (!rawTextFieldPattern.hasMatch(file.readAsStringSync())) {
        stale.add('$path (no longer constructs a TextField/TextFormField)');
      }
    }

    expect(
      stale,
      isEmpty,
      reason:
          'Stale allowlist entries in this file — drop them: '
          '${stale.join(', ')}',
    );
  });
}
