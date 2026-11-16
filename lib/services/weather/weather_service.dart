/// The weather card of the Übersicht (#1569): storage, the two network
/// clients and the notifier. The rules are in `core/overview/weather.dart`.
///
/// Nothing here runs at start-up or on the hotkey path. The card calls
/// [WeatherNotifier.refreshIfDue] only while it is on the page, switched on,
/// a place is chosen and the window is active. Without a place no weather
/// service is ever asked. Failures stay quiet: the card keeps the stored
/// forecast or shows a calm line, nothing goes to crash reporting.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/app_info.dart' show appUserAgent;
import '../../core/app_urls.dart' show kContactEmail, kWebsiteUrl;
import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/overview/weather.dart';

final _log = AppLogger('Weather');

/// MET Norway's forecast endpoint (no key, CC BY 4.0).
const kMetForecastUrl =
    'https://api.met.no/weatherapi/locationforecast/2.0/compact';

/// The licence page MET Norway asks to link with the attribution.
const kMetLicenceUrl = 'https://api.met.no/doc/License';

/// OpenStreetMap's place search (no key, usage policy: one request per
/// second, identifying User-Agent, no search while typing).
const kNominatimSearchUrl = 'https://nominatim.openstreetmap.org/search';

/// The OpenStreetMap copyright page linked with the search attribution.
const kOsmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// The identifying User-Agent both services ask for: app, version and the
/// project's public website and contact address. No device or user detail.
String get weatherUserAgent => '$appUserAgent (+$kWebsiteUrl; $kContactEmail)';

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

const _kPlaceKey = 'overview_weather_place';
const _kCacheKey = 'overview_weather_forecast';
const _kNextKey = 'overview_weather_next';

abstract interface class WeatherStore {
  Future<WeatherPlace?> readPlace();
  Future<void> writePlace(WeatherPlace? place);
  Future<WeatherCache?> readCache();
  Future<void> writeCache(WeatherCache? cache);
  Future<DateTime?> readNextAttempt();
  Future<void> writeNextAttempt(DateTime? at);
}

/// Keeps the place, the forecast and the next request time in the local app
/// settings. An empty value means "none".
class DatabaseWeatherStore implements WeatherStore {
  const DatabaseWeatherStore(this._db);

  final HistoryDatabase _db;

  @override
  Future<WeatherPlace?> readPlace() async =>
      decodeWeatherPlace(await _db.readAppSetting(_kPlaceKey));

  @override
  Future<void> writePlace(WeatherPlace? place) => _db.writeAppSetting(
    _kPlaceKey,
    place == null ? '' : encodeWeatherPlace(place),
  );

  @override
  Future<WeatherCache?> readCache() async =>
      decodeWeatherCache(await _db.readAppSetting(_kCacheKey));

  @override
  Future<void> writeCache(WeatherCache? cache) => _db.writeAppSetting(
    _kCacheKey,
    cache == null ? '' : encodeWeatherCache(cache),
  );

