// Hand-over points of the weather card (#1569): what goes over the wire to
// MET Norway and Nominatim (rounded coordinates, identifying User-Agent,
// If-Modified-Since), how each answer is read (200, 304, 429, errors,
// offline), the one-second gap of the place search, and the notifier that
// asks only when due. Time is fixed with `clock`; HTTP is a MockClient.
import 'dart:io' show HttpDate, SocketException;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/core/overview/weather.dart';
import 'package:whispaste/services/weather/weather_service.dart';

final _now = DateTime.utc(2026, 11, 15, 12, 10);
final _place = WeatherPlace(
  name: 'Berlin',
  latitude: 52.5170365,
  longitude: 13.3888599,
);

const _body =
    '{"properties":{"timeseries":[{"time":"2026-11-15T12:00:00Z","data":'
    '{"instant":{"details":{"air_temperature":4.2}},"next_1_hours":'
    '{"summary":{"symbol_code":"cloudy"}}}}]}}';

class _FakeStore implements WeatherStore {
  WeatherPlace? place;
  WeatherCache? cache;
  DateTime? next;

  @override
  Future<WeatherPlace?> readPlace() async => place;
  @override
  Future<void> writePlace(WeatherPlace? p) async => place = p;
  @override
  Future<WeatherCache?> readCache() async => cache;
  @override
  Future<void> writeCache(WeatherCache? c) async => cache = c;
  @override
  Future<DateTime?> readNextAttempt() async => next;
  @override
  Future<void> writeNextAttempt(DateTime? at) async => next = at;
}

class _FakeFetcher implements WeatherForecastFetcher {
  _FakeFetcher(this.result);

  WeatherFetchResult result;
  int calls = 0;
  String? lastIfModifiedSince;

  @override
  Future<WeatherFetchResult> fetch(
    WeatherPlace place, {
    String? ifModifiedSince,
    required DateTime now,
  }) async {
    calls++;
    lastIfModifiedSince = ifModifiedSince;
    return result;
  }
}

