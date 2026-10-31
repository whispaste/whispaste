import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../services/modifier_key_monitor.dart';

export '../../core/config/settings_labels.dart'
    show
        leftMetaLabel,
        modifierOnlyLabel,
        modifierOnlySuggestion,
        rightMetaLabel;

/// Makes [key] the dictation trigger: hold to dictate, double tap for
/// hands-free when that is on (one trigger per action). The stored combination
/// stays as the stand-in while the key cannot be observed. On macOS the
/// recorder has already said that the key needs Input Monitoring, so the
/// system prompt follows directly.
Future<void> applyDictationSingleKey({
  required WidgetRef ref,
  required ModifierHotkey key,
  bool? isMacOS,
}) async {
  if (isMacOS ?? Platform.isMacOS) {
    await ModifierKeyMonitor().requestAccess();
  }
  await ref.read(settingsProvider.notifier).updateSettings((s) {
    return s.copyWithSections(
      hotkey: s.hotkey.copyWith(hotkeyDoubleTapKey: key.name),
    );
  });
}
