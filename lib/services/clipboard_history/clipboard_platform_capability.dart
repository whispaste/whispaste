import 'package:flutter/foundation.dart';

/// Which clipboard-history behavior a platform supports.
///
/// macOS/Windows poll or subscribe to clipboard-change notifications and can
/// maintain a rolling buffer. GNOME/Wayland (via XWayland) has no reliable
/// background clipboard-monitoring story, so Linux only ever gets a single
/// snapshot taken when the panel opens.
enum ClipboardHistoryCapability { rollingHistory, snapshotOnly }

ClipboardHistoryCapability clipboardHistoryCapabilityFor(
  TargetPlatform platform,
) {
  switch (platform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return ClipboardHistoryCapability.rollingHistory;
    case TargetPlatform.linux:
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return ClipboardHistoryCapability.snapshotOnly;
  }
}
