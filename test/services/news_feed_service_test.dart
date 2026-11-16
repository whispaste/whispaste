/// The news block's fetching (#1568): the size and status limits of the HTTP
/// fetch, and the loop on simulated time: nothing until the block is active,
/// each feed at most once an hour, nothing after the block went inactive.
library;

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/core/overview/news_feed.dart';
import 'package:whispaste/services/news_feed_service.dart';

const _feedA = 'https://a.example/feed.xml';
const _feedB = 'https://b.example/feed.xml';

const _rss =
    '<rss><channel><title>A</title><item><title>Hello</title>'
    '<link>https://a.example/hello</link></item></channel></rss>';

class _MemoryStore implements NewsFeedStore {
  _MemoryStore({List<String> feeds = const []}) : feeds = [...feeds];

  List<String> feeds;
  Map<String, NewsFeedRecord> records = {};

  @override
  Future<List<String>> readFeeds() async => feeds;

  @override
  Future<void> writeFeeds(List<String> f) async => feeds = [...f];

  @override
  Future<Map<String, NewsFeedRecord>> readRecords() async => records;

  @override
  Future<void> writeRecords(Map<String, NewsFeedRecord> r) async =>
      records = {...r};
}

class _CountingFetcher implements NewsFeedFetcher {
  final calls = <String>[];
  bool offline = false;

  @override
  Future<NewsFeed?> fetch(Uri url) async {
    calls.add(url.toString());
    if (offline) return null;
    return parseNewsFeed(_rss, feedUrl: url);
  }
}

ProviderContainer _container(_MemoryStore store, _CountingFetcher fetcher) =>
    ProviderContainer(
      overrides: [
        newsFeedStoreProvider.overrideWithValue(store),
        newsFeedFetcherProvider.overrideWithValue(fetcher),
      ],
    );

