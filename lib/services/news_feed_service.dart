/// Fetches the feeds of the "Neuigkeiten" block (#1568) and keeps their
/// entries.
///
/// Driven by the block alone: nothing runs until [NewsFeedNotifier.setActive]
/// is called with `true` (the block is on the page and the window is active),
/// and the timer stops when it is called with `false` or the block leaves the
/// page. Each feed is asked at most once per [kNewsFetchInterval]; the
/// interval counts from the last attempt, also a failed one, so an offline
/// machine does not retry in a loop. Never at start-up, never on the hotkey
/// path. Failures keep the last entries and stay quiet.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import '../core/overview/news_feed.dart';

final _log = AppLogger('NewsFeed');

const _kFeedsKey = 'overview_news_feeds';
const _kRecordsKey = 'overview_news_records';

/// Where the feed list and the last results are kept.
abstract interface class NewsFeedStore {
  Future<List<String>> readFeeds();
  Future<void> writeFeeds(List<String> feeds);
  Future<Map<String, NewsFeedRecord>> readRecords();
  Future<void> writeRecords(Map<String, NewsFeedRecord> records);
}

/// Both values in the local app settings table.
class DatabaseNewsFeedStore implements NewsFeedStore {
  const DatabaseNewsFeedStore(this._db);

  final HistoryDatabase _db;

  @override
  Future<List<String>> readFeeds() async =>
      newsFeedsFromStored(await _db.readAppSetting(_kFeedsKey));

  @override
  Future<void> writeFeeds(List<String> feeds) =>
      _db.writeAppSetting(_kFeedsKey, newsFeedsToStored(feeds));

  @override
  Future<Map<String, NewsFeedRecord>> readRecords() async =>
      newsRecordsFromStored(await _db.readAppSetting(_kRecordsKey));

  @override
  Future<void> writeRecords(Map<String, NewsFeedRecord> records) =>
      _db.writeAppSetting(_kRecordsKey, newsRecordsToStored(records));
}

/// One network attempt for one feed. Returns null on any failure.
abstract interface class NewsFeedFetcher {
  Future<NewsFeed?> fetch(Uri url);
}

/// GET with a time limit for the whole answer, a size limit checked while the
/// body arrives (a larger answer is cut off unread), the plain product user
/// agent (no version, no identifier, no cookie) and the parse in a separate
/// isolate, so a large feed never stalls the window.
class HttpNewsFeedFetcher implements NewsFeedFetcher {
  const HttpNewsFeedFetcher(
    this._client, {
    this.timeout = const Duration(seconds: 10),
    this.maxBytes = kNewsFeedMaxBytes,
  });

  final http.Client _client;
  final Duration timeout;
  final int maxBytes;

  @override
  Future<NewsFeed?> fetch(Uri url) async {
    try {
      final body = await _download(url).timeout(timeout);
      if (body == null) return null;
      return await _parseInIsolate(body, url);
    } on Object catch (e) {
      _log.debug('Feed not read: ${url.host}: $e');
      return null;
    }
  }

  Future<String?> _download(Uri url) async {
    final request = http.Request('GET', url)
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.addAll(const {
        'User-Agent': 'WhisPaste',
        'Accept':
            'application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8',
      });
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      return null;
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      // Leaving the loop cancels the subscription, which closes the
      // connection: the rest of an oversized answer is never read.
      if (bytes.length > maxBytes) return null;
    }
    return decodeNewsBody(bytes.takeBytes());
  }
}

/// Top level on purpose: the closure sent to the isolate captures only the
/// body and the address, never the fetcher with its HTTP client.
Future<NewsFeed> _parseInIsolate(String body, Uri url) =>
    Isolate.run(() => parseNewsFeed(body, feedUrl: url));

/// UTF-8, unless the XML declaration names a Latin-1 family encoding.
/// Malformed sequences become replacement characters instead of failing.
String decodeNewsBody(List<int> bytes) {
  final head = latin1
      .decode(bytes.take(200).toList(), allowInvalid: true)
      .toLowerCase();
  final latin = RegExp(
    r'''encoding\s*=\s*["'](iso-8859-1|latin-?1|windows-1252|us-ascii)["']''',
  ).hasMatch(head);
  return latin
      ? latin1.decode(bytes, allowInvalid: true)
      : utf8.decode(bytes, allowMalformed: true);
}

final newsFeedStoreProvider = Provider<NewsFeedStore>(
  (ref) => DatabaseNewsFeedStore(ref.watch(historyDatabaseProvider)),
);

final newsFeedFetcherProvider = Provider<NewsFeedFetcher>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpNewsFeedFetcher(client);
});

/// What the block and the sources dialog show.
class NewsFeedState {
  const NewsFeedState({
    this.loaded = false,
    this.feeds = const [],
    this.records = const {},
    this.fetching = false,
  });

  /// False until the stored feeds were read.
  final bool loaded;
  final List<String> feeds;
  final Map<String, NewsFeedRecord> records;

  /// A fetch round is running.
  final bool fetching;

  List<NewsItem> get items => newsShownItems(feeds: feeds, records: records);

