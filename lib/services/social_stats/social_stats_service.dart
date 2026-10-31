/// Fetches the public project numbers for the "Mitmachen" block. The block
/// asks once per app session, when the Übersicht shows it, and at most once
/// per [kSocialStatsAttemptGap]. Never on start-up, never on the hotkey path.
/// Any failure leaves the block without numbers; nothing is reported to the
/// user and nothing goes to crash reporting.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/app_urls.dart';
import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import 'social_stats_logic.dart';

final _log = AppLogger('SocialStats');

/// Where the last answer and the last attempt are kept (app settings).
const _kSnapshotKey = 'social_stats_snapshot';
const _kLastAttemptKey = 'social_stats_last_attempt';

abstract interface class SocialStatsStore {
  Future<SocialStatsSnapshot?> readSnapshot();
  Future<DateTime?> readLastAttempt();
  Future<void> writeSnapshot(SocialStatsSnapshot snapshot);
  Future<void> writeLastAttempt(DateTime at);
}

/// Stores both values in the local app settings database.
class DatabaseSocialStatsStore implements SocialStatsStore {
  const DatabaseSocialStatsStore(this._db);

  final HistoryDatabase _db;

  @override
  Future<SocialStatsSnapshot?> readSnapshot() async =>
      decodeSocialStatsSnapshot(await _db.readAppSetting(_kSnapshotKey));

  @override
  Future<DateTime?> readLastAttempt() async {
    final raw = await _db.readAppSetting(_kLastAttemptKey);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> writeSnapshot(SocialStatsSnapshot snapshot) =>
      _db.writeAppSetting(_kSnapshotKey, encodeSocialStatsSnapshot(snapshot));

  @override
  Future<void> writeLastAttempt(DateTime at) => _db.writeAppSetting(
    _kLastAttemptKey,
    at.toUtc().millisecondsSinceEpoch.toString(),
  );
}

/// One network attempt. Returns null on any failure.
abstract interface class SocialStatsFetcher {
  Future<SocialStatsSnapshot?> fetch(DateTime now);
}

/// GET [kSocialStatsUrl] with a short timeout and the plain product user agent
/// (no version, no identifier).
class HttpSocialStatsFetcher implements SocialStatsFetcher {
  const HttpSocialStatsFetcher(
    this._client, {
    this.timeout = const Duration(seconds: 5),
  });

  final http.Client _client;
  final Duration timeout;

  @override
  Future<SocialStatsSnapshot?> fetch(DateTime now) async {
    try {
      final response = await _client
          .get(
            Uri.parse(kSocialStatsUrl),
            headers: const {'User-Agent': 'WhisPaste'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return parseSocialStats(response.body, fetchedAt: now);
    } on Object {
      return null;
    }
  }
}

final socialStatsStoreProvider = Provider<SocialStatsStore>(
  (ref) => DatabaseSocialStatsStore(ref.watch(historyDatabaseProvider)),
);

final socialStatsFetcherProvider = Provider<SocialStatsFetcher>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpSocialStatsFetcher(client);
});

/// The numbers the "Mitmachen" block shows. Starts empty; [refreshIfDue]
/// fills it from the stored answer at once and asks the server only when due.
class SocialStatsNotifier extends Notifier<SocialStatsView> {
  bool _askedThisSession = false;

  @override
  SocialStatsView build() => const SocialStatsView();

  /// Call when the block is shown. Shows the stored numbers at once, then
  /// fetches only if the last attempt is a day old or more. Failures keep the
  /// stored numbers or none.
  Future<void> refreshIfDue() async {
    if (_askedThisSession) return;
    _askedThisSession = true;
    try {
      final store = ref.read(socialStatsStoreProvider);
      final now = clock.now().toUtc();
      state = socialStatsView(await store.readSnapshot(), now);
      if (!socialStatsFetchDue(
        lastAttempt: await store.readLastAttempt(),
        now: now,
      )) {
        return;
      }
      await store.writeLastAttempt(now);
      final fresh = await ref.read(socialStatsFetcherProvider).fetch(now);
      if (fresh == null) return;
      await store.writeSnapshot(fresh);
      state = socialStatsView(fresh, now);
    } on Object catch (error) {
      // Storage or network trouble is expected offline: the block shows no
      // numbers, so this stays a debug-level note, never a Sentry event.
      _log.info('Social stats unavailable: $error');
    }
  }
}

final socialStatsProvider =
    NotifierProvider<SocialStatsNotifier, SocialStatsView>(
      SocialStatsNotifier.new,
    );
