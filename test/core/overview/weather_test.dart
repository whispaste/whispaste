// Rules of the weather card (#1569): rounding of the stored place, the
// MET Norway and Nominatim parsers, and when the card may ask again
// (Expires, minimum interval, failures, 429).
import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/weather.dart';

final _now = DateTime.utc(2026, 11, 15, 12, 10);

String _met(List<String> steps) =>
    '{"type":"Feature","properties":{"meta":{"updated_at":"2026-11-15T11:00:00Z"},'
    '"timeseries":[${steps.join(',')}]}}';

String _step(
  String time, {
  double temp = 5,
  String? symbol1 = 'cloudy',
  String? symbol6,
  double? rain,
}) =>
    '{"time":"$time","data":{"instant":{"details":{"air_temperature":$temp}}'
    '${symbol1 == null ? '' : ',"next_1_hours":{"summary":{"symbol_code":"$symbol1"}'
              '${rain == null ? '' : ',"details":{"precipitation_amount":$rain}'}}'}'
    '${symbol6 == null ? '' : ',"next_6_hours":{"summary":{"symbol_code":"$symbol6"}}'}'
    '}}';

WeatherCache _cache(WeatherPlace p, {DateTime? at}) => WeatherCache(
  latitude: p.latitude,
  longitude: p.longitude,
  hours: [WeatherHour(time: _now, temperatureC: 4)],
  fetchedAt: at ?? _now,
);

