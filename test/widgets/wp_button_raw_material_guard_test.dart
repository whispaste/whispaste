import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Anchors that `WpButton` stays the app's single push-button (see its
/// library doc comment): no call site outside `wp_button.dart` itself may
/// construct a raw `ElevatedButton`/`OutlinedButton`/`TextButton`/
/// `FilledButton` (including their `.icon`/`.tonal`/`.tonalIcon` forms).
/// `theme.dart`'s `ElevatedButtonThemeData`/`...styleFrom(...)` calls don't
/// match this pattern — they configure the theme, they don't construct a
/// button — so they stay the sanctioned safety net for Material-internal
/// widgets (DatePicker, SnackBar actions, …) without needing an allowlist
/// entry here.
void main() {
  test('no source file outside wp_button.dart constructs a raw Material '
      'button (Elevated/Outlined/Text/FilledButton)', () {
    const allowedFiles = <String>{'lib/widgets/wp_button.dart'};

    final rawButtonPattern = RegExp(
      r'\b(ElevatedButton|OutlinedButton|TextButton|FilledButton)'
      r'(\.icon|\.tonal|\.tonalIcon)?\(',
    );

    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.contains(relPath)) continue;
      final content = entity.readAsStringSync();
      if (rawButtonPattern.hasMatch(content)) offenders.add(relPath);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw Material button constructed outside WpButton — route it '
          'through WpButton instead (or WpHeroButton for the gradient '
          'hero CTA): ${offenders.join(', ')}',
    );
  });
}
