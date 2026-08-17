import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

/// The executable half of **The Earned-Green Rule** (`lib/DESIGN.md`):
/// `success` green appears only in the instant a user-initiated action has
/// just completed — never decorative, never at rest.
///
/// Armed by Ticket 13, the first of the three screen-family tickets. Ticket 05
/// specified the rule and named its check; it could not write it green,
/// because the screens that would violate it had not been through the refresh
/// yet. Tickets 14 and 15 inherit this file: every debt row below names the
/// ticket that owes its removal, and the stale-entry test at the bottom makes
/// deleting the row part of paying the debt rather than an optional tidy-up.
///
/// ## Why a component gate rather than a "is this a completion?" gate
///
/// "Just completed" is a runtime fact; no grep can see it. What a grep *can*
/// see is which kind of component a token resolves inside, and the rule's own
/// check (Ticket 05) is phrased exactly that way: `success` tokens resolve
/// only inside status-chip, badge and toast components. Those are the three
/// component families whose whole job is to report the outcome of something
/// that just happened, and they are the only ones the rule sanctions. A green
/// icon on a settings row, a green number on a dashboard, a green ring around
/// a card — all of them are surfaces that sit there being green, and all of
/// them are what this gate counts down.
///
/// ## Non-vacuity
///
/// Two guards, both mirroring `one_atmosphere_test.dart`: the tokens must
/// still exist under the names this file greps for, and no allowlist row may
/// describe a file that no longer references them.
void main() {
  /// The tokens that *are* the earned green. `success` is the flat signal
  /// colour; `successActiveFill` is its 12 % surface tint.
  const successTokens = <String>['success', 'successActiveFill'];

  /// Path → why it may resolve a `success` token. Relative to the repo root,
  /// `/`-joined.
  ///
  /// The first three rows are the rule's own sanctioned component families and
  /// are meant to stay. Everything below them is a debt with an owner.
  const allowedFiles = <String, String>{
    // ── Sanctioned: the three component families the rule names ──────────
    'lib/widgets/toast.dart':
        'the toast component itself — a toast exists only for the moment '
        'after an action and disappears on its own, which is the rule\'s '
        'definition of earned',
    'lib/widgets/status_bar.dart':
        'the app\'s status-chip group (Ticket 10): the phase dot reports what '
        'the recording pipeline just did. Noted, not waved through: '
        '`SttServerState.ready` (:616) paints green while nothing has just '
        'happened, which the rule\'s prose calls resting green even though '
        'its component scope sanctions it. Ticket 32 finding, not this '
        'ticket\'s screen',
    'lib/widgets/paste_capability_indicator.dart':
        'the paste-capability status badge — one chip reporting the outcome '
        'of the permission handshake the user just went through. Same '
        'reservation as the status bar above: `PasteCapabilityStatus.ready` '
        '(:329) is a resting state wearing the outcome colour',

    // ── Debt: screens still to come through the refresh ───────────────────
    // Each row names the ticket that owes its removal. When that ticket
    // clears the file, it deletes the row here too — the stale-entry test
    // below fails otherwise.
    'lib/features/settings/stt_model_selector.dart':
        'resting green on downloaded-model rows — Ticket 14 (settings family)',
    'lib/features/analytics/analytics_page.dart':
        'resting green on a dashboard metric — Ticket 14 (analytics)',
  };

  /// The screens the refresh has already brought through. Held separately
  /// from the allowlist on purpose: the sweep below proves they carry no
  /// `success` token *at all*, so a future edit cannot make one legitimate by
  /// adding an allowlist row — it has to reach for a status chip, a badge or
  /// a toast, which is what the rule asks for.
  ///
  /// Ticket 13 put the four list screens here. Ticket 15 added the narrative
  /// family (onboarding and About) — the same guarantee, extended rather than
  /// reinvented, which is what that ticket asked for.
  const refreshedScreenDirs = <String>[
    // Ticket 13 — the list-panel family.
    'lib/features/history',
    'lib/features/notes',
    'lib/features/snippets',
    'lib/features/replacements',
    // Ticket 15 — the narrative family.
    'lib/features/onboarding',
    'lib/features/about',
  ];

  /// The third screen Ticket 15 covers is a single widget rather than a
  /// feature directory: the 3-px bar above the content panel is the main
  /// window's whole recording surface (the in-window FAB is gone, and the
  /// floating overlay is a separate window with its own material).
  const refreshedScreenFiles = <String>[
    'lib/widgets/recording_indicator_bar.dart',
  ];

  /// Everything after a `//` on a line, so a file *discussing* success in a
  /// comment is not counted as painting it.
  final lineComment = RegExp(r'//.*$', multiLine: true);

  final successReference = RegExp(
    r'\bWpColors(?:Dark)?\.(?:' + successTokens.join('|') + r')\b',
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

  test('success green resolves only inside status, badge and toast components', () {
    final files = dartFilesUnder('lib');
    expect(
      files.length,
      greaterThan(100),
      reason:
          'the sweep found only ${files.length} Dart files under lib/ — an '
          'empty offender list below would pass vacuously',
    );

    final offenders = <String>[];
    for (final relPath in files) {
      if (relPath == 'lib/core/theme/colors.dart') continue; // the definitions
      if (allowedFiles.containsKey(relPath)) continue;

      final source = File(
        relPath,
      ).readAsStringSync().replaceAll(lineComment, '');
      if (successReference.hasMatch(source)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These files resolve a `success` token outside a status-chip, badge '
          'or toast component: ${offenders.join(', ')}. Green that is not '
          'reporting a just-finished action is decoration, and decoration '
          'spends the one colour the app has left for "that worked". Show the '
          'outcome through `WpToast.show(..., type: WpToastType.success)` or '
          'through a status chip; if a call site is genuinely one of the three '
          'sanctioned component families, add it to `allowedFiles` with its '
          'reason.',
    );
  });

  test('the refreshed screens carry no success token at all', () {
    final offenders = <String>[];
    for (final dir in refreshedScreenDirs) {
      for (final relPath in dartFilesUnder(dir)) {
        final source = File(
          relPath,
        ).readAsStringSync().replaceAll(lineComment, '');
        if (successReference.hasMatch(source)) offenders.add(relPath);
      }
    }
    for (final relPath in refreshedScreenFiles) {
      final file = File(relPath);
      expect(file.existsSync(), isTrue, reason: '$relPath must exist');
      final source = file.readAsStringSync().replaceAll(lineComment, '');
      if (successReference.hasMatch(source)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Verlauf, Notizen, Snippets and Ersetzungen (Ticket 13) plus '
          'onboarding, About and the recording bar (Ticket 15) came through '
          'the refresh with every green on them coming from a transient '
          '`WpToastType.success` toast — i.e. from a component that cannot '
          'exist at rest. These files broke that: ${offenders.join(', ')}. '
          'Adding an `allowedFiles` row is not the fix here; the fix is to '
          'let the toast (or a status chip) carry the outcome.',
    );
  });

  test('the guarded tokens still exist under these names', () {
    // Anti-vacuum guard: the gate matches on token *names*, so renaming
    // `successActiveFill` would leave it green while guarding nothing.
    final colors = File('lib/core/theme/colors.dart');
    expect(colors.existsSync(), isTrue);
    final source = colors.readAsStringSync();

    for (final token in successTokens) {
      expect(
        source,
        contains('$token ='),
        reason:
            '`$token` is no longer declared in colors.dart. The Earned-Green '
            'gate greps for that name — rename it there and the gate silently '
            'stops guarding anything.',
      );
    }

    // And that they are still the green the rule is about, not a token that
    // kept its name through a hue change.
    for (final color in <int>[
      WpColors.success.toARGB32(),
      WpColors.successActiveFill.toARGB32(),
    ]) {
      expect(
        color & 0x00FFFFFF,
        WpColors.success.toARGB32() & 0x00FFFFFF,
        reason: 'the success family drifted apart into two different hues',
      );
    }
  });

  test('the allowlist has no stale entries', () {
    // A path that no longer exists, or no longer references a success token,
    // is an exemption nobody is using. This is the half that puts Tickets 14
    // and 15 on the hook: clearing a screen without deleting its row fails
    // here rather than leaving the countdown looking longer than it is.
    final stale = <String>[];
    allowedFiles.forEach((path, _) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing)');
        return;
      }
      final source = file.readAsStringSync().replaceAll(lineComment, '');
      if (!successReference.hasMatch(source)) {
        stale.add('$path (no longer resolves a success token)');
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
