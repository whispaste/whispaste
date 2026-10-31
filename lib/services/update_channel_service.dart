/// Update channel — the **independent** release feed selector (`stable` /
/// `beta`) that decides which Sparkle/WinSparkle appcast the self-updater
/// requests at runtime (PRD Säule *Beta- & Stable-Release-Kanäle*, §5.2/§5.3).
///
/// **Domain boundary:** this is NOT the [DeployChannel] (store/installer/
/// portable/linux — *how* the app was installed, Matomo Dimension 4). The
/// update channel is a separate concept: *which release feed* a direct
/// (non-store) build polls. The two must never be merged. Store builds have no
/// Sparkle feed at all (their update channel is telemetry-reported as `n/a`).
///
/// Persisted via SharedPreferences (key [_keyUpdateChannel]); default is
/// [UpdateChannel.stable]. Exposed as an [AsyncNotifier] because reading the
/// persisted value is asynchronous.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('UpdateChannel');

// ---------------------------------------------------------------------------
// SharedPreferences key
// ---------------------------------------------------------------------------

const _keyUpdateChannel = 'update_channel';

// ---------------------------------------------------------------------------
// Enum
// ---------------------------------------------------------------------------

/// Which release feed the self-updater polls.
///
/// The [UpdateChannel.name] (`stable`/`beta`) is the canonical token stored in
/// SharedPreferences and sent as Matomo Dimension 6 — categorical values only.
enum UpdateChannel {
  /// Production feed (`…/releases/latest/download/appcast.xml`).
  stable,

  /// Pre-release feed, served from the `beta-appcast-pointer` branch (see
  /// `auto_updater_service.dart`'s `_betaAppcastFeedUrl` for why it's a
  /// branch, not a `releases/download/...` URL).
  beta,
}

/// Parses a persisted token into an [UpdateChannel], defaulting to
/// [UpdateChannel.stable] for any missing/unknown value. Top-level so it is
/// unit-testable in isolation.
UpdateChannel parseUpdateChannel(String? stored) {
  if (stored == UpdateChannel.beta.name) return UpdateChannel.beta;
  return UpdateChannel.stable;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Persists the chosen [UpdateChannel] across app restarts.
///
/// Loads the stored value once in [build]; [setChannel] writes it through to
/// SharedPreferences. I/O failures never throw — a broken prefs read degrades
/// to [UpdateChannel.stable], a broken write still flips the in-memory state so
/// the running session picks the right feed (the next restart re-reads prefs).
class UpdateChannelNotifier extends AsyncNotifier<UpdateChannel> {
  @override
  Future<UpdateChannel> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return parseUpdateChannel(prefs.getString(_keyUpdateChannel));
    } on Exception catch (e) {
      _log.debug('Update channel load failed (defaulting to stable): $e');
      return UpdateChannel.stable;
    }
  }

  /// Switches the update channel and persists it.
  Future<void> setChannel(UpdateChannel channel) async {
    state = AsyncData(channel);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUpdateChannel, channel.name);
    } on Exception catch (e) {
      _log.debug('Update channel persist failed (non-fatal): $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// The persisted update channel (`stable`/`beta`). Async because it reads
/// SharedPreferences on first access; consumers that need a synchronous value
/// fall back to [UpdateChannel.stable] via `.value ?? UpdateChannel.stable`.
final updateChannelProvider =
    AsyncNotifierProvider<UpdateChannelNotifier, UpdateChannel>(
      UpdateChannelNotifier.new,
    );
