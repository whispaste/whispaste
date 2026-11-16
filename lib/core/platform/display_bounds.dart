/// Thin `screen_retriever` wrapper — isolates the plugin call so
/// [WindowPositionClamp] (window_position_clamp.dart) stays pure and
/// unit-testable, and so callers don't each repeat the visible-vs-full-size
/// fallback or the failure handling.
library;

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('DisplayBounds');

/// Work area of [d]: the visible bounds without taskbar, Dock or menu bar.
///
/// Falls back to the full [Display.size] when [Display.visibleSize] is
/// unavailable (some platforms don't report a work area distinct from the
/// full screen).
Rect _workArea(Display d) => Rect.fromLTWH(
  d.visiblePosition?.dx ?? 0,
  d.visiblePosition?.dy ?? 0,
  d.visibleSize?.width ?? d.size.width,
  d.visibleSize?.height ?? d.size.height,
);

/// Returns the visible bounds of every currently connected display, in
/// logical pixels, top-left origin.
///
/// Returns an empty list on any plugin failure — callers treat that as
/// "clamping unavailable" rather than crashing a window-restore path on a
/// missing/misbehaving native implementation.
Future<List<Rect>> currentDisplayBounds() async {
  try {
    final displays = await ScreenRetriever.instance.getAllDisplays();
    return [for (final d in displays) _workArea(d)];
  } catch (e, st) {
    _log.warning('Failed to enumerate displays for position clamping', e, st);
    return const [];
  }
}

/// Work area of the primary display, or `null` when it cannot be read. Used
/// to center a fresh window.
Future<Rect?> currentPrimaryWorkArea() async {
  try {
    return _workArea(await ScreenRetriever.instance.getPrimaryDisplay());
  } catch (e, st) {
    _log.warning('Failed to read the primary display work area', e, st);
    return null;
  }
}
