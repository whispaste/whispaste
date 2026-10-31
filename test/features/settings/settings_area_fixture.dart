/// Test helper: pins the settings navigation to one area (WP-23b).
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:whispaste/features/settings/settings_areas.dart';

class _FixedSettingsArea extends SettingsAreaNotifier {
  _FixedSettingsArea(this._area);

  final SettingsArea _area;

  @override
  SettingsArea build() => _area;
}

/// Override that opens the settings page on [area] instead of the default.
Override settingsAreaAt(SettingsArea area) =>
    settingsAreaProvider.overrideWith(() => _FixedSettingsArea(area));
