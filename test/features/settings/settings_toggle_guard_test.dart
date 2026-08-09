import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that every on/off toggle goes through `settingsToggle()`.
///
/// This family never diverged visually — `switchTheme` in `theme.dart` is set
/// globally, so a raw `Switch` and the helper render the same pixels today.
/// That is exactly why the guard is worth having: the day the helper grows a
/// size, a tone or a semantics default, the three call sites that bypassed it
/// would silently keep the old look, and nobody would notice until a
/// screenshot review. The helper is the seam; this test keeps it the only one.
///
/// Note the helper is still named and located as settings-local
/// (`lib/features/settings/settings_widgets.dart`) while two of its five
/// non-settings call sites live in onboarding and replacements. Hoisting it to
/// `lib/widgets/` is a Masterplan item, not this guard's business — the guard
/// tracks the idiom, and will keep working after the move as long as the
/// allowlist path follows it.
void main() {
  test('no source file builds a raw Switch outside the helper', () {
    const allowedFiles = <String, String>{
      'lib/features/settings/settings_widgets.dart':
          'the helper — it is the one place a Switch may be constructed',
    };

    // `(?<![\w$])` keeps identifiers that merely *end* in "Switch" out of the
    // match — `_waitForDefaultInputSwitch(` in `audio_service.dart` is a real
    // method that would otherwise trip this on every run.
    final rawSwitchPattern = RegExp(r'(?<![\w$])Switch\s*\(');

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();
      if (rawSwitchPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw Switch built outside settingsToggle(). Use '
          'settingsToggle(value: …, onChanged: …) — it accepts a null '
          'onChanged for the disabled case and forwards a key onto the '
          'Switch itself: ${offenders.join(', ')}',
    );
  });

  test('the allowlist has no stale entries', () {
    // A path that stops existing, or stops matching, means the allowlist is
    // lying about why it exists.
    const allowedFiles = <String>{
      'lib/features/settings/settings_widgets.dart',
    };

    final rawSwitchPattern = RegExp(r'(?<![\w$])Switch\s*\(');
    final stale = <String>[];
    for (final path in allowedFiles) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (missing — did settingsToggle move?)');
        continue;
      }
      if (!rawSwitchPattern.hasMatch(file.readAsStringSync())) {
        stale.add('$path (no longer constructs a Switch)');
      }
    }

    expect(
      stale,
      isEmpty,
      reason:
          'Stale allowlist entries in this file — drop or repoint them: '
          '${stale.join(', ')}',
    );
  });
}
