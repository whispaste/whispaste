/// Smoke test: verifies that both WhisPaste themes use Inter as the primary
/// font family.
///
/// Flutter propagates the ThemeData(fontFamily:) value by applying it to the
/// default typography TextTheme and then merging with the custom _textTheme().
/// Because our _textTheme() TextStyles do not set an explicit fontFamily,
/// the merge preserves 'Inter' from the default. Checking bodyMedium (a style
/// we own) and bodyLarge (another custom role) gives two independent probes.
///
/// This is the machine-verifiable proxy for AC3 (cross-platform font parity):
/// Inter is a bundled asset, so fontFamily == 'Inter' guarantees identical
/// rendering on Windows, macOS and Linux by construction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/theme.dart';

void main() {
  group('Theme fontFamily — Inter bundled', () {
    test('wpDarkTheme textTheme uses Inter for body roles', () {
      final theme = wpDarkTheme();
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.textTheme.bodyLarge?.fontFamily, 'Inter');
    });

    test('wpLightTheme textTheme uses Inter for body roles', () {
      final theme = wpLightTheme();
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.textTheme.bodyLarge?.fontFamily, 'Inter');
    });

    test('wpDarkTheme textTheme uses Inter for headline roles', () {
      final theme = wpDarkTheme();
      expect(theme.textTheme.headlineLarge?.fontFamily, 'Inter');
      expect(theme.textTheme.headlineMedium?.fontFamily, 'Inter');
    });

    test('elevated button textStyle uses Inter', () {
      final theme = wpDarkTheme();
      final style = theme.elevatedButtonTheme.style;
      final resolved = style?.textStyle?.resolve({});
      expect(resolved?.fontFamily, 'Inter');
    });

    test('text button textStyle uses Inter', () {
      final theme = wpDarkTheme();
      final style = theme.textButtonTheme.style;
      final resolved = style?.textStyle?.resolve({});
      expect(resolved?.fontFamily, 'Inter');
    });
  });
}
