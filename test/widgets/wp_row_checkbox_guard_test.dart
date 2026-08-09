import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that `WpRowCheckbox` stays the app's only multi-select checkbox
/// (CONTEXT.md §5.5.13).
///
/// The family this closes had two members: the history list and compact
/// views each built their own `Checkbox` at a different size (24 vs 18 px).
/// `WpRowCheckbox` absorbed both into a single 24 px styling block — the
/// accessible size, and the one that matches Material's own checkbox extent
/// so the tick keeps its intended stroke weight instead of being scaled
/// down. This guard exists so a third hand-rolled `Checkbox` — in a new list
/// view, or a reintroduced one in an old — can't appear silently.
///
/// The allowlist is deliberately down to one entry: `wp_row_checkbox.dart`
/// itself is where the single legitimate `Checkbox(` construction lives;
/// everything that needs a row-level multi-select checkbox reaches for the
/// component around it instead. Not part of this family: any other
/// selection affordance (the notes favourite star, row hover actions) — this
/// guard is about the multi-select checkbox specifically, not selection UI
/// in general.
void main() {
  test('no source file outside WpRowCheckbox builds a raw Checkbox', () {
    const allowedFiles = <String, String>{
      // The component itself — it may build whatever it likes.
      'lib/widgets/wp_row_checkbox.dart': 'the component this guard protects',
    };

    // Constructor-shaped: `\b` keeps identifiers that merely contain
    // "Checkbox" (a `showCheckbox` flag, say) out of the match.
    final rawCheckboxPattern = RegExp(r'\bCheckbox\s*\(');

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();
      if (rawCheckboxPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw Checkbox built outside WpRowCheckbox. Route it through '
          'WpRowCheckbox(value: …, onChanged: …, isDark: …) instead — '
          'otherwise it carries a different size/styling than every other '
          'row selection checkbox in the app: ${offenders.join(', ')}',
    );
  });

  test('WpRowCheckbox is where the checkbox lives', () {
    // Sanity anchor for the allowlist above: if the component moves or is
    // renamed, the guard would keep passing while guarding nothing.
    final component = File('lib/widgets/wp_row_checkbox.dart');
    expect(
      component.existsSync(),
      isTrue,
      reason:
          'lib/widgets/wp_row_checkbox.dart is the component this guard '
          'protects',
    );
    expect(
      component.readAsStringSync(),
      contains('class WpRowCheckbox'),
      reason:
          'WpRowCheckbox must still be the API the guard points call sites '
          'at',
    );
  });

  test('the history list and compact views use WpRowCheckbox', () {
    // Sanity anchor for the two call sites the family closed (Ticket 02):
    // if either regresses to a raw Checkbox, this fails loudly instead of
    // the broad grep above silently widening its offender list.
    const callSites = <String>[
      'lib/features/history/widgets/history_list_tile.dart',
      'lib/features/history/widgets/history_compact_view.dart',
    ];

    for (final path in callSites) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path must exist');
      expect(
        file.readAsStringSync(),
        contains('WpRowCheckbox('),
        reason: '$path must select through WpRowCheckbox',
      );
    }
  });
}
