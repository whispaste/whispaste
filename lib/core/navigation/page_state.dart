/// Navigation state providers — shared between [app.dart] and any widget or
/// service that needs to read or drive the active page / settings scroll target.
///
/// Extracted from [app.dart] to break a circular import: previously every file
/// that needed [activePageProvider] or [settingsScrollTargetProvider] imported
/// [app.dart], while [app.dart] itself imports those same files.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Active page provider
// ---------------------------------------------------------------------------

/// Tracks which top-level page is currently shown in the app shell.
class ActivePageNotifier extends Notifier<String> {
  @override
  String build() => 'history';

  void setPage(String id) => state = id;
}

final activePageProvider = NotifierProvider<ActivePageNotifier, String>(
  ActivePageNotifier.new,
);

// ---------------------------------------------------------------------------
// Settings scroll-target provider
// ---------------------------------------------------------------------------

/// Optional settings section to scroll to after navigating to Settings.
/// Set before calling [activePageProvider.notifier.setPage]('settings') —
/// SettingsPage consumes & clears it on mount.
class SettingsScrollTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

final settingsScrollTargetProvider =
    NotifierProvider<SettingsScrollTargetNotifier, String?>(
      SettingsScrollTargetNotifier.new,
    );
