/// Test helper: pins the settings navigation to one area (ticket).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/smart_mode/smart_mode_page.dart';

class _FixedSettingsArea extends SettingsAreaNotifier {
  _FixedSettingsArea(this._area);

  final SettingsArea _area;

  @override
  SettingsArea build() => _area;
}

/// Override that opens the settings page on [area] instead of the default.
Override settingsAreaAt(SettingsArea area) =>
    settingsAreaProvider.overrideWith(() => _FixedSettingsArea(area));

class _PendingLegacyKeychain extends LegacyKeychainNotifier {
  @override
  LegacyKeychainState build() =>
      const LegacyKeychainState(pending: ['legacy-key']);
}

/// Override for a left-over old-keychain entry: the privacy page then shows
/// its migration row (#1243), which the default state hides.
Override legacyKeychainPending() =>
    legacyKeychainProvider.overrideWith(_PendingLegacyKeychain.new);

/// Stands in for the app shell in a search-jump test: the Settings page until
/// a jump hands a Smart Mode row over (`activePageProvider` = `smartMode`),
/// then the Smart Mode page, as `lib/app.dart` does. Without it the Settings
/// page would stay mounted and take the handed-over row back in a loop.
class SettingsOrSmartModeHost extends ConsumerWidget {
  const SettingsOrSmartModeHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(activePageProvider) == 'smartMode'
      ? const SmartModePage()
      : const SettingsPage();
}
