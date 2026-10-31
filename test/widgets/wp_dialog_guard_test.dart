import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that `lib/widgets/dialog.dart` stays the app's only dialog shell.
///
/// Three call sites used to build their own `AlertDialog` / `Dialog`, and each
/// one looked it: Material's M3 radius and title typography on the mic
/// permission prompt and the factory-reset progress dialog, a hand-mixed
/// `WpColorsDark.surfaceElevated` card with its own `maxWidth: 380` on the
/// history shortcut help. Correct tokens, own composition, different result —
/// which is exactly the failure this guard exists to catch on the next one.
///
/// Everything a call site might reach for a raw dialog for now lives in the
/// component: `dismissible: false` (barrier + `PopScope`) for a modal that
/// must not be walked away from, `useRootNavigator`, custom `actions`, and
/// `WpFormDialogShell` for form bodies.
void main() {
  test('no source file builds a raw Material dialog', () {
    const allowedFiles = <String, String>{
      // The canon itself — it may build whatever it likes.
      'lib/widgets/dialog.dart': 'the component this guard protects',
      // Debug-only entry point, never shipped in a user-facing build.
      'lib/main_smart_mode_debug.dart': 'debug harness, exempt by design',
    };

    // Constructor-shaped on purpose: `\bDialog\s*\(` does not match
    // `showDialog(` or `_SnippetDialog(` (no word boundary before `Dialog`
    // there), so the guard only fires on an actually constructed dialog.
    final rawDialogPattern = RegExp(
      r'\bAlertDialog\s*\(|\bSimpleDialog\s*\(|\bDialog\s*\(|\bDialog\.\w+\s*\(',
    );

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();
      if (rawDialogPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw Material dialog built outside lib/widgets/dialog.dart. Route it '
          'through showWpDialog / showWpConfirmDialog / showWpFormDialog '
          'instead — otherwise it carries Material defaults for radius, '
          'padding, title typography and scrim while every other dialog in '
          'the app carries WpDialog: ${offenders.join(', ')}',
    );
  });

  test('dialog.dart is where the dialog lives', () {
    // Sanity anchor for the allowlist above: if the component moves or its
    // entry points are renamed, the guard would keep passing while guarding
    // nothing.
    final dialog = File('lib/widgets/dialog.dart');
    expect(
      dialog.existsSync(),
      isTrue,
      reason: 'lib/widgets/dialog.dart is the component this guard protects',
    );
    final source = dialog.readAsStringSync();
    for (final api in const [
      'showWpDialog',
      'showWpConfirmDialog',
      'showWpFormDialog',
      'class WpFormDialogShell',
    ]) {
      expect(
        source,
        contains(api),
        reason: '$api must stay the API the guard points call sites at',
      );
    }
  });
}