  @override
  Future<DateTime?> readNextAttempt() async {
    final raw = await _db.readAppSetting(_kNextKey);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> writeNextAttempt(DateTime? at) => _db.writeAppSetting(
    _kNextKey,
    at == null ? '' : at.toUtc().millisecondsSinceEpoch.toString(),
  );
}

// ---------------------------------------------------------------------------
// Forecast client
// ---------------------------------------------------------------------------

/// The outcome of one forecast request.
sealed class WeatherFetchResult {
  const WeatherFetchResult();
}

/// 200 (or 203, a deprecated but still valid answer) with a usable body.
final class WeatherFetchFresh extends WeatherFetchResult {
  const WeatherFetchFresh(this.hours, {this.lastModified, this.serverTtl});
  final List<WeatherHour> hours;
  final String? lastModified;
  final Duration? serverTtl;
}

/// 304: the stored forecast is still current.
final class WeatherFetchNotModified extends WeatherFetchResult {
  const WeatherFetchNotModified({this.lastModified, this.serverTtl});
  final String? lastModified;
  final Duration? serverTtl;
}

/// 429: asked too often; wait at least [retryAfter].
final class WeatherFetchThrottled extends WeatherFetchResult {
  const WeatherFetchThrottled(this.retryAfter);
  final Duration? retryAfter;
}

/// Offline, timeout, any other status or an unusable body.
final class WeatherFetchFailed extends WeatherFetchResult {
  const WeatherFetchFailed();
}

abstract interface class WeatherForecastFetcher {
  Future<WeatherFetchResult> fetch(
    WeatherPlace place, {
    String? ifModifiedSince,
    required DateTime now,
  });
}

/// GET the `compact` forecast for the rounded coordinates, with the
/// identifying User-Agent and `If-Modified-Since` when a forecast is stored.
class HttpWeatherForecastFetcher implements WeatherForecastFetcher {
  const HttpWeatherForecastFetcher(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration timeout;

  @override
  Future<WeatherFetchResult> fetch(
    WeatherPlace place, {
    String? ifModifiedSince,
    required DateTime now,
  }) async {
    final uri = Uri.parse(kMetForecastUrl).replace(
      queryParameters: {'lat': place.latitudeText, 'lon': place.longitudeText},
    );
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': weatherUserAgent,
              'Accept': 'application/json',
              'If-Modified-Since': ?ifModifiedSince,
            },
          )
          .timeout(timeout);
      final headers = response.headers;
      Duration? ttl() => weatherServerTtl(
        expires: headers['expires'],
        date: headers['date'],
        now: now,
      );
      switch (response.statusCode) {
        case 200:
        case 203:
          if (response.statusCode == 203) {
            _log.info('MET Norway reports this API version as deprecated');
          }
          final hours = parseMetForecast(response.body);
          if (hours == null) return const WeatherFetchFailed();
          return WeatherFetchFresh(
            hours,
            lastModified: headers['last-modified'],
            serverTtl: ttl(),
          );
        case 304:
          return WeatherFetchNotModified(
            lastModified: headers['last-modified'],
            serverTtl: ttl(),
          );
        case 429:
          return WeatherFetchThrottled(
            weatherRetryAfter(headers['retry-after'], now: now),
          );
        default:
          _log.info('Forecast request answered ${response.statusCode}');
          return const WeatherFetchFailed();
      }
    } on Object catch (error) {
      _log.info('Forecast unavailable: ${error.runtimeType}');
      return const WeatherFetchFailed();
    }
  }
}

// ---------------------------------------------------------------------------
// Place search client
// ---------------------------------------------------------------------------

/// Thrown by [PlaceSearch.search] when the search service is unreachable or
/// answers with something unusable. "No hit" is an empty list instead.
class PlaceSearchUnavailable implements Exception {
  const PlaceSearchUnavailable();
}

abstract interface class PlaceSearch {
  /// The hits for [query] in [languageCode], or [PlaceSearchUnavailable].
  Future<List<GeocodeResult>> search(String query, String languageCode);
}

/// Nominatim search, only on an explicit search. Keeps one second between
/// requests (waiting rather than dropping the second one) and answers a
/// repeated query from memory.
class NominatimPlaceSearch implements PlaceSearch {
  NominatimPlaceSearch(
    this._client, {
    this.timeout = const Duration(seconds: 10),
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  final http.Client _client;
  final Duration timeout;
  final Future<void> Function(Duration) _wait;
  DateTime? _lastRequest;
  final Map<String, List<GeocodeResult>> _memo = {};

  /// Requests actually sent (not answered from memory), for tests.
  int sent = 0;

  @override
  Future<List<GeocodeResult>> search(String query, String languageCode) async {
    final q = geocodeQuery(query);
    if (q == null) return const [];
    final memoKey = '$languageCode|${q.toLowerCase()}';
    final memo = _memo[memoKey];
    if (memo != null) return memo;

    final last = _lastRequest;
    if (last != null) {
      final since = clock.now().difference(last);
      if (since < kGeocodeMinGap) await _wait(kGeocodeMinGap - since);
    }
    _lastRequest = clock.now();
    sent++;

    final uri = Uri.parse(kNominatimSearchUrl).replace(
      queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'limit': '5',
        'featureType': 'settlement',
        'accept-language': languageCode,
      },
    );
    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': weatherUserAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
    } on Object catch (error) {
      _log.info('Place search unavailable: ${error.runtimeType}');
      throw const PlaceSearchUnavailable();
    }
    if (response.statusCode != 200) {
      _log.info('Place search answered ${response.statusCode}');
      throw const PlaceSearchUnavailable();
    }
    final results = parseNominatimResults(response.body);
    if (results == null) throw const PlaceSearchUnavailable();
    _memo[memoKey] = results;
    return results;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final weatherStoreProvider = Provider<WeatherStore>(
  (ref) => DatabaseWeatherStore(ref.watch(historyDatabaseProvider)),
);

final _weatherHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final weatherFetcherProvider = Provider<WeatherForecastFetcher>(
  (ref) => HttpWeatherForecastFetcher(ref.watch(_weatherHttpClientProvider)),
);

/// One search client for the whole app, so the one-second gap holds across
/// dialogs.
final placeSearchProvider = Provider<PlaceSearch>(
  (ref) => NominatimPlaceSearch(ref.watch(_weatherHttpClientProvider)),
);

/// What the card shows.
class WeatherView {
  const WeatherView({
    this.loaded = false,
    this.place,
    this.cache,
    this.nextAttempt,
    this.lastFailed = false,
  });

  /// False until the stored values were read.
  final bool loaded;
  final WeatherPlace? place;

  /// The stored forecast, only when it belongs to [place].
  final WeatherCache? cache;

  /// When the card may ask again (UTC); the card sets its timer to it.
  final DateTime? nextAttempt;

  /// The last request failed (the card may still show [cache]).
  final bool lastFailed;
}

/// Reads the stored place and forecast and asks MET Norway only when due.
class WeatherNotifier extends Notifier<WeatherView> {
  bool _running = false;
  bool _again = false;

  @override
  WeatherView build() => const WeatherView();

  WeatherStore get _store => ref.read(weatherStoreProvider);

  /// Shows the stored forecast at once, then asks only when due (see
  /// [weatherFetchDue]). A call while one is running runs once more after
  /// it, so a place chosen meanwhile is not missed.
  Future<void> refreshIfDue() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      await _refresh();
    } finally {
      _running = false;
    }
    if (_again) {
      _again = false;
      await refreshIfDue();
    }
  }

