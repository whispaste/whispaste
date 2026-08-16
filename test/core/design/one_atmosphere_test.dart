import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

/// The executable half of **The One-Atmosphere Rule** (`lib/DESIGN.md`):
/// exactly one light source, painted at exactly one place.
///
/// Armed by Ticket 08, which was the second of the two prerequisites the rule
/// named for itself — Ticket 06 removed the frame watermark, Ticket 08 put the
/// card primitives on the shared frost so they stop needing a ground of their
/// own. Until both were true the gate could only have been written red.
///
/// ## What is gated, and why it is names rather than shapes
///
/// The tempting rule is structural — "no widget builds a gradient with three
/// or more stops". It does not work here, in both directions:
///
///  * `WpColors.surfaceGradient` has **two** stops and is a background, so a
///    stop-count rule would have waved through the exact violations this gate
///    was written to count down (the two detail panels, cleared by Ticket 09).
///  * `navChipGradient`, `navChipGradientHover` and `navPillActiveGradient`
///    have **three** stops each and are chip fills — objects standing on the
///    ground, not the ground. A stop-count rule would fail them for existing.
///
/// So the gate names the three tokens that *are* the atmosphere and asserts
/// that nothing outside the sanctioned places paints one. What counts is the
/// token's job, which is exactly what the rule is about.
///
/// ## The allowlist is a countdown, not an amnesty
///
/// It has already been counted down once: the notes and history detail panels
/// painted `surfaceGradient` as their own ground until Ticket 09 moved their
/// writing surfaces onto the card material, and their rows are gone rather
/// than grandfathered. What is left is three genuine exceptions, each naming
/// why it may paint a ground. Following `wp_toast_guard_test.dart`: if a new
/// call site ever becomes legitimate, add it here **with its reason** rather
/// than widening the pattern or deleting the guard.
void main() {
  /// The tokens that *are* the app's atmosphere — the ground itself, in the
  /// three shapes it is painted in.
  const groundTokens = <String>[
    'frameGradient',
    'warmSurfaceGradient',
    'surfaceGradient',
  ];

  /// Path → why it may paint a ground. Relative to the repo root, `/`-joined.
  const allowedFiles = <String, String>{
    // The one place. `app.dart` paints the frame's ambient and the content
    // plane that sits on it; everything else in the app stands on those two.
    'lib/app.dart': 'the single light source the whole rule is about',

    // Frozen overlay: a separate always-on-top window with its own
    // liquid-glass material and its own golden suite. It does not sit on the
    // main window's atmosphere, so it has to bring one.
    'lib/snippet_picker_render_entrypoint.dart':
        'the floating overlay is a second window, not a second light source '
        'in this one',

    // *The Preflight-Screen Exception* (lib/DESIGN.md): the blocking
    // low-RAM screen renders *instead of* the app, never inside it. It is the
    // app's ground painted where `app.dart` is not running — the rule's
    // subject, not a violation of it.
    'lib/widgets/insufficient_ram_screen.dart':
        'stands in for the app rather than inside it (Preflight-Screen '
        'Exception)',
  };

  /// Everything after a `//` on a line, so that a file *discussing* the
  /// ambient in a comment (e.g. `settings_page.dart`, which explains which
  /// gradient its page lands on) is not counted as painting one.
  final lineComment = RegExp(r'//.*$', multiLine: true);

  final groundReference = RegExp(
    r'\bWpColors(?:Dark)?\.(?:' + groundTokens.join('|') + r')\b',
  );

  test('no widget outside app.dart paints a second atmosphere', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (relPath == 'lib/core/theme/colors.dart') continue;
      if (relPath.startsWith('lib/widgets/floating_overlay/')) continue;
      if (allowedFiles.containsKey(relPath)) continue;

      final source = entity.readAsStringSync().replaceAll(lineComment, '');
      if (groundReference.hasMatch(source)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These files paint one of the app\'s ground gradients '
          '(${groundTokens.join(', ')}) outside the one place that may: '
          '${offenders.join(', ')}. A second background gradient is a felt '
          'second light source, and it competes with the accent for the '
          'user\'s attention — put the card material on the surface instead '
          '(WpColors.cardFill / cardFillElevated / cardEdgeHighlight), which '
          'is translucent precisely so the one atmosphere shows through it. '
          'If a call site is genuinely legitimate, add it to `allowedFiles` '
          'with its reason.',
    );
  });

  test('the guarded tokens still exist under these names', () {
    // Anti-vacuum guard. The gate matches on token *names*, so renaming
    // `warmSurfaceGradient` would leave it green while guarding nothing at
    // all. Bind the names to real declarations, and to the values a caller
    // would actually reach for.
    final colors = File('lib/core/theme/colors.dart');
    expect(colors.existsSync(), isTrue);
    final source = colors.readAsStringSync();

    for (final token in groundTokens) {
      expect(
        source,
        contains('$token ='),
        reason:
            '`$token` is no longer declared in colors.dart. The One-Atmosphere '
            'gate greps for that name — rename it there and the gate silently '
            'stops guarding anything.',
      );
    }

    // And that they really are gradients, i.e. still the thing being gated.
    expect(WpColors.frameGradient.colors, isNotEmpty);
    expect(WpColors.warmSurfaceGradient.colors, isNotEmpty);
    expect(WpColors.surfaceGradient.colors, isNotEmpty);
  });

  test('the allowlist has no stale entries', () {
    // A path that no longer exists, or no longer references a ground token,
    // is an exemption nobody is using. This is the half that forced the two
    // Ticket-09 rows out: fixing the panels without deleting their rows fails
    // here rather than leaving the list looking stale.
    final stale = <String>[];
    allowedFiles.forEach((path, _) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        return;
      }
      final source = file.readAsStringSync().replaceAll(lineComment, '');
      if (!groundReference.hasMatch(source)) {
        stale.add('$path (no longer paints a ground)');
      }
    });

    expect(
      stale,
      isEmpty,
      reason:
          'Allowlist entries that guard nothing: ${stale.join(', ')}. Remove '
          'them — the list is a countdown of known debts, and a row that no '
          'longer describes reality makes the remaining ones look equally '
          'stale.',
    );
  });
}