void main() {
  group('rounding', () {
    test('a place keeps two decimals, about one kilometre', () {
      final p = WeatherPlace(
        name: 'Berlin',
        latitude: 52.5170365,
        longitude: 13.3888599,
      );
      expect(p.latitude, 52.52);
      expect(p.longitude, 13.39);
      expect(p.latitudeText, '52.52');
      expect(p.longitudeText, '13.39');
    });

    test('negative coordinates round the same way', () {
      final p = WeatherPlace(
        name: 'Rio',
        latitude: -22.906847,
        longitude: -43.172897,
      );
      expect(p.latitudeText, '-22.91');
      expect(p.longitudeText, '-43.17');
    });

    test('the stored form holds only rounded values', () {
      final p = WeatherPlace(
        name: 'Berlin',
        latitude: 52.5170365,
        longitude: 13.3888599,
      );
      final stored = encodeWeatherPlace(p);
      expect(stored, isNot(contains('5170365')));
      expect(decodeWeatherPlace(stored), p);
    });

    test('a hand-written precise value is rounded when read', () {
      final p = decodeWeatherPlace(
        '{"name":"X","lat":48.137154,"lon":11.576124}',
      );
      expect(p?.latitude, 48.14);
      expect(p?.longitude, 11.58);
    });

    test('unusable stored places are none', () {
      expect(decodeWeatherPlace(null), isNull);
      expect(decodeWeatherPlace(''), isNull);
      expect(decodeWeatherPlace('nope'), isNull);
      expect(decodeWeatherPlace('{"name":"","lat":1,"lon":1}'), isNull);
      expect(decodeWeatherPlace('{"name":"X","lat":91,"lon":1}'), isNull);
      expect(decodeWeatherPlace('{"name":"X","lat":"1","lon":1}'), isNull);
    });

    test('a long name is cut', () {
      final p = WeatherPlace(name: 'a' * 200, latitude: 0, longitude: 0);
      expect(p.name.length, kWeatherPlaceNameMax);
    });
  });

  group('MET Norway answer', () {
    test('reads temperature, symbol and rain of each step', () {
      final hours = parseMetForecast(
        _met([
          _step('2026-11-15T12:00:00Z', temp: 3.4, symbol1: 'rain', rain: 0.6),
          _step('2026-11-15T13:00:00Z', temp: 4.1, symbol1: 'cloudy'),
        ]),
      )!;
      expect(hours, hasLength(2));
      expect(hours.first.time, DateTime.utc(2026, 11, 15, 12));
      expect(hours.first.temperatureC, 3.4);
      expect(hours.first.symbol, 'rain');
      expect(hours.first.precipitationMm, 0.6);
    });

    test('far steps without a one-hour summary use the six-hour one', () {
      final hours = parseMetForecast(
        _met([
          _step(
            '2026-11-15T12:00:00Z',
            symbol1: null,
            symbol6: 'partlycloudy_day',
          ),
        ]),
      )!;
      expect(hours.single.symbol, 'partlycloudy_day');
    });

    test('keeps at most 48 hours past the first step', () {
      final start = DateTime.utc(2026, 11, 15);
      final hours = parseMetForecast(
        _met([
          for (var i = 0; i < 80; i++)
            _step(start.add(Duration(hours: i)).toIso8601String()),
        ]),
      )!;
      expect(hours.last.time, start.add(kWeatherKeepAhead));
    });

    test('a body that is not a forecast is no forecast', () {
      expect(parseMetForecast('not json'), isNull);
      expect(parseMetForecast('[]'), isNull);
      expect(parseMetForecast('{"properties":{}}'), isNull);
      expect(parseMetForecast(_met([])), isNull);
      expect(parseMetForecast(_met(['{"time":"x"}'])), isNull);
    });

    test('the cache survives a round trip', () {
      final cache = WeatherCache(
        latitude: 52.52,
        longitude: 13.39,
        hours: [
          WeatherHour(
            time: _now,
            temperatureC: -1.5,
            symbol: 'snow',
            precipitationMm: 0.2,
          ),
        ],
        fetchedAt: _now,
        lastModified: 'Sun, 15 Nov 2026 11:00:00 GMT',
      );
      final back = decodeWeatherCache(encodeWeatherCache(cache))!;
      expect(back.latitude, 52.52);
      expect(back.hours.single.temperatureC, -1.5);
      expect(back.hours.single.symbol, 'snow');
      expect(back.fetchedAt, _now);
      expect(back.lastModified, cache.lastModified);
      expect(decodeWeatherCache('{"lat":1}'), isNull);
      expect(decodeWeatherCache('garbage'), isNull);
    });
  });

  group('conditions and the current step', () {
    test('symbol codes map to conditions without the time of day', () {
      expect(weatherConditionOf('clearsky_night'), WeatherCondition.clear);
      expect(weatherConditionOf('fair_day'), WeatherCondition.fair);
      expect(weatherConditionOf('cloudy'), WeatherCondition.cloudy);
      expect(weatherConditionOf('lightrainshowers_day'), WeatherCondition.rain);
      expect(weatherConditionOf('heavysleet'), WeatherCondition.sleet);
      expect(
        weatherConditionOf('snowshowers_polartwilight'),
        WeatherCondition.snow,
      );
      expect(weatherConditionOf('rainandthunder'), WeatherCondition.thunder);
      expect(weatherConditionOf('fog'), WeatherCondition.fog);
      expect(weatherConditionOf('mystery'), isNull);
      expect(weatherSymbolIsNight('clearsky_night'), isTrue);
      expect(weatherSymbolIsNight('clearsky_day'), isFalse);
    });

    test('the step that started last describes now', () {
      final hours = [
        WeatherHour(time: DateTime.utc(2026, 11, 15, 11), temperatureC: 1),
        WeatherHour(time: DateTime.utc(2026, 11, 15, 12), temperatureC: 2),
        WeatherHour(time: DateTime.utc(2026, 11, 15, 13), temperatureC: 3),
      ];
      expect(weatherHourAt(hours, _now)?.temperatureC, 2);
    });

    test('a forecast that no longer reaches now shows nothing', () {
      final hours = [
        WeatherHour(time: DateTime.utc(2026, 11, 14), temperatureC: 1),
      ];
      expect(weatherHourAt(hours, _now), isNull);
    });

    test('the range needs two readings in the next day', () {
      final hours = [
        WeatherHour(time: DateTime.utc(2026, 11, 15, 12), temperatureC: 2),
        WeatherHour(time: DateTime.utc(2026, 11, 15, 18), temperatureC: -3),
        WeatherHour(time: DateTime.utc(2026, 11, 16, 6), temperatureC: 7),
        WeatherHour(time: DateTime.utc(2026, 11, 17, 6), temperatureC: 30),
      ];
      final range = weatherRange(hours, _now)!;
      expect(range.low, -3);
      expect(range.high, 7);
      expect(weatherRange(hours.sublist(3), _now), isNull);
    });
  });

  group('Expires and when to ask again', () {
    final place = WeatherPlace(name: 'Oslo', latitude: 59.91, longitude: 10.75);

    test('the server ttl is measured against its own Date header', () {
      // This computer's clock is two hours ahead; the ttl stays 45 min.
      final serverNow = DateTime.utc(2026, 11, 15, 10);
      final ttl = weatherServerTtl(
        expires: HttpDate.format(serverNow.add(const Duration(minutes: 45))),
        date: HttpDate.format(serverNow),
        now: _now,
      );
      expect(ttl, const Duration(minutes: 45));
    });

    test('without Date the ttl counts from now; bad headers give none', () {
      expect(
        weatherServerTtl(
          expires: HttpDate.format(_now.add(const Duration(minutes: 90))),
          date: null,
          now: _now,
        ),
        const Duration(minutes: 90),
      );
      expect(weatherServerTtl(expires: 'soon', date: null, now: _now), isNull);
      expect(weatherServerTtl(expires: null, date: null, now: _now), isNull);
    });

    test('after an answer: not before Expires, at least an hour, '
        'at most six', () {
      expect(
        weatherNextAfterAnswer(_now, const Duration(minutes: 10)),
        _now.add(kWeatherMinInterval),
      );
      expect(
        weatherNextAfterAnswer(_now, const Duration(minutes: 95)),
        _now.add(const Duration(minutes: 95)),
      );
      expect(
        weatherNextAfterAnswer(_now, const Duration(days: 3)),
        _now.add(kWeatherMaxWait),
      );
      expect(weatherNextAfterAnswer(_now, null), _now.add(kWeatherMinInterval));
    });

    test('after a failure the card waits half an hour', () {
      expect(weatherNextAfterFailure(_now), _now.add(kWeatherRetryGap));
    });

    test('429 waits for Retry-After, at least an hour', () {
      expect(
        weatherNextAfterThrottle(_now, weatherRetryAfter('120', now: _now)),
        _now.add(kWeatherMinInterval),
      );
      expect(
        weatherNextAfterThrottle(_now, weatherRetryAfter('7200', now: _now)),
        _now.add(const Duration(hours: 2)),
      );
      expect(
        weatherRetryAfter(
          HttpDate.format(_now.add(const Duration(hours: 3))),
          now: _now,
        ),
        const Duration(hours: 3),
      );
      expect(weatherRetryAfter('later', now: _now), isNull);
    });

    test('no place, no request', () {
      expect(
        weatherFetchDue(place: null, cache: null, nextAttempt: null, now: _now),
        isFalse,
      );
    });

    test('a first request is due at once', () {
      expect(
        weatherFetchDue(
          place: place,
          cache: null,
          nextAttempt: null,
          now: _now,
        ),
        isTrue,
      );
    });

    test('a stored forecast waits for the next attempt time', () {
      final cache = _cache(place);
      final next = _now.add(const Duration(minutes: 20));
      expect(
        weatherFetchDue(
          place: place,
          cache: cache,
          nextAttempt: next,
          now: _now,
        ),
        isFalse,
      );
      expect(
        weatherFetchDue(
          place: place,
          cache: cache,
          nextAttempt: next,
          now: next,
        ),
        isTrue,
      );
    });

    test('a failure blocks retries until the gap is over, '
        'even without a forecast', () {
      expect(
        weatherFetchDue(
          place: place,
          cache: null,
          nextAttempt: weatherNextAfterFailure(_now),
          now: _now.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('a next time far ahead (clock set back) does not block forever', () {
      expect(
        weatherFetchDue(
          place: place,
          cache: _cache(place),
          nextAttempt: _now.add(const Duration(days: 2)),
          now: _now,
        ),
        isTrue,
      );
    });

    test('a forecast of another place is not this place', () {
      final other = WeatherPlace(
        name: 'Bergen',
        latitude: 60.39,
        longitude: 5.32,
      );
      expect(_cache(other).isFor(place), isFalse);
      expect(_cache(place).isFor(place), isTrue);
    });
  });

  group('place search', () {
    test('queries are trimmed, collapsed and bounded', () {
      expect(geocodeQuery('  Bad   Homburg '), 'Bad Homburg');
      expect(geocodeQuery('a'), isNull);
      expect(geocodeQuery('x' * 500)!.length, kGeocodeQueryMax);
    });

    test('Nominatim hits keep name, label and coordinates', () {
      final hits = parseNominatimResults(
        '[{"lat":"52.5170365","lon":"13.3888599","name":"Berlin",'
        '"display_name":"Berlin, Deutschland"},'
        '{"lat":"52.5170365","lon":"13.3888599","name":"Berlin",'
        '"display_name":"Berlin, Deutschland"},'
        '{"lat":"x","lon":"1","name":"Broken"},'
        '{"lat":"47.37","lon":"8.54","display_name":"Zürich, Schweiz"}]',
      )!;
      expect(hits, hasLength(2));
      expect(hits.first.name, 'Berlin');
      expect(hits.first.label, 'Berlin, Deutschland');
      expect(hits.first.toPlace().latitude, 52.52);
      expect(hits.last.name, 'Zürich');
    });

    test('a body that is not a hit list is none', () {
      expect(parseNominatimResults('{"error":"x"}'), isNull);
      expect(parseNominatimResults('<html>'), isNull);
      expect(parseNominatimResults('[]'), isEmpty);
    });
  });
}
