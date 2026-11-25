/// Accessible name of the menu bar icon on macOS (#1926).
///
/// tray_manager creates the NSStatusItem without a name and puts the state
/// into the tooltip only; VoiceOver then announced just "status menu" and
/// Voice Control could not target WhisPaste. `TrayPanelHost.swift` names the
/// item's button on request. Windows and Linux name their tray icon through
/// the tooltip / indicator title already, so the call is macOS-only.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';

final _log = AppLogger('StatusItemName');

/// The channel of `TrayPanelHost.swift`, which also names the status item.
const MethodChannel kTrayPanelChannel = MethodChannel(
  'com.whispaste.tray_panel',
);

/// The name the menu bar icon carries: the app name. The state stays in the
/// tooltip, which macOS reads as help.
const String kStatusItemAccessibleName = 'WhisPaste';

/// Names the menu bar icon once it exists. Never throws: a missing name only
/// costs the accessible label, never the tray.
Future<void> nameMacStatusItem({
  MethodChannel channel = kTrayPanelChannel,
}) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) return;
  try {
    await channel.invokeMethod<Object?>('nameStatusItem', {
      'label': kStatusItemAccessibleName,
    });
  } on PlatformException catch (e) {
    _log.debug('Status item name not set: $e');
  } on MissingPluginException catch (e) {
    _log.debug('Status item name not set: $e');
  }
}
