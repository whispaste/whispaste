// Logic of the "Mitmachen" numbers: the answer contract, the seven-day rule,
// the once-a-day attempt, and the notifier that ties them together. Time is
// fixed with `clock`; the network and the database are replaced by fakes.
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/social_stats/social_stats_logic.dart';
import 'package:whispaste/services/social_stats/social_stats_service.dart';

final _now = DateTime.utc(2026, 10, 31, 12);

String _answer({
  Object? stars = 66,
  Object? subscribers = 1234,
  Object? schema = 1,
}) =>
    '{"schema":$schema,"updatedAt":"2026-10-31T09:00:00Z","stale":false,'
    '"github":{"stars":$stars},"youtube":{"subscribers":$subscribers}}';

class _FakeStore implements SocialStatsStore {
  SocialStatsSnapshot? snapshot;
  DateTime? lastAttempt;

  @override
  Future<SocialStatsSnapshot?> readSnapshot() async => snapshot;

  @override
  Future<DateTime?> readLastAttempt() async => lastAttempt;

  @override
  Future<void> writeSnapshot(SocialStatsSnapshot s) async => snapshot = s;

  @override
  Future<void> writeLastAttempt(DateTime at) async => lastAttempt = at;
}

class _FakeFetcher implements SocialStatsFetcher {
  _FakeFetcher(this.result);

  final SocialStatsSnapshot? result;
  int calls = 0;

  @override
  Future<SocialStatsSnapshot?> fetch(DateTime now) async {
    calls++;
    return result;
  }
}

ProviderContainer _container(_FakeStore store, _FakeFetcher fetcher) =>
    ProviderContainer(
      overrides: [
        socialStatsStoreProvider.overrideWithValue(store),
        socialStatsFetcherProvider.overrideWithValue(fetcher),
      ],
    );

