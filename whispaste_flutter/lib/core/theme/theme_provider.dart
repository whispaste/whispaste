import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ThemeMode state — persists the user's choice of Dark / Light / System.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  /// Set a specific theme mode.
  void setTheme(ThemeMode mode) => state = mode;

  /// Quick toggle between dark and light (ignores system).
  void toggleDarkLight() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

/// Primary theme mode provider.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Convenience: true when the effective theme is dark.
final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  // For ThemeMode.system we'd need the platform brightness; default to dark.
  return mode != ThemeMode.light;
});