ProviderContainer _container(_FakeStore store, _FakeFetcher fetcher) {
  final c = ProviderContainer(
    overrides: [
      weatherStoreProvider.overrideWithValue(store),
      weatherFetcherProvider.overrideWithValue(fetcher),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('forecast request', () {
    test('sends rounded coordinates and the identifying User-Agent', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(_body, 200);
      });
      await HttpWeatherForecastFetcher(client).fetch(_place, now: _now);
      expect(seen.url.host, 'api.met.no');
      expect(seen.url.queryParameters, {'lat': '52.52', 'lon': '13.39'});
      expect(seen.headers['User-Agent'], startsWith('WhisPaste/'));
      expect(seen.headers['User-Agent'], contains('https://whispaste.de'));
      expect(seen.headers.containsKey('If-Modified-Since'), isFalse);
    });

    test('a stored Last-Modified goes back as If-Modified-Since', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response('', 304);
      });
      const lm = 'Sun, 15 Nov 2026 11:00:00 GMT';
      final result = await HttpWeatherForecastFetcher(
        client,
      ).fetch(_place, ifModifiedSince: lm, now: _now);
      expect(seen.headers['If-Modified-Since'], lm);
      expect(result, isA<WeatherFetchNotModified>());
    });

    test('200 yields the forecast, Last-Modified and the server ttl', () async {
      final date = DateTime.utc(2026, 11, 15, 12);
      final client = MockClient(
        (_) async => http.Response(
          _body,
          200,
          headers: {
            'date': HttpDate.format(date),
            'expires': HttpDate.format(date.add(const Duration(minutes: 40))),
            'last-modified': 'Sun, 15 Nov 2026 11:55:00 GMT',
          },
        ),
      );
      final result =
          await HttpWeatherForecastFetcher(client).fetch(_place, now: _now)
              as WeatherFetchFresh;
      expect(result.hours.single.temperatureC, 4.2);
      expect(result.lastModified, 'Sun, 15 Nov 2026 11:55:00 GMT');
      expect(result.serverTtl, const Duration(minutes: 40));
    });

    test('203 (deprecated version) is still a usable answer', () async {
      final client = MockClient((_) async => http.Response(_body, 203));
      expect(
        await HttpWeatherForecastFetcher(client).fetch(_place, now: _now),
        isA<WeatherFetchFresh>(),
      );
    });

    test('429 carries Retry-After', () async {
      final client = MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': '3600'}),
      );
      final result =
          await HttpWeatherForecastFetcher(client).fetch(_place, now: _now)
              as WeatherFetchThrottled;
      expect(result.retryAfter, const Duration(hours: 1));
    });

    test('server errors, bad bodies and offline are quiet failures', () async {
      for (final client in [
        MockClient((_) async => http.Response('oops', 500)),
        MockClient((_) async => http.Response('<html>', 200)),
        MockClient((_) async => throw const SocketException('offline')),
      ]) {
        expect(
          await HttpWeatherForecastFetcher(client).fetch(_place, now: _now),
          isA<WeatherFetchFailed>(),
        );
      }
    });
  });

  group('place search', () {
    const hits =
        '[{"lat":"52.52","lon":"13.40","name":"Berlin",'
        '"display_name":"Berlin, Deutschland"}]';

    test('asks Nominatim with the User-Agent and the UI language', () async {
      late http.Request seen;
      final search = NominatimPlaceSearch(
        MockClient((r) async {
          seen = r;
          return http.Response(hits, 200);
        }),
        wait: (_) async {},
      );
      final results = await search.search('  Berlin ', 'de');
      expect(results.single.name, 'Berlin');
      expect(seen.url.host, 'nominatim.openstreetmap.org');
      expect(seen.url.queryParameters['q'], 'Berlin');
      expect(seen.url.queryParameters['format'], 'jsonv2');
      expect(seen.url.queryParameters['accept-language'], 'de');
      expect(seen.headers['User-Agent'], startsWith('WhisPaste/'));
    });

    test('keeps one second between requests and answers repeats from '
        'memory', () async {
      final waits = <Duration>[];
      final search = NominatimPlaceSearch(
        MockClient((_) async => http.Response(hits, 200)),
        wait: (d) async => waits.add(d),
      );
      await withClock(Clock.fixed(_now), () async {
        await search.search('Berlin', 'de');
        await search.search('Berlin', 'de');
        await search.search('Hamburg', 'de');
      });
      expect(search.sent, 2);
      expect(waits, [kGeocodeMinGap]);
    });

    test('a too short query sends nothing', () async {
      final search = NominatimPlaceSearch(
        MockClient((_) async => fail('must not be sent')),
        wait: (_) async {},
      );
      expect(await search.search(' a ', 'de'), isEmpty);
      expect(search.sent, 0);
    });

    test('errors and offline report an unavailable search', () async {
      for (final client in [
        MockClient((_) async => http.Response('', 503)),
        MockClient((_) async => http.Response('{"x":1}', 200)),
        MockClient((_) async => throw const SocketException('offline')),
      ]) {
        final search = NominatimPlaceSearch(client, wait: (_) async {});
        await expectLater(
          search.search('Berlin', 'de'),
          throwsA(isA<PlaceSearchUnavailable>()),
        );
      }
    });
  });

  group('notifier', () {
    test('without a place nothing is asked', () async {
      final store = _FakeStore();
      final fetcher = _FakeFetcher(const WeatherFetchFailed());
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).refreshIfDue(),
      );
      expect(fetcher.calls, 0);
      expect(c.read(weatherProvider).loaded, isTrue);
    });

    test('a fresh answer is stored and sets the next time', () async {
      final store = _FakeStore()..place = _place;
      final fetcher = _FakeFetcher(
        WeatherFetchFresh(
          [WeatherHour(time: _now, temperatureC: 3)],
          lastModified: 'LM',
          serverTtl: const Duration(minutes: 90),
        ),
      );
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).refreshIfDue(),
      );
      expect(fetcher.calls, 1);
      expect(store.cache?.isFor(_place), isTrue);
      expect(store.cache?.lastModified, 'LM');
      expect(store.next, _now.add(const Duration(minutes: 90)));
      expect(c.read(weatherProvider).cache?.hours.single.temperatureC, 3);
    });

    test('before the next time the stored forecast is shown without a '
        'request', () async {
      final store = _FakeStore()
        ..place = _place
        ..cache = WeatherCache(
          latitude: _place.latitude,
          longitude: _place.longitude,
          hours: [WeatherHour(time: _now, temperatureC: 1)],
          fetchedAt: _now,
          lastModified: 'LM',
        )
        ..next = _now.add(const Duration(minutes: 30));
      final fetcher = _FakeFetcher(const WeatherFetchFailed());
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).refreshIfDue(),
      );
      expect(fetcher.calls, 0);
      expect(c.read(weatherProvider).cache, isNotNull);
    });

    test('304 keeps the forecast and sent If-Modified-Since', () async {
      final store = _FakeStore()
        ..place = _place
        ..cache = WeatherCache(
          latitude: _place.latitude,
          longitude: _place.longitude,
          hours: [WeatherHour(time: _now, temperatureC: 1)],
          fetchedAt: _now.subtract(const Duration(hours: 2)),
          lastModified: 'LM',
        );
      final fetcher = _FakeFetcher(const WeatherFetchNotModified());
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).refreshIfDue(),
      );
      expect(fetcher.lastIfModifiedSince, 'LM');
      expect(store.cache?.fetchedAt, _now);
      expect(store.cache?.hours.single.temperatureC, 1);
      expect(store.next, _now.add(kWeatherMinInterval));
    });

    test('offline keeps the old forecast and retries in 30 minutes', () async {
      final store = _FakeStore()
        ..place = _place
        ..cache = WeatherCache(
          latitude: _place.latitude,
          longitude: _place.longitude,
          hours: [WeatherHour(time: _now, temperatureC: 1)],
          fetchedAt: _now.subtract(const Duration(hours: 2)),
        );
      final fetcher = _FakeFetcher(const WeatherFetchFailed());
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).refreshIfDue(),
      );
      final view = c.read(weatherProvider);
      expect(view.lastFailed, isTrue);
      expect(view.cache?.hours.single.temperatureC, 1);
      expect(store.next, _now.add(kWeatherRetryGap));
    });

    test('429 waits at least an hour', () async {
      final store = _FakeStore()..place = _place;
      final fetcher = _FakeFetcher(
        const WeatherFetchThrottled(Duration(minutes: 5)),
      );
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).refreshIfDue(),
      );
      expect(store.next, _now.add(kWeatherMinInterval));
    });

    test('a new place drops the old forecast and asks at once', () async {
      final old = WeatherPlace(name: 'Oslo', latitude: 59.91, longitude: 10.75);
      final store = _FakeStore()
        ..place = old
        ..cache = WeatherCache(
          latitude: old.latitude,
          longitude: old.longitude,
          hours: [WeatherHour(time: _now, temperatureC: 1)],
          fetchedAt: _now,
          lastModified: 'OSLO',
        )
        ..next = _now.add(const Duration(minutes: 50));
      final fetcher = _FakeFetcher(
        WeatherFetchFresh([WeatherHour(time: _now, temperatureC: 9)]),
      );
      final c = _container(store, fetcher);
      await withClock(
        Clock.fixed(_now),
        () => c.read(weatherProvider.notifier).setPlace(_place),
      );
      expect(fetcher.calls, 1);
      expect(fetcher.lastIfModifiedSince, isNull);
      expect(store.place, _place);
      expect(store.cache?.isFor(_place), isTrue);
    });

    test('removing the place forgets place and forecast', () async {
      final store = _FakeStore()
        ..place = _place
        ..cache = WeatherCache(
          latitude: _place.latitude,
          longitude: _place.longitude,
          hours: [WeatherHour(time: _now, temperatureC: 1)],
          fetchedAt: _now,
        )
        ..next = _now;
      final c = _container(store, _FakeFetcher(const WeatherFetchFailed()));
      await c.read(weatherProvider.notifier).clearPlace();
      expect(store.place, isNull);
      expect(store.cache, isNull);
      expect(store.next, isNull);
      expect(c.read(weatherProvider).place, isNull);
    });
  });
}
