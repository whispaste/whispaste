import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/modifier_key_monitor.dart';
import '../../widgets/dialog.dart';

/// The modifier key recommended on this platform: Fn on macOS (the Globe key
/// does nothing in WhisPaste), right Control elsewhere, because right Alt is
/// AltGr on many European Windows and Linux layouts.
String modifierOnlySuggestion({required bool isMacOS}) =>
    isMacOS ? 'fn' : 'rightControl';

/// Display name of a modifier-only choice; the empty name means off.
String modifierOnlyLabel(L10n l10n, String name) => switch (name) {
  'rightControl' => l10n.settingsModifierRightControl,
  'rightAlt' => l10n.settingsModifierRightAlt,
  'rightMeta' => l10n.settingsModifierRightMeta,
  'fn' => l10n.settingsModifierFn,
  _ => l10n.settingsModifierOnlyNone,
};

/// Stores [name] as the modifier-only dictation key ("" turns it off). On
/// macOS a new key first explains Input Monitoring; declining keeps the
/// current setting. The system request follows the explanation.
Future<void> applyModifierOnlyHotkey({
  required BuildContext context,
  required WidgetRef ref,
  required String name,
  bool? isMacOS,
}) async {
  final l10n = L10n.of(context);
  if (name.isNotEmpty && (isMacOS ?? Platform.isMacOS)) {
    final proceed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsModifierInputTitle,
      message: l10n.settingsModifierInputBody,
      confirmLabel: l10n.settingsModifierInputContinue,
      cancelLabel: l10n.settingsModifierInputLater,
    );
    if (!proceed) return;
    await ModifierKeyMonitor().requestAccess();
  }
  await ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          hotkey: s.hotkey.copyWith(hotkeyModifierOnly: name),
        ),
      );
}
