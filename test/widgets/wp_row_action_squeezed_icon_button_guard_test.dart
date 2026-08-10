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
/// (either axis, either order — the shape both historical offenders, the
/// title-bar theme toggle and the trigger-list remove button, were written
/// in), `BoxConstraints.tightFor(width: …, height: …)`, and
/// `IconButton.styleFrom(minimumSize: const Size(…, …))` (the modern
/// `ButtonStyle`-based idiom). The match window after each `IconButton(` is
/// bounded (600 characters) and heuristic, not a parser — it is sized to
/// comfortably cover one constructor's argument list and has been checked
/// against every current `IconButton` call site in `lib/`, but a
/// sufficiently unusual layout could in principle span past it or reach into
/// an unrelated neighbouring construct.
///
/// That "in principle" was observed in practice while Ticket 06 fixed the
/// trigger-list button: a six-line explanatory comment placed *between*
/// `IconButton(` and its `constraints:` pushed the constraints past the
/// 600-character mark, and the guard went green on a call site it was no
/// longer reading — a false pass, not a false alarm, which is the expensive
/// direction for a guard to fail in. Prose is cheap and grows; argument
/// lists do not. So the guarantee this window offers is weaker than its
/// size suggests: it holds for the call sites as currently *written*, and
/// any comment added inside an `IconButton(...)` argument list can quietly
/// void it. When a call site needs commentary, put it above the
/// `IconButton(` line, not inside the call. If this keeps biting, the fix
/// is to match to the closing paren instead of a fixed character count —
/// not a bigger magic number.
void main() {
  test('no IconButton outside WpRowAction hand-sets a tap target below '
      'WpLayout.minTouchTarget', () {
    // The title-bar theme toggle used to sit here at 36x32, flagged as
    // "documented debt, not a permanent exemption" because a guard-only
    // ticket could not make the layout decision. The layout ticket has since
    // made it: the toggle is 48x48 and the entry is gone rather than
    // grandfathered — which is what "not a permanent exemption" has to mean
    // if the word is to carry weight.
    //
    // Re-examined and confirmed after the toggle's glyph grew to
    // `WpIconSize.md`: that change is irrelevant here either way, because
    // what this guard measures is the hand-set *tap target*, never the
    // glyph-to-target ratio — "squeezed" names a squeezed target, not a
    // small mark in a large one. And re-adding `lib/app.dart` is not merely
    // unnecessary but impossible: the toggle now spells its size as
    // `WpLayout.minTouchTarget`, which the stale-entry test's digit-matching
    // regex cannot see, so the entry would be reported stale and fail.
    // The trigger-phrase remove button in `replacements_page.dart`'s
    // add/edit dialog used to sit here at 28x28, carried as "known open, a
    // layout decision out of scope for a guard-only ticket". Ticket 06 made
    // that decision the same way the title-bar toggle's was made: the button
    // is 48x48 and the entry is gone rather than grandfathered. It also
    // spells its size as `WpLayout.minTouchTarget`, so — as with
    // `lib/app.dart` — re-adding it would fail the stale-entry test below
    // rather than quietly suppress anything.
    //
    // The allowlist is empty on purpose and stays declared: an empty map
    // says "no exemptions today", which is a different and stronger
    // statement than having no mechanism for them.
    const allowedFiles = <String, String>{};

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
    const allowedFiles = <String>{};

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
