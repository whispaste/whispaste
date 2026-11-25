import 'package:flutter/foundation.dart';

import '../../core/l10n/generated/app_localizations.dart';

/// Name of the "keep running after closing the window" switch. The Mac has
/// no tray or notification area, the icon sits in the menu bar, so macOS
/// gets its own wording (#1920); Windows and Linux keep the tray wording.
String closeToTrayTitle(L10n l10n) =>
    _onMac ? l10n.settingsCloseToMenuBar : l10n.settingsCloseToTray;

/// Explanation under [closeToTrayTitle], in the same platform wording.
String closeToTraySubtitle(L10n l10n) => _onMac
    ? l10n.settingsCloseToMenuBarSubtitle
    : l10n.settingsCloseToTraySubtitle;

bool get _onMac => defaultTargetPlatform == TargetPlatform.macOS;
