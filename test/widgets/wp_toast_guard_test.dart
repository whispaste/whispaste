import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that no raw `SnackBar` and no classic toast (`WpToast`, removed in
/// #456) appears in `lib/`.
///
/// The leak this closes was small but visible: two call sites still raised a
/// Material `SnackBar` — bottom-centre, square, its own typography, its own
/// timing — next to an app that says everything else in the toast language
/// (bottom-right card, accent line, severity icon, Reduce-Motion-aware
/// animation). Worse, a `SnackBar` has no severity axis, so
/// `paste_capability_indicator.dart` rendered "reset done" and "reset failed"
/// identically.
///
/// The allowlist is deliberately empty: the app builds its own notices and
/// never touches `ScaffoldMessenger`, so there is no legitimate
/// `showSnackBar` anywhere in `lib/`. If one ever becomes legitimate, add it
/// here with the reason rather than deleting the guard.
void main() {
  test('no source file raises a raw SnackBar', () {
    const allowedFiles = <String, String>{};

    // Both halves of the idiom: the messenger call and the widget itself.
    // Matching only `showSnackBar` would miss a `SnackBar` handed to a
    // `ScaffoldMessengerState` held in a variable, which is how the two
    // `voice_note` call sites hid from the original inventory grep.
    final snackBarPattern = RegExp(r'\bshowSnackBar\s*\(|\bSnackBar\s*\(');

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(relPath)) continue;
      final content = entity.readAsStringSync();
      if (snackBarPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw SnackBar found. Route it through showWpNotice / '
          'showWpPageNotice instead — the kind is the part a SnackBar '
          'cannot express: ${offenders.join(', ')}',
    );
  });

  test('the classic toast does not return', () {
    expect(
      File('lib/widgets/toast.dart').existsSync(),
      isFalse,
      reason:
          'The classic toast is gone (#456); use showWpNotice, '
          'showWpPageNotice, showWpAppError or showWpDictationMessage.',
    );
    final pattern = RegExp(r'\bWpToast(Type|PopupObserver)?\b');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (pattern.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path.replaceAll(r'\', '/'));
      }
    }
    expect(offenders, isEmpty, reason: 'WpToast is back in: $offenders');
  });
}