void main() {
  group('HttpNewsFeedFetcher', () {
    final url = Uri.parse(_feedA);

    test('reads a feed with the plain user agent', () async {
      http.BaseRequest? seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(_rss, 200);
      });
      final feed = await HttpNewsFeedFetcher(client).fetch(url);
      expect(feed?.items.single.title, 'Hello');
      expect(seen?.headers['User-Agent'], 'WhisPaste');
    });

    test('an answer above the size limit is not read', () async {
      final big = MockClient.streaming((request, _) async {
        final chunks = Stream<List<int>>.fromIterable([
          for (var i = 0; i < 10; i++) List<int>.filled(1024, 0x20),
        ]);
        return http.StreamedResponse(chunks, 200);
      });
      expect(await HttpNewsFeedFetcher(big, maxBytes: 4096).fetch(url), isNull);
      final declared = MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream.value(utf8.encode(_rss)),
          200,
          contentLength: 10 * 1024 * 1024,
        ),
      );
      expect(await HttpNewsFeedFetcher(declared).fetch(url), isNull);
    });

    test('an error status, broken XML or no connection give null', () async {
      expect(
        await HttpNewsFeedFetcher(
          MockClient((_) async => http.Response(_rss, 404)),
        ).fetch(url),
        isNull,
      );
      expect(
        await HttpNewsFeedFetcher(
          MockClient((_) async => http.Response('<rss><channel>', 200)),
        ).fetch(url),
        isNull,
      );
      expect(
        await HttpNewsFeedFetcher(
          MockClient((_) async => throw http.ClientException('offline')),
        ).fetch(url),
        isNull,
      );
    });

    test('a server that never answers runs into the time limit', () async {
      final hanging = MockClient((_) => Completer<http.Response>().future);
      expect(
        await HttpNewsFeedFetcher(
          hanging,
          timeout: const Duration(milliseconds: 10),
        ).fetch(url),
        isNull,
      );
    });

    test('a Latin-1 feed is decoded as declared', () {
      final bytes = latin1.encode(
        '<?xml version="1.0" encoding="ISO-8859-1"?><rss>Grüße</rss>',
      );
      expect(decodeNewsBody(bytes), contains('Grüße'));
      expect(
        decodeNewsBody(utf8.encode('<rss>Grüße</rss>')),
        contains('Grüße'),
      );
    });
  });

  group('NewsFeedNotifier', () {
    test('nothing is fetched until the block is active', () {
      fakeAsync((async) {
        final store = _MemoryStore(feeds: [_feedA]);
        final fetcher = _CountingFetcher();
        final container = _container(store, fetcher);
        container.listen(newsFeedProvider, (_, _) {});
        async.elapse(const Duration(hours: 3));
        expect(fetcher.calls, isEmpty);
        container.dispose();
      });
    });

    test('each feed at most once an hour while active, none after', () {
      fakeAsync((async) {
        withClock(async.getClock(DateTime.utc(2026, 11, 15, 12)), () {
          final store = _MemoryStore(feeds: [_feedA, _feedB]);
          final fetcher = _CountingFetcher();
          final container = _container(store, fetcher);
          container.listen(newsFeedProvider, (_, _) {});
          final notifier = container.read(newsFeedProvider.notifier);

          notifier.setActive(active: true);
          async.flushMicrotasks();
          expect(fetcher.calls, [_feedA, _feedB]);
          expect(container.read(newsFeedProvider).items, isNotEmpty);

          // Leaving and coming back within the hour asks nothing.
          notifier.setActive(active: false);
          async.elapse(const Duration(minutes: 30));
          notifier.setActive(active: true);
          async.flushMicrotasks();
          expect(fetcher.calls, hasLength(2));

          // Still on screen an hour after the first round: asked again.
          async.elapse(const Duration(minutes: 31));
          expect(fetcher.calls, hasLength(4));

          // Inactive: the timer is gone, nothing more in the background.
          notifier.setActive(active: false);
          async.elapse(const Duration(hours: 5));
          expect(fetcher.calls, hasLength(4));
          container.dispose();
        });
      });
    });

    test('offline: the attempt counts, old entries stay, no retry loop', () {
      fakeAsync((async) {
        withClock(async.getClock(DateTime.utc(2026, 11, 15, 12)), () {
          final store = _MemoryStore(feeds: [_feedA]);
          final fetcher = _CountingFetcher();
          final container = _container(store, fetcher);
          container.listen(newsFeedProvider, (_, _) {});
          final notifier = container.read(newsFeedProvider.notifier);
          notifier.setActive(active: true);
          async.flushMicrotasks();
          expect(container.read(newsFeedProvider).items, hasLength(1));

          fetcher.offline = true;
          async.elapse(const Duration(minutes: 61));
          expect(fetcher.calls, hasLength(2));
          final state = container.read(newsFeedProvider);
          expect(state.items, hasLength(1), reason: 'last entries stay');
          expect(state.records[_feedA]!.failed, isTrue);

          async.elapse(const Duration(minutes: 30));
          expect(fetcher.calls, hasLength(2));
          container.dispose();
        });
      });
    });

    test('an added feed is asked at once, a removed one is forgotten', () {
      fakeAsync((async) {
        withClock(async.getClock(DateTime.utc(2026, 11, 15, 12)), () {
          final store = _MemoryStore();
          final fetcher = _CountingFetcher();
          final container = _container(store, fetcher);
          container.listen(newsFeedProvider, (_, _) {});
          final notifier = container.read(newsFeedProvider.notifier);
          notifier.setActive(active: true);
          async.flushMicrotasks();
          expect(fetcher.calls, isEmpty);

          NewsFeedUrlProblem? problem;
          unawaited(
            notifier.addFeed('a.example/feed.xml').then((p) => problem = p),
          );
          async.flushMicrotasks();
          expect(problem, isNull);
          expect(store.feeds, [_feedA]);
          expect(fetcher.calls, [_feedA]);

          unawaited(
            notifier.addFeed('a.example/feed.xml').then((p) => problem = p),
          );
          async.flushMicrotasks();
          expect(problem, NewsFeedUrlProblem.duplicate);

          unawaited(notifier.removeFeed(_feedA));
          async.flushMicrotasks();
          expect(store.feeds, isEmpty);
          expect(store.records, isEmpty);
          expect(container.read(newsFeedProvider).items, isEmpty);
          async.elapse(const Duration(hours: 2));
          expect(fetcher.calls, hasLength(1));
          container.dispose();
        });
      });
    });
  });
}
