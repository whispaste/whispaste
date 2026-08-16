import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

/// The in-plane half of **The Depth-Source Rule** (`lib/DESIGN.md`): on the
/// app's one remaining (dark) theme, depth comes from the brightness delta
/// between fills and from `cardEdgeHighlight` — **no shadow at all**. A
/// surface that genuinely floats above the plane (dialog, toast, dropdown,
/// the floating overlay window) still gets exactly one; a card, a row or a
/// band that sits *in* the plane gets none.
///
/// Armed by Ticket 13 on the four list-panel screens. Ticket 04's check in
/// `wcag_contrast_test.dart` already guards the *glow* half of the rule (a
/// coloured shadow at offset 0 fails there); nothing guarded the "no shadow
/// at all" half, which is how `history_card_view.dart` kept an ambient lift
/// under every grid tile eight months after the rule said otherwise.
///
/// ## Why a per-directory sweep rather than an app-wide one
///
/// The rule is only enforceable where a ticket has actually walked the
/// screen and classified every surface as in-plane or floating. An app-wide
/// gate would need an allowlist of every dialog and popup in the app on day
/// one, and an allowlist that large is a list nobody reads. Instead the
/// sweep grows with the refresh: [refreshedScreenDirs] mirrors the list in
/// `earned_green_test.dart`, and Tickets 14 and 16 add their screens here
/// when they land — the same "extended, not reinvented" shape Ticket 15 used
/// for the other two rule checks.
///
/// ## Non-vacuity
///
/// Two guards, both mirroring `one_atmosphere_test.dart`: the shadow tokens
/// must still exist under the names this file greps for, and the sweep must
/// find a plausible number of Dart files.
void main() {
  /// Directories whose every surface has been classified by a screen ticket.
  ///
  /// Ticket 13 — the list-panel family. The history detail panel is part of
  /// the history screen and therefore covered by the same row.
  const refreshedScreenDirs = <String>[
    'lib/features/history',
    'lib/features/notes',
    'lib/features/snippets',
    'lib/features/replacements',
  ];

  /// The shared primitive the four screens' rows are made of. It lives
  /// outside a feature directory but is the canonical statement of the rule
  /// ("## Why there is no shadow (Ticket 08)"), so a regression there would
  /// reach all four screens at once.
  const refreshedScreenFiles = <String>[
    'lib/widgets/wp_list_tile_surface.dart',
  ];

  /// Floating surfaces inside those directories: they sit *above* the plane,
  /// so the rule grants them exactly one shadow. Path → why it floats.
  const floatingSurfaces = <String, String>{
    'lib/features/history/widgets/tag_management_dialog.dart':
        'A modal dialog on its own barrier — it floats above the whole plane, '
        'so the rule grants it the one shadow. It spends it on '
        '`Material(elevation: 8)`, the same lift the shared `WpDialog` shell '
        'paints, which is why the surface underneath is `floatingSurface` '
        'rather than a frost fill.',
  };

  /// Everything after a `//` on a line, so a file *discussing* shadows in a
  /// comment (`history_helpers.dart` carries two retraction notes about
  /// exactly this rule) is not counted as painting one.
  final lineComment = RegExp(r'//.*$', multiLine: true);

  /// Every way a shadow can reach the screen, not just the decoration route:
  /// a named token, a hand-rolled `BoxShadow(...)`, `Material`'s own
  /// `elevation:`, and the two `CustomPainter` spellings — `drawShadow` and a
  /// blurred fill standing in for one. The first review of this gate matched
  /// only the first two and therefore called the family "shadow-free" while
  /// `tag_management_dialog.dart` was lifting itself with `elevation: 8`; a
  /// grep narrower than the ways a shadow can be painted is a gate that
  /// reports on its own regex rather than on the screens.
  ///
  /// `elevation: 0` is the *absence* of a lift and matches nothing, as does
  /// `boxShadow: null` — the explicit "this one carries no lift" marker
  /// `history_helpers.dart` uses.
  final shadowReference = RegExp(
    r'\bWpShadows\.\w+'
    r'|\bBoxShadow\s*\('
    r'|\belevation:\s*[1-9]'
    r'|\bdrawShadow\s*\('
    r'|\bMaskFilter\.blur\b',
  );

  List<String> dartFilesUnder(String dir) {
    final directory = Directory(dir);
    expect(directory.existsSync(), isTrue, reason: '$dir must exist');
    return [
      for (final entity in directory.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.replaceAll(r'\', '/'),
    ];
  }

  test('the refreshed screens paint no in-plane shadow', () {
    final swept = <String>[];
    final offenders = <String>[];

    for (final dir in refreshedScreenDirs) {
      swept.addAll(dartFilesUnder(dir));
    }
    for (final relPath in refreshedScreenFiles) {
      expect(File(relPath).existsSync(), isTrue, reason: '$relPath must exist');
      swept.add(relPath);
    }

    expect(
      swept.length,
      greaterThan(20),
      reason:
          'the sweep found only ${swept.length} Dart files — an empty '
          'offender list below would pass vacuously',
    );

    for (final relPath in swept) {
      if (floatingSurfaces.containsKey(relPath)) continue;
      final source = File(
        relPath,
      ).readAsStringSync().replaceAll(lineComment, '');
      if (shadowReference.hasMatch(source)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These files paint a shadow on a surface that lives in the content '
          'plane: ${offenders.join(', ')}. On dark, a black shadow on a '
          'near-black ground is mud rather than lift, and it muddies the one '
          'ambient gradient the frost fills exist to let through. Separate '
          'the surface with fill brightness (`cardFill` → `cardFillElevated`) '
          'or with `cardEdgeHighlight` instead. If a surface genuinely floats '
          'above the plane, add it to `floatingSurfaces` with the reason.',
    );
  });

  test('the guarded tokens still exist under these names', () {
    // Anti-vacuum guard: the gate matches on token *names*, so renaming
    // `WpShadows.card` would leave it green while guarding nothing.
    final tokens = File('lib/core/theme/tokens.dart');
    expect(tokens.existsSync(), isTrue);
    final source = tokens.readAsStringSync();

    for (final name in <String>['subtle', 'card', 'elevated']) {
      expect(
        source,
        contains('$name ='),
        reason:
            '`WpShadows.$name` is no longer declared in tokens.dart. The '
            'Depth-Source gate greps for that name — rename it there and the '
            'gate silently stops guarding anything.',
      );
    }

    // And that they are still shadows with a nonzero offset, i.e. the thing
    // the rule keeps out of the plane rather than a glow (which Ticket 04's
    // offset audit in `wcag_contrast_test.dart` owns).
    for (final shadow in <List<dynamic>>[
      ['subtle', WpShadows.subtle],
      ['card', WpShadows.card],
      ['elevated', WpShadows.elevated],
    ]) {
      final layers = shadow[1] as List;
      expect(
        layers,
        isNotEmpty,
        reason: 'WpShadows.${shadow[0]} became an empty list',
      );
    }
  });

  test('the floating allowlist has no stale entries', () {
    final stale = <String>[];
    floatingSurfaces.forEach((path, _) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        return;
      }
      final source = file.readAsStringSync().replaceAll(lineComment, '');
      if (!shadowReference.hasMatch(source)) {
        stale.add('$path (no longer paints a shadow)');
      }
    });

    expect(
      stale,
      isEmpty,
      reason:
          'Allowlist entries that guard nothing: ${stale.join(', ')}. Remove '
          'them — every row is a standing claim that a surface floats, and a '
          'row that no longer describes reality makes the remaining ones look '
          'equally stale.',
    );
  });
}