void main() {
  group('answer contract', () {
    test('a valid answer yields both counts', () {
      final s = parseSocialStats(_answer(), fetchedAt: _now);
      expect(s?.stars, 66);
      expect(s?.subscribers, 1234);
    });

    test('a null count is a valid "no number", not a failure', () {
      final s = parseSocialStats(_answer(subscribers: 'null'), fetchedAt: _now);
      expect(s, isNotNull);
      expect(s?.subscribers, isNull);
    });

    test('another schema is not usable', () {
      expect(parseSocialStats(_answer(schema: 2), fetchedAt: _now), isNull);
    });

    test('negative, fractional and text counts are not usable', () {
      expect(parseSocialStats(_answer(stars: -1), fetchedAt: _now), isNull);
      expect(parseSocialStats(_answer(stars: 66.5), fetchedAt: _now), isNull);
      expect(parseSocialStats(_answer(stars: '"66"'), fetchedAt: _now), isNull);
    });

    test('a missing field is not usable', () {
      const body =
          '{"schema":1,"updatedAt":"2026-10-31T09:00:00Z","stale":false,"github":{"stars":66}}';
      expect(parseSocialStats(body, fetchedAt: _now), isNull);
    });

    test('broken JSON and foreign shapes are not usable', () {
      expect(parseSocialStats('<html>', fetchedAt: _now), isNull);
      expect(parseSocialStats('[]', fetchedAt: _now), isNull);
    });

    test('the stored form round-trips', () {
      final original = SocialStatsSnapshot(
        stars: 66,
        subscribers: null,
        fetchedAt: _now,
      );
      final back = decodeSocialStatsSnapshot(
        encodeSocialStatsSnapshot(original),
      );
      expect(back?.stars, 66);
      expect(back?.subscribers, isNull);
      expect(back?.fetchedAt, _now);
      expect(decodeSocialStatsSnapshot('{"stars":"x"}'), isNull);
      expect(decodeSocialStatsSnapshot(null), isNull);
    });
  });

  group('what is shown', () {
    test('numbers are shown exactly, without rounding or a minimum', () {
      final snap = SocialStatsSnapshot(
        stars: 7,
        subscribers: 1234,
        fetchedAt: _now,
      );
      final view = socialStatsView(snap, _now);
      expect(view.stars, 7);
      expect(view.subscribers, 1234);
    });

    test('a number older than seven days is dropped', () {
      final snap = SocialStatsSnapshot(
        stars: 66,
        subscribers: 1234,
        fetchedAt: _now,
      );
      final view = socialStatsView(
        snap,
        _now.add(kSocialStatsMaxAge + const Duration(seconds: 1)),
      );
      expect(view.stars, isNull);
      expect(view.subscribers, isNull);
    });

    test('a number exactly seven days old is still shown', () {
      final snap = SocialStatsSnapshot(
        stars: 66,
        subscribers: null,
        fetchedAt: _now,
      );
      expect(socialStatsView(snap, _now.add(kSocialStatsMaxAge)).stars, 66);
    });

    test('without a stored answer there is nothing to show', () {
      final view = socialStatsView(null, _now);
      expect(view.stars, isNull);
      expect(view.subscribers, isNull);
    });
  });

  group('attempt rule', () {
    test('the first visit is due, a visit within 24 h is not', () {
      expect(socialStatsFetchDue(lastAttempt: null, now: _now), isTrue);
      expect(
        socialStatsFetchDue(
          lastAttempt: _now.subtract(const Duration(hours: 23, minutes: 59)),
          now: _now,
        ),
        isFalse,
      );
    });

    test('after 24 h it is due again', () {
      expect(
        socialStatsFetchDue(
          lastAttempt: _now.subtract(const Duration(hours: 24)),
          now: _now,
        ),
        isTrue,
      );
    });

    test('an attempt time in the future (clock set back) is due once', () {
      expect(
        socialStatsFetchDue(
          lastAttempt: _now.add(const Duration(days: 3)),
          now: _now,
        ),
        isTrue,
      );
    });
  });

  group('notifier', () {
    test(
      'a stored answer shows at once and a fresh one is fetched when due',
      () async {
        final store = _FakeStore()
          ..snapshot = SocialStatsSnapshot(
            stars: 60,
            subscribers: null,
            fetchedAt: _now.subtract(const Duration(days: 1)),
          );
        final fetcher = _FakeFetcher(
          SocialStatsSnapshot(stars: 66, subscribers: 1234, fetchedAt: _now),
        );
        final container = _container(store, fetcher);
        addTearDown(container.dispose);

        await withClock(
          Clock.fixed(_now),
          () => container.read(socialStatsProvider.notifier).refreshIfDue(),
        );

        expect(fetcher.calls, 1);
        expect(container.read(socialStatsProvider).stars, 66);
        expect(store.snapshot?.stars, 66);
        expect(store.lastAttempt, _now);
      },
    );

    test('no second request within 24 h, even after a failed one', () async {
      final store = _FakeStore();
      final fetcher = _FakeFetcher(null);
      final first = _container(store, fetcher);
      addTearDown(first.dispose);
      await withClock(
        Clock.fixed(_now),
        () => first.read(socialStatsProvider.notifier).refreshIfDue(),
      );

      final later = _container(store, fetcher);
      addTearDown(later.dispose);
      await withClock(
        Clock.fixed(_now.add(const Duration(hours: 5))),
        () => later.read(socialStatsProvider.notifier).refreshIfDue(),
      );

      expect(fetcher.calls, 1);
      expect(
        later.read(socialStatsProvider).stars,
        isNull,
      ); // failure shows no number, no error
    });

    test('a second call in the same session asks nothing', () async {
      final store = _FakeStore();
      final fetcher = _FakeFetcher(
        SocialStatsSnapshot(stars: 66, subscribers: 1, fetchedAt: _now),
      );
      final container = _container(store, fetcher);
      addTearDown(container.dispose);
      final notifier = container.read(socialStatsProvider.notifier);

      await withClock(Clock.fixed(_now), notifier.refreshIfDue);
      await withClock(
        Clock.fixed(_now.add(const Duration(days: 2))),
        notifier.refreshIfDue,
      );

      expect(fetcher.calls, 1);
    });
  });
}
