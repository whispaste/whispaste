import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/settings_provider.dart';

/// Primary locale provider — derived from [settingsProvider].
final localeProvider = Provider<Locale>((ref) {
  final settings = ref.watch(settingsProvider);
  final code = settings.value?.locale ?? 'en';
  return Locale(code);
});
