import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'floating_button_support.dart';

const _channel = MethodChannel('com.whispaste.floating_button');

/// Asks the native Linux host whether its GDK backend is X11 (native or
/// XWayland). A failed call counts as unavailable, so the switch is disabled
/// with its explanation rather than doing nothing.
Future<FloatingButtonSupport> probeLinuxFloatingButtonSupport({
  Map<String, String>? environment,
}) async {
  var x11Backend = false;
  try {
    final caps = await _channel.invokeMapMethod<String, Object?>(
      'getCapabilities',
    );
    x11Backend = caps?['x11'] == true;
  } on PlatformException {
    x11Backend = false;
  } on MissingPluginException {
    x11Backend = false;
  }
  return linuxFloatingButtonSupport(
    x11Backend: x11Backend,
    session: linuxSessionTypeFrom(environment ?? Platform.environment),
  );
}

/// Support state of the floating button on this desktop. Only Linux needs the
/// runtime probe; Windows and macOS are fully supported.
final floatingButtonSupportProvider = FutureProvider<FloatingButtonSupport>((
  ref,
) async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return FloatingButtonSupport.full;
  }
  return probeLinuxFloatingButtonSupport();
});
