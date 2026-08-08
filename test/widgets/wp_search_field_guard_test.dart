import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that `WpSearchField` stays the app's single search input (see its
/// library doc comment). The family this closes had six members that drifted
/// on every axis left free — three radii, three resting borders, two focus
/// signals, and a clear button in two of six places. The guard exists so the
/// seventh one can't appear silently.
///
/// The pattern targets the *idiom*, not the widget: a `TextField` whose
/// border is switched off (`border: InputBorder.none`) is one that hands its
/// chrome to a hand-rolled container around it. That is precisely the shape
/// `WpSearchField` absorbs — and the one `WpTextField` absorbs for non-search
/// fields (Batch 6, partially landed: the two History fields and the note
/// editor run through it). The non-search call sites still waiting are named
/// in the allowlist with their reason, so the list shrinks as Batch 6
/// progresses rather than being quietly reused as a dumping ground.
void main() {
  test('no source file outside WpSearchField hand-rolls a borderless '
      'TextField for search', () {
    const allowedFiles = <String, String>{
      // The component itself.
      'lib/widgets/wp_search_field.dart': 'the component',

      // Batch 6's component — the same idiom, for the fields that hold a
      // value instead of a query. It is the destination of the entries
      // below, not an offender.
      'lib/widgets/wp_text_field.dart': 'the WpTextField component',

      // Non-search text fields — these belong to Batch 6 (WpTextField), not
      // to this family. Remove each entry as that batch migrates it.
      'lib/features/feedback/feedback_page.dart': 'Batch 6 — WpTextField',
      'lib/features/history/widgets/history_notes_section.dart':
          'Batch 6 — WpTextField',
    };

    // Two files are *not* listed here on purpose, because they do not use
    // this idiom and so never trip the pattern:
    //
    // - lib/widgets/tag_input.dart — the deliberate, permanent exclusion from
    //   this family (plan Batch 1): a value-in-progress, not a query; its
    //   suffix is a commit affordance (Enter), not a clear affordance; it
    //   already lives in a central component; and it is width-constrained
    //   (60-200 px) inside a Wrap. It leaves the border to the theme default
    //   rather than switching it off.
    // - lib/features/history/widgets/history_detail_panel.dart — a Batch 6
    //   candidate until its title and transcript fields moved into
    //   `WpTextField`. It now hand-rolls no chrome at all: no `InputBorder`,
    //   no `contentPadding`, no font size. Nothing left to allow.

    // `InputBorder.none` on a `border:`/`enabledBorder:`/`focusedBorder:`
    // slot — the marker of a field that delegates its chrome to a wrapper.
    final borderlessFieldPattern = RegExp(
      r'\b(border|enabledBorder|focusedBorder)\s*:\s*InputBorder\.none',
    );

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();
      if (borderlessFieldPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Borderless TextField built outside WpSearchField. If it is a '
          'search input, route it through WpSearchField (variant: outlined '
          'in-window, capsule in an overlay). If it is not, add it to the '
          'allowlist above '
          'with the reason, so Batch 6 can find it: ${offenders.join(', ')}',
    );
  });

  test('the allowlist has no stale entries', () {
    // A path that stops existing, or stops matching, means the allowlist is
    // lying about why it exists — and a stale entry silently re-opens the
    // hole it was meant to document.
    const allowedFiles = <String>{
      'lib/widgets/wp_search_field.dart',
      'lib/widgets/wp_text_field.dart',
      'lib/features/feedback/feedback_page.dart',
      'lib/features/history/widgets/history_notes_section.dart',
    };

    final stale = <String>[];
    for (final path in allowedFiles) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        continue;
      }
      // The two components legitimately set the pattern — they are what the
      // other entries delegate their chrome *to*. Every other entry must
      // still contain it, or it has been migrated and the entry should go.
      if (path == 'lib/widgets/wp_search_field.dart') continue;
      if (path == 'lib/widgets/wp_text_field.dart') continue;
      final content = file.readAsStringSync();
      final pattern = RegExp(
        r'\b(border|enabledBorder|focusedBorder)\s*:\s*InputBorder\.none',
      );
      if (!pattern.hasMatch(content)) stale.add('$path (already migrated)');
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
