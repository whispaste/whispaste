/// Screen-reader announcements for the whole app. Call [announce] instead of
/// `SemanticsService.sendAnnouncement` (guarded by
/// test/core/accessibility/announce_guard_test.dart).
///
/// The macOS engine never replies on `flutter/accessibility`: its handler in
/// FlutterEngine.mm (`setUpAccessibilityChannel`) drops the reply block,
/// while Windows and Linux always send an empty reply. Each
/// `sendAnnouncement` there leaves its reply callback pending, held by the
/// engine as a persistent handle for the rest of the app's life. On macOS the
/// announcement therefore goes out without a reply callback.
///
/// The branch reads [defaultTargetPlatform], which is the running OS in the
/// app. In tests it defaults to Android, so the announcement reaches the test
/// messenger (`tester.takeAnnouncements`) on every host; the host's
/// `Platform.isMacOS` would hide it from tests run on a Mac.
library;

import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

void announce(FlutterView view, String message, TextDirection textDirection) {
  final event = AnnounceSemanticsEvent(message, textDirection, view.viewId);
  if (defaultTargetPlatform != TargetPlatform.macOS) {
    SemanticsService.sendAnnouncement(view, message, textDirection);
    return;
  }
  view.platformDispatcher.sendPlatformMessage(
    SystemChannels.accessibility.name,
    SystemChannels.accessibility.codec.encodeMessage(event.toMap()),
    null,
  );
}
