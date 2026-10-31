/// Sidecar mirror of the persisted appearance mode (AR-21).
///
/// Same contract as `core/l10n/persisted_locale.dart`: the main engine keeps
/// the mode in a plain file next to the database, and the secondary render
/// engines (snippet picker, side panel) read it without touching SQLite. See
/// [writeLocaleMirror] for why those engines must never open a database.
///
/// The file lives in the app-support directory, the same place as the locale
/// mirror, so it works inside the Mac App Store sandbox and MSIX without any
/// extra entitlement.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/path_service.dart' as paths;
import '../config/settings_enums.dart';
import '../logging/app_logger.dart';
import 'appearance.dart';
import 'colors.dart';

final _log = AppLogger('PersistedAppearance');

/// Overrides [appearanceMirrorPath] in tests, so a test never touches the real
/// `~/Library/Application Support/WhisPaste` directory.
@visibleForTesting
String? appearanceMirrorPathOverride;

/// Path of the sidecar file mirroring the persisted `appearance` setting.
String appearanceMirrorPath() =>
    appearanceMirrorPathOverride ?? p.join(paths.appDataDir(), 'appearance');

/// Reads the mirrored appearance mode. A missing, unreadable or unknown value
/// yields [AppearanceMode.navy], the default (WP-50b).
///
/// Synchronous and free of any dependency other than `dart:io`, for the same
/// reason as `readLocaleMirror`: the callers run during `initState` of a
/// secondary engine that has no plugins and must not touch SQLite.
AppearanceMode readAppearanceMirror() {
  try {
    final file = File(appearanceMirrorPath());
    if (!file.existsSync()) return AppearanceMode.navy;
    return AppearanceMode.fromValue(file.readAsStringSync().trim());
  } catch (e) {
    _log.debug('Failed to read appearance mirror: $e');
    return AppearanceMode.navy;
  }
}

/// Mirrors the appearance [value] (an [AppearanceMode.value]) next to the
/// database. Best-effort and idempotent, like [writeLocaleMirror]: a null or
/// blank value leaves the previous mirror in place, an unknown value is stored
/// as `navy`, and an unchanged value is not rewritten.
void writeAppearanceMirror(String? value) {
  // Same test guard as writeLocaleMirror: a unit test writing settings must
  // not overwrite the real mirror of the user's install.
  if (appearanceMirrorPathOverride == null && _isTestEnvironment) return;
  try {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return;
    final mode = AppearanceMode.fromValue(raw).value;
    final file = File(appearanceMirrorPath());
    if (file.existsSync() && file.readAsStringSync().trim() == mode) return;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(mode, flush: true);
  } catch (e) {
    _log.debug('Failed to write appearance mirror: $e');
  }
}

/// Activates the colour set for the mirrored appearance in this engine and
/// returns it. [platform] is the engine's own platform brightness, which only
/// matters for [AppearanceMode.system].
WpThemeColors resolvePersistedAppearance(Brightness platform) {
  final colors = colorsForAppearance(readAppearanceMirror(), platform);
  WpColors.activate(colors);
  return colors;
}

/// Same detection `writeLocaleMirror` uses: `flutter_test` installs this zone
/// value for every test it runs.
bool get _isTestEnvironment => kIsWeb || Zone.current[#test.declarer] != null;