  /// Every feed was asked and none has an entry from a success: offline, or
  /// the addresses are not feeds.
  bool get allFailed =>
      feeds.isNotEmpty &&
      feeds.every((f) {
        final r = records[f];
        return r != null && r.failed && r.items.isEmpty;
      });

  NewsFeedState copyWith({
    bool? loaded,
    List<String>? feeds,
    Map<String, NewsFeedRecord>? records,
    bool? fetching,
  }) => NewsFeedState(
    loaded: loaded ?? this.loaded,
    feeds: feeds ?? this.feeds,
    records: records ?? this.records,
    fetching: fetching ?? this.fetching,
  );
}

class NewsFeedNotifier extends Notifier<NewsFeedState> {
  Timer? _timer;
  bool _active = false;
  bool _running = false;
  Future<void>? _loading;

  @override
  NewsFeedState build() {
    ref.onDispose(_stopTimer);
    return const NewsFeedState();
  }

  NewsFeedStore get _store => ref.read(newsFeedStoreProvider);

  /// Reads the stored feeds and entries once; the block shows them at once.
  Future<void> _ensureLoaded() => _loading ??= () async {
    try {
      final feeds = await _store.readFeeds();
      final records = await _store.readRecords();
      if (!ref.mounted) return;
      state = state.copyWith(loaded: true, feeds: feeds, records: records);
    } on Object catch (e) {
      _log.debug('News feeds not loaded (non-fatal): $e');
      if (ref.mounted) state = state.copyWith(loaded: true);
    }
  }();

  /// The block is on the page and the window active (`true`), or not. Only
  /// while active are feeds asked, each when it is due.
  void setActive({required bool active}) {
    if (active == _active) return;
    _active = active;
    if (active) {
      unawaited(_ensureLoaded().then((_) => _fetchDue()));
    } else {
      _stopTimer();
    }
  }

  /// Adds a feed address chosen by the user. Returns the problem when it
  /// cannot be added; the new feed is asked at once while the block is
  /// active.
  Future<NewsFeedUrlProblem?> addFeed(String input) async {
    await _ensureLoaded();
    final problem = newsFeedUrlProblem(input, state.feeds);
    if (problem != null) return problem;
    final feeds = [...state.feeds, normalizeNewsFeedUrl(input)!];
    state = state.copyWith(feeds: feeds);
    await _write(() => _store.writeFeeds(feeds));
    if (_active) unawaited(_fetchDue());
    return null;
  }

  /// Removes a feed together with its stored entries.
  Future<void> removeFeed(String url) async {
    await _ensureLoaded();
    final feeds = [...state.feeds]..remove(url);
    final records = {...state.records}..remove(url);
    state = state.copyWith(feeds: feeds, records: records);
    await _write(() => _store.writeFeeds(feeds));
    await _write(() => _store.writeRecords(records));
    if (feeds.isEmpty) _stopTimer();
  }

  /// Asks every feed that is due, one after the other, then waits for the
  /// next one. Stops as soon as the block is no longer active.
  Future<void> _fetchDue() async {
    if (_running || !_active || !ref.mounted) return;
    _running = true;
    _stopTimer();
    try {
      final due = newsFeedsDue(
        feeds: state.feeds,
        records: state.records,
        now: clock.now().toUtc(),
      );
      if (due.isNotEmpty) state = state.copyWith(fetching: true);
      for (final url in due) {
        if (!_active || !ref.mounted) break;
        final now = clock.now().toUtc();
        final fetched = await ref
            .read(newsFeedFetcherProvider)
            .fetch(Uri.parse(url));
        if (!ref.mounted) return;
        // Removed while it was being asked: forget the answer.
        if (!state.feeds.contains(url)) continue;
        final old = state.records[url] ?? const NewsFeedRecord();
        final record = fetched == null
            ? NewsFeedRecord(
                source: old.source,
                items: old.items,
                lastAttempt: now,
                lastSuccess: old.lastSuccess,
                failed: true,
              )
            : NewsFeedRecord(
                source: fetched.source,
                items: fetched.items,
                lastAttempt: now,
                lastSuccess: now,
              );
        final records = {...state.records, url: record};
        state = state.copyWith(records: records);
        await _write(() => _store.writeRecords(records));
      }
    } finally {
      _running = false;
      if (ref.mounted) {
        state = state.copyWith(fetching: false);
        _scheduleNext();
      }
    }
  }

  void _scheduleNext() {
    _stopTimer();
    if (!_active) return;
    final wait = newsNextFetchIn(
      feeds: state.feeds,
      records: state.records,
      now: clock.now().toUtc(),
    );
    if (wait == null) return;
    // A feed added while a round ran is due at once; the short floor only
    // guards against a tight loop should a round ever record no attempt.
    final delay = wait < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : wait;
    _timer = Timer(delay, () => unawaited(_fetchDue()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _write(Future<void> Function() write) async {
    try {
      await write();
    } on Object catch (e) {
      _log.debug('News feeds not saved (non-fatal): $e');
    }
  }
}

/// Watched by the block and the sources dialog only: auto-disposed, so
/// leaving the Übersicht drops the timer with the last listener.
final newsFeedProvider =
    NotifierProvider.autoDispose<NewsFeedNotifier, NewsFeedState>(
      NewsFeedNotifier.new,
    );