  Future<void> _refresh() async {
    try {
      final now = clock.now().toUtc();
      final place = await _store.readPlace();
      var cache = await _store.readCache();
      final next = await _store.readNextAttempt();
      final own = place != null && cache != null && cache.isFor(place);
      state = WeatherView(
        loaded: true,
        place: place,
        cache: own ? cache : null,
        nextAttempt: next,
        lastFailed: state.lastFailed,
      );
      if (place == null) return;
      if (!weatherFetchDue(
        place: place,
        cache: cache,
        nextAttempt: next,
        now: now,
      )) {
        return;
      }
      if (!own) cache = null;
      final result = await ref
          .read(weatherFetcherProvider)
          .fetch(place, ifModifiedSince: cache?.lastModified, now: now);
      DateTime nextAttempt;
      var failed = false;
      switch (result) {
        case WeatherFetchFresh(
          :final hours,
          :final lastModified,
          :final serverTtl,
        ):
          cache = WeatherCache(
            latitude: place.latitude,
            longitude: place.longitude,
            hours: hours,
            fetchedAt: now,
            lastModified: lastModified,
          );
          await _store.writeCache(cache);
          nextAttempt = weatherNextAfterAnswer(now, serverTtl);
        case WeatherFetchNotModified(:final lastModified, :final serverTtl):
          if (cache != null) {
            cache = cache.confirmedAt(now, lastModified: lastModified);
            await _store.writeCache(cache);
          }
          nextAttempt = weatherNextAfterAnswer(now, serverTtl);
        case WeatherFetchThrottled(:final retryAfter):
          nextAttempt = weatherNextAfterThrottle(now, retryAfter);
          failed = true;
        case WeatherFetchFailed():
          nextAttempt = weatherNextAfterFailure(now);
          failed = true;
      }
      await _store.writeNextAttempt(nextAttempt);
      state = WeatherView(
        loaded: true,
        place: place,
        cache: cache,
        nextAttempt: nextAttempt,
        lastFailed: failed,
      );
    } on Object catch (error) {
      // Storage trouble: the card shows what it has; a debug-level note only.
      _log.info('Weather not refreshed: ${error.runtimeType}');
    }
  }

  /// Stores [place] (rounded) and asks for its forecast right away. The
  /// forecast of the previous place is dropped.
  Future<void> setPlace(WeatherPlace place) async {
    try {
      await _store.writePlace(place);
      await _store.writeCache(null);
      await _store.writeNextAttempt(null);
    } on Object catch (error) {
      _log.info('Weather place not saved: ${error.runtimeType}');
    }
    state = WeatherView(loaded: true, place: place);
    await refreshIfDue();
  }

  /// Forgets the place and its forecast; no weather service is asked again
  /// until a new place is chosen.
  Future<void> clearPlace() async {
    try {
      await _store.writePlace(null);
      await _store.writeCache(null);
      await _store.writeNextAttempt(null);
    } on Object catch (error) {
      _log.info('Weather place not removed: ${error.runtimeType}');
    }
    state = const WeatherView(loaded: true);
  }
}

final weatherProvider = NotifierProvider<WeatherNotifier, WeatherView>(
  WeatherNotifier.new,
);
