/// Smoke test: every appearance uses the bundled faces (ADR 0018) — Hanken
/// Grotesk for UI text, Bricolage Grotesque for the title roles — with Inter
/// as first fallback for scripts neither face covers (Cyrillic, Hebrew).
///
/// This is the machine-verifiable proxy for cross-platform font parity: the
/// faces are bundled assets, so the family names guarantee identical
/// rendering on Windows, macOS and Linux by construction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';

void main() {
  final themes = <String, ThemeData>{
    'light': wpThemeFor(wpLightColors),
    'dark': wpThemeFor(wpDarkColors),
    'navy': wpThemeFor(wpNavyColors),
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group('$name theme fonts', () {
      test('body roles use Hanken Grotesk with Inter fallback', () {
        for (final style in [
          theme.textTheme.bodyMedium,
          theme.textTheme.bodyLarge,
          theme.textTheme.labelMedium,
        ]) {
          expect(style?.fontFamily, kWpUiFont);
          expect(style?.fontFamilyFallback?.first, 'Inter');
        }
      });

      test('title roles use Bricolage Grotesque', () {
        for (final style in [
          theme.textTheme.headlineLarge,
          theme.textTheme.headlineMedium,
          theme.textTheme.titleLarge,
        ]) {
          expect(style?.fontFamily, kWpDisplayFont);
          expect(style?.fontFamilyFallback?.first, 'Inter');
        }
      });

      test('button text styles use the UI face', () {
        for (final style in [
          theme.elevatedButtonTheme.style,
          theme.textButtonTheme.style,
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
        ]) {
          expect(style?.textStyle?.resolve({})?.fontFamily, kWpUiFont);
        }
      });
    });
  }
}
