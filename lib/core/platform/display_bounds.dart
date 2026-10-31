/// Thin `screen_retriever` wrapper — isolates the plugin call so
/// [WindowPositionClamp] (window_position_clamp.dart) stays pure and
/// unit-testable, and so callers don't each repeat the visible-vs-full-size
/// fallback or the failure handling.
library;

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('DisplayBounds');

/// Returns the visible bounds of every currently connected display, in
/// logical pixels, top-left origin.
///
/// Falls back to a display's full [Display.size] when [Display.visibleSize]
/// is unavailable (some platforms don't report a work area distinct from the
/// full screen). Returns an empty list on any plugin failure — callers treat
/// that as "clamping unavailable" rather than crashing a window-restore path
/// on a missing/misbehaving native implementation.
Future<List<Rect>> currentDisplayBounds() async {
  try {
    final displays = await ScreenRetriever.instance.getAllDisplays();
    return [
      for (final d in displays)
        Rect.fromLTWH(
          d.visiblePosition?.dx ?? 0,
          d.visiblePosition?.dy ?? 0,
          d.visibleSize?.width ?? d.size.width,
          d.visibleSize?.height ?? d.size.height,
        ),
    ];
  } catch (e, st) {
    _log.warning('Failed to enumerate displays for position clamping', e, st);
    return const [];
  }
}
