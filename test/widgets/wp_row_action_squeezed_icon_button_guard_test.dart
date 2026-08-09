import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that a raw `IconButton` never hand-sets a tap target smaller than
/// `WpLayout.minTouchTarget` (48 px, `lib/DESIGN.md` line ~207: "All
/// interactive elements meet the 48px minimum touch target") outside
/// `WpRowAction` (CONTEXT.md's row-action family, Ticket 02).
///
/// The family this closes: history's list/card/compact views, notes and
/// replacements/snippets each used to build their own row-action
/// `IconButton`, and each picked its own undersized `BoxConstraints` — the
/// drift Ticket 02 closed by centralising every row action in `WpRowAction`,
/// which offers exactly two sizes: 44 px standard and a 28 px `dense`
/// variant reserved for rows too narrow for 44 (documented in
/// `WpRowAction`'s own library comment, and itself a deliberate, reviewed
/// exception to the 48 px rule — not something this guard is meant to flag).
/// Critically, `WpRowAction` does not build a Material `IconButton` at all —
/// its hit surface is `Semantics` + `MouseRegion` + `InkWell` — so any
/// `IconButton` that is *also* paired with a hand-set sub-minimum tap target
/// is, by construction, not going through the component. That pairing is
/// the guard's target.
///
/// This is deliberately **not** a general `IconButton` guard —
/// `lib/DESIGN.md` counts 29 legitimate bare `IconButton` call sites app-wide
/// ("icon-only affordances stay `IconButton`"), and a blanket guard would be
/// wrong; an `IconButton` at or above 48 px never trips this one. It is also
/// not a `PopupMenuButton` guard: two menu triggers (`history_detail_panel
/// .dart`, `history_search_filter_bar.dart`) carry the same undersized
/// `BoxConstraints` shape but are a different widget with no dedicated
/// component to route through yet (see Ticket 09's PRD note) — every pattern
/// below only matches inside an `IconButton(...)` call, so they never trip
/// it.
///
/// Three shapes of "hand-set a smaller tap target" are checked, because a
/// single-shape guard would let the next offender through in whichever shape
/// it didn't cover: a literal `BoxConstraints(minWidth: …, minHeight: …)`
/// (either axis, either order — this was the shape of both known offenders
/// below), `BoxConstraints.tightFor(width: …, height: …)`, and
/// `IconButton.styleFrom(minimumSize: const Size(…, …))` (the modern
/// `ButtonStyle`-based idiom). The match window after each `IconButton(` is
/// bounded (600 characters) and heuristic, not a parser — it is sized to
/// comfortably cover one constructor's argument list and has been checked
/// against every current `IconButton` call site in `lib/`, but a
/// sufficiently unusual layout could in principle span past it or reach into
/// an unrelated neighbouring construct.
void main() {
  test('no IconButton outside WpRowAction hand-sets a tap target below '
      'WpLayout.minTouchTarget', () {
    const allowedFiles = <String, String>{
      // Status bar dark/light toggle (36x32) — documented debt, not a
      // permanent exemption. It predates this guard, sits outside the
      // WpRowAction family (not one of the four list views Ticket 02
      // migrated), and resizing a shipped status-bar control is a layout
      // decision this guard-only ticket may not make.
      'lib/app.dart':
          'status bar theme toggle at 36x32 — below the 48px '
          'rule, known debt, not a list row',

      // Trigger-phrase remove button (28x28) inside the add/edit dialog's
      // dynamic trigger list — not one of the four list views (history
      // list/card/compact, notes, replacements, snippets rows) that
      // Ticket 02 migrated to WpRowAction. Known open per Ticket 09;
      // migrating it is a layout decision, out of scope for a guard-only
      // ticket.
      'lib/features/replacements/replacements_page.dart':
          'trigger-list remove button in the add/edit dialog — known open, '
          'not part of the WpRowAction family Ticket 02 closed',
    };

    const minTouchTarget = 48; // WpLayout.minTouchTarget
    const windowSize = 600;

    bool hasSqueezedConstraints(String window) {
      for (final m in RegExp(
        r'BoxConstraints\s*\(([^()]*)\)',
      ).allMatches(window)) {
        for (final n in RegExp(
          r'min(?:Width|Height):\s*(\d+)',
        ).allMatches(m.group(1)!)) {
          if (int.parse(n.group(1)!) < minTouchTarget) return true;
        }
      }
      for (final m in RegExp(
        r'BoxConstraints\.tightFor\s*\(([^()]*)\)',
      ).allMatches(window)) {
        for (final n in RegExp(
          r'(?:width|height):\s*(\d+)',
        ).allMatches(m.group(1)!)) {
          if (int.parse(n.group(1)!) < minTouchTarget) return true;
        }
      }
      for (final m in RegExp(
        r'minimumSize:\s*(?:const\s+)?Size\s*\(([^()]*)\)',
      ).allMatches(window)) {
        for (final n in RegExp(r'(\d+)').allMatches(m.group(1)!)) {
          if (int.parse(n.group(1)!) < minTouchTarget) return true;
        }
      }
      return false;
    }

    final iconButtonPattern = RegExp(r'IconButton\s*\(');

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();

      var hit = false;
      for (final m in iconButtonPattern.allMatches(content)) {
        final start = m.end;
        final end = (start + windowSize < content.length)
            ? start + windowSize
            : content.length;
        if (hasSqueezedConstraints(content.substring(start, end))) {
          hit = true;
          break;
        }
      }
      if (hit) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'IconButton with a hand-set tap target below the 48px minimum '
          'outside WpRowAction. Route row-level hover actions through '
          'WpRowAction(dense: …) instead of hand-setting a smaller tap '
          'target, or add the file to the allowlist above with a reason: '
          '${offenders.join(', ')}',
    );
  });

  test('the allowlist has no stale entries', () {
    const allowedFiles = <String>{
      'lib/app.dart',
      'lib/features/replacements/replacements_page.dart',
    };

    const minTouchTarget = 48;
    const windowSize = 600;

    bool hasSqueezedConstraints(String window) {
      for (final m in RegExp(
        r'BoxConstraints\s*\(([^()]*)\)',
      ).allMatches(window)) {
        for (final n in RegExp(
          r'min(?:Width|Height):\s*(\d+)',
        ).allMatches(m.group(1)!)) {
          if (int.parse(n.group(1)!) < minTouchTarget) return true;
        }
      }
      for (final m in RegExp(
        r'BoxConstraints\.tightFor\s*\(([^()]*)\)',
      ).allMatches(window)) {
        for (final n in RegExp(
          r'(?:width|height):\s*(\d+)',
        ).allMatches(m.group(1)!)) {
          if (int.parse(n.group(1)!) < minTouchTarget) return true;
        }
      }
      for (final m in RegExp(
        r'minimumSize:\s*(?:const\s+)?Size\s*\(([^()]*)\)',
      ).allMatches(window)) {
        for (final n in RegExp(r'(\d+)').allMatches(m.group(1)!)) {
          if (int.parse(n.group(1)!) < minTouchTarget) return true;
        }
      }
      return false;
    }

    final iconButtonPattern = RegExp(r'IconButton\s*\(');

    final stale = <String>[];
    for (final path in allowedFiles) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        continue;
      }
      final content = file.readAsStringSync();
      var hit = false;
      for (final m in iconButtonPattern.allMatches(content)) {
        final start = m.end;
        final end = (start + windowSize < content.length)
            ? start + windowSize
            : content.length;
        if (hasSqueezedConstraints(content.substring(start, end))) {
          hit = true;
          break;
        }
      }
      if (!hit) stale.add('$path (no longer matches the pattern)');
    }

    expect(
      stale,
      isEmpty,
      reason:
          'Stale allowlist entries in this file — drop them: '
          '${stale.join(', ')}',
    );
  });

  test('WpRowAction is where row actions live', () {
    // Sanity anchor: if the component moves or is renamed, the guard would
    // keep passing while guarding nothing.
    final component = File('lib/widgets/wp_row_action.dart');
    expect(
      component.existsSync(),
      isTrue,
      reason:
          'lib/widgets/wp_row_action.dart is the component this guard '
          'protects',
    );
    final source = component.readAsStringSync();
    expect(
      source,
      contains('class WpRowAction'),
      reason:
          'WpRowAction must still be the API the guard points call sites at',
    );
    expect(
      source,
      isNot(contains('IconButton(')),
      reason:
          'WpRowAction builds its own hit surface (Semantics/MouseRegion/'
          'InkWell), not a Material IconButton — if that changes, this '
          'guard\'s pattern needs a rethink, not a silent pass',
    );
  });
}
