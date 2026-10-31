import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that `WpToast` stays the app's only transient notification.
///
/// The leak this closes was small but visible: two call sites still raised a
/// Material `SnackBar` — bottom-centre, square, its own typography, its own
/// timing — next to an app that says everything else in the toast language
/// (bottom-right card, accent line, severity icon, Reduce-Motion-aware
/// animation). Worse, a `SnackBar` has no severity axis, so
/// `paste_capability_indicator.dart` rendered "reset done" and "reset failed"
/// identically.
///
/// The allowlist is deliberately empty: `toast.dart` builds its own overlay
/// and never touches `ScaffoldMessenger`, so there is no legitimate
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
          'Raw SnackBar built outside WpToast. Route it through '
          'WpToast.show(context, message: …, type: WpToastType.success / '
          'error / warning / info) instead — the type is the part a SnackBar '
          'cannot express: ${offenders.join(', ')}',
    );
  });

  test('WpToast is where the toast lives', () {
    // Sanity anchor for the empty allowlist above: if `toast.dart` ever moves
    // or is renamed, the guard would keep passing while guarding nothing.
    final toast = File('lib/widgets/toast.dart');
    expect(
      toast.existsSync(),
      isTrue,
      reason: 'lib/widgets/toast.dart is the component this guard protects',
    );
    expect(
      toast.readAsStringSync(),
      contains('class WpToast'),
      reason: 'WpToast must still be the API the guard points call sites at',
    );
  });
}
