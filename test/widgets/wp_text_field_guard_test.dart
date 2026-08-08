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
/// That divergence is not fully closed yet outside those three fields —
/// several settings/dialog inputs still hand-roll a `TextField` with their
/// own `style`/`decoration` rather than going through `WpTextField`. Each is
/// named below with a reason, not silently allowed, so the list is a to-do
/// rather than a hiding place. Ticket 01 (`WpTextField`) scoped itself to
/// the History detail panel and the Notes editor only — it did not claim
/// these call sites, so their presence here is expected, not a regression.
///
/// Explicitly **not** part of this family: nothing else in `lib/` builds a
/// `TextField` directly once the entries below migrate — there is no third
/// idiom this guard is meant to leave standing.
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

      // Still-open call sites — pre-existing hand-rolled TextFields that
      // Ticket 01 did not claim (it scoped itself to the History detail
      // panel and the Notes editor). Each hand-rolls its own style/
      // decoration today; migrating any of them to WpTextField is a
      // visual/layout decision, not this guard's job.
      'lib/features/settings/settings_widgets.dart':
          'settingsApiKeyField()/settingsTextField() helpers — pre-Batch 6, '
          'not migrated to WpTextField yet',
      'lib/features/settings/sections/stt_section.dart':
          'custom-vocabulary field — pre-Batch 6, not migrated yet',
      'lib/features/snippets/snippets_page.dart':
          'snippet title/body fields in the add/edit dialog — pre-Batch 6, '
          'not migrated yet',
      'lib/features/replacements/replacements_page.dart':
          'trigger-phrase list and replacement field in the add/edit '
          'dialog — pre-Batch 6, not migrated yet',
      'lib/features/feedback/feedback_page.dart':
          'Batch 6 — WpTextField (also named in the WpSearchField guard '
          'allowlist for the same reason)',
      'lib/features/history/widgets/history_notes_section.dart':
          'Batch 6 — WpTextField (also named in the WpSearchField guard '
          'allowlist for the same reason)',
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
      'lib/features/settings/settings_widgets.dart',
      'lib/features/settings/sections/stt_section.dart',
      'lib/features/snippets/snippets_page.dart',
      'lib/features/replacements/replacements_page.dart',
      'lib/features/feedback/feedback_page.dart',
      'lib/features/history/widgets/history_notes_section.dart',
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
