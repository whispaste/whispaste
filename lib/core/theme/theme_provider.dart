import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/settings_provider.dart';

/// Primary theme mode provider — derived from [settingsProvider].
final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.value?.themeMode ?? ThemeMode.dark;
});

/// Convenience: true when the effective theme is dark.
final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  // For ThemeMode.system we'd need the platform brightness; default to dark.
  return mode != ThemeMode.light;
});
