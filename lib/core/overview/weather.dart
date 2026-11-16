/// The weather card of the Übersicht (#1569, part of #196): the pure rules.
///
/// Everything here works on plain values (a stored place, the parsed
/// forecast, response headers and an injected time), so rounding, the cache
/// and Expires rules and the parsers are tested without network or storage.
/// The service in `services/weather/weather_service.dart` feeds them.
///
/// Data sources, both without a key:
/// * Forecast: MET Norway `locationforecast/2.0/compact`, CC BY 4.0. Their
///   terms ask for an identifying User-Agent, caching until `Expires` and
///   `If-Modified-Since` on the next request.
/// * Place search: OpenStreetMap Nominatim, at most one request per second,
///   only on an explicit search (no search while typing), results cached.
library;

import 'dart:convert';
import 'dart:io' show HttpDate;

// ---------------------------------------------------------------------------
// Place and rounding
// ---------------------------------------------------------------------------

/// Decimal places kept of a coordinate: two, about one kilometre. MET Norway
/// accepts up to four; fewer keep the stored place and every request coarse.
const kWeatherCoordinateDecimals = 2;

/// [value] rounded to [kWeatherCoordinateDecimals] places.
double weatherRoundCoordinate(double value) =>
    double.parse(value.toStringAsFixed(kWeatherCoordinateDecimals));

/// The longest place name kept; a longer search result is cut.
const kWeatherPlaceNameMax = 80;

/// The place the card shows the weather for. The coordinates are always
/// rounded ([WeatherPlace.new] rounds), so an exact position never reaches
/// storage or a request.
class WeatherPlace {
  WeatherPlace({
    required String name,
    required double latitude,
    required double longitude,
  }) : name = _clipName(name),
       latitude = weatherRoundCoordinate(latitude),
       longitude = weatherRoundCoordinate(longitude);

  final String name;
  final double latitude;
  final double longitude;

  /// The coordinates as they appear in a request and in storage.
  String get latitudeText =>
      latitude.toStringAsFixed(kWeatherCoordinateDecimals);
  String get longitudeText =>
      longitude.toStringAsFixed(kWeatherCoordinateDecimals);

  /// Whether [other] is the same spot (after rounding).
  bool samePosition(double lat, double lon) =>
      weatherRoundCoordinate(lat) == latitude &&
      weatherRoundCoordinate(lon) == longitude;

  static String _clipName(String raw) {
    final name = raw.trim();
    return name.length <= kWeatherPlaceNameMax
        ? name
        : name.substring(0, kWeatherPlaceNameMax).trimRight();
  }

  @override
  bool operator ==(Object other) =>
      other is WeatherPlace &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(name, latitude, longitude);
}

bool _validLatitude(double v) => v.isFinite && v >= -90 && v <= 90;
bool _validLongitude(double v) => v.isFinite && v >= -180 && v <= 180;

/// The stored form of [place]: JSON with the rounded coordinates.
String encodeWeatherPlace(WeatherPlace place) => jsonEncode({
  'name': place.name,
  'lat': place.latitude,
  'lon': place.longitude,
});

/// The place from its stored form, or null when there is none or it is not
/// usable. Rounds again, so a value written by hand stays coarse.
WeatherPlace? decodeWeatherPlace(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final name = map['name'];
    final lat = map['lat'];
    final lon = map['lon'];
    if (name is! String || name.trim().isEmpty) return null;
    if (lat is! num || lon is! num) return null;
    if (!_validLatitude(lat.toDouble()) || !_validLongitude(lon.toDouble())) {
      return null;
    }
    return WeatherPlace(
      name: name,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
    );
  } on FormatException {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Forecast
// ---------------------------------------------------------------------------

/// What the sky does, from MET Norway's `symbol_code` without its time of day.
enum WeatherCondition {
  clear,
  fair,
  partlyCloudy,
  cloudy,
  fog,
  rain,
  sleet,
  snow,
  thunder,
}

/// The condition of a MET Norway symbol code (`partlycloudy_day`,
/// `lightrainshowersandthunder_night`, …), or null for an unknown one.
WeatherCondition? weatherConditionOf(String? symbol) {
  if (symbol == null) return null;
  final code = symbol.split('_').first;
  if (code.contains('thunder')) return WeatherCondition.thunder;
  if (code.contains('sleet')) return WeatherCondition.sleet;
  if (code.contains('snow')) return WeatherCondition.snow;
  if (code.contains('rain')) return WeatherCondition.rain;
  return switch (code) {
    'clearsky' => WeatherCondition.clear,
    'fair' => WeatherCondition.fair,
    'partlycloudy' => WeatherCondition.partlyCloudy,
    'cloudy' => WeatherCondition.cloudy,
    'fog' => WeatherCondition.fog,
    _ => null,
  };
}

/// Whether the symbol is the night variant (moon instead of sun).
bool weatherSymbolIsNight(String? symbol) =>
    symbol != null && symbol.endsWith('_night');

/// One step of the forecast.
class WeatherHour {
  const WeatherHour({
    required this.time,
    this.temperatureC,
    this.symbol,
    this.precipitationMm,
  });

  /// Start of the step, UTC.
  final DateTime time;
  final double? temperatureC;

  /// MET Norway symbol code of the next hour (or the next six, further out).
  final String? symbol;

  /// Precipitation expected in the next hour, in millimetres.
  final double? precipitationMm;

  Map<String, Object?> toJson() => {
    't': time.toUtc().millisecondsSinceEpoch,
    if (temperatureC != null) 'c': temperatureC,
    if (symbol != null) 's': symbol,
    if (precipitationMm != null) 'p': precipitationMm,
  };

  static WeatherHour? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['t'];
    if (t is! int) return null;
    final c = raw['c'];
    final s = raw['s'];
    final p = raw['p'];
    return WeatherHour(
      time: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
      temperatureC: c is num ? c.toDouble() : null,
      symbol: s is String ? s : null,
      precipitationMm: p is num ? p.toDouble() : null,
    );
  }
}

/// How far ahead the stored forecast reaches. The card uses the next 24
/// hours; the rest covers a day offline.
const kWeatherKeepAhead = Duration(hours: 48);

/// The steps of a MET Norway `compact` answer, at most [kWeatherKeepAhead]
/// past the first, or null when the body is not such an answer.
List<WeatherHour>? parseMetForecast(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final properties = decoded['properties'];
  if (properties is! Map) return null;
  final series = properties['timeseries'];
  if (series is! List) return null;
  final hours = <WeatherHour>[];
  DateTime? first;
  for (final step in series) {
    if (step is! Map) continue;
    final rawTime = step['time'];
    final time = rawTime is String ? DateTime.tryParse(rawTime) : null;
    if (time == null) continue;
    first ??= time;
    if (time.difference(first) > kWeatherKeepAhead) break;
    final data = step['data'];
    if (data is! Map) continue;
    final temp = _path(data, const ['instant', 'details', 'air_temperature']);
    final next1 = data['next_1_hours'];
    final next6 = data['next_6_hours'];
    final symbol =
        _path(next1, const ['summary', 'symbol_code']) ??
        _path(next6, const ['summary', 'symbol_code']);
    final rain = _path(next1, const ['details', 'precipitation_amount']);
    hours.add(
      WeatherHour(
        time: time.toUtc(),
        temperatureC: temp is num ? temp.toDouble() : null,
        symbol: symbol is String ? symbol : null,
        precipitationMm: rain is num ? rain.toDouble() : null,
      ),
    );
  }
  return hours.isEmpty ? null : hours;
}

Object? _path(Object? node, List<String> keys) {
  var current = node;
  for (final key in keys) {
    if (current is! Map) return null;
    current = current[key];
  }
  return current;
}

/// The step that describes [now]: the last one that started before it (at
/// most six hours before, the longest step), or the first one if it starts
/// within the hour. Null when the stored forecast no longer reaches [now].
WeatherHour? weatherHourAt(List<WeatherHour> hours, DateTime now) {
  final t = now.toUtc();
  WeatherHour? best;
  for (final h in hours) {
    if (!h.time.isAfter(t)) best = h;
  }
  if (best != null) {
    final age = t.difference(best.time);
    // A six-hour step further out still describes its whole span.
    return age <= const Duration(hours: 6) ? best : null;
  }
  if (hours.isNotEmpty &&
      hours.first.time.difference(t) <= const Duration(hours: 1)) {
    return hours.first;
  }
  return null;
}

/// Lowest and highest temperature of the steps from [now] on within [span],
/// or null with fewer than two readings.
({double low, double high})? weatherRange(
  List<WeatherHour> hours,
  DateTime now, {
  Duration span = const Duration(hours: 24),
}) {
  final from = now.toUtc().subtract(const Duration(hours: 1));
  final to = now.toUtc().add(span);
  final temps = [
    for (final h in hours)
      if (h.temperatureC != null && h.time.isAfter(from) && h.time.isBefore(to))
        h.temperatureC!,
  ];
  if (temps.length < 2) return null;
  var low = temps.first;
  var high = temps.first;
  for (final v in temps) {
    if (v < low) low = v;
    if (v > high) high = v;
  }
  return (low: low, high: high);
}

/// The stored forecast for one position.
class WeatherCache {
  const WeatherCache({
    required this.latitude,
    required this.longitude,
    required this.hours,
    required this.fetchedAt,
    this.lastModified,
  });

  final double latitude;
  final double longitude;
  final List<WeatherHour> hours;

  /// When the forecast was last confirmed (fresh answer or 304), UTC.
  final DateTime fetchedAt;

  /// The `Last-Modified` header as received, sent back as
  /// `If-Modified-Since`.
  final String? lastModified;

  /// Whether this forecast belongs to [place].
  bool isFor(WeatherPlace place) => place.samePosition(latitude, longitude);

  WeatherCache confirmedAt(DateTime at, {String? lastModified}) => WeatherCache(
    latitude: latitude,
    longitude: longitude,
    hours: hours,
    fetchedAt: at.toUtc(),
    lastModified: lastModified ?? this.lastModified,
  );
}

String encodeWeatherCache(WeatherCache cache) => jsonEncode({
  'lat': cache.latitude,
  'lon': cache.longitude,
  'at': cache.fetchedAt.toUtc().millisecondsSinceEpoch,
  if (cache.lastModified != null) 'lm': cache.lastModified,
  'h': [for (final h in cache.hours) h.toJson()],
});

WeatherCache? decodeWeatherCache(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final lat = map['lat'];
    final lon = map['lon'];
    final at = map['at'];
    final list = map['h'];
    final lm = map['lm'];
    if (lat is! num || lon is! num || at is! int || list is! List) {
      return null;
    }
    final hours = [for (final h in list) ?WeatherHour.fromJson(h)];
    if (hours.isEmpty) return null;
    return WeatherCache(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      hours: hours,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      lastModified: lm is String ? lm : null,
    );
  } on FormatException {
    return null;
  }
}

// ---------------------------------------------------------------------------
// When to ask again
// ---------------------------------------------------------------------------

/// Shortest time between two forecast requests after an answer, even when
/// `Expires` is sooner: the card is a glance, not a live feed.
const kWeatherMinInterval = Duration(minutes: 60);

/// Wait after a failed request (offline, server error, unusable answer).
const kWeatherRetryGap = Duration(minutes: 30);

/// Longest wait taken from `Expires`. Guards against a wrong clock on either
/// side leaving the card without fresh data for days.
const kWeatherMaxWait = Duration(hours: 6);

/// How long the server allows the answer to be reused, from its `Expires`
/// and `Date` headers. Measured against the server's own `Date`, so a wrong
/// clock on this computer does not move it. Null without a usable `Expires`.
Duration? weatherServerTtl({
  required String? expires,
  required String? date,
  required DateTime now,
}) {
  final until = _httpDate(expires);
  if (until == null) return null;
  final base = _httpDate(date) ?? now.toUtc();
  final ttl = until.difference(base);
  return ttl.isNegative ? Duration.zero : ttl;
}

/// The wait in a 429 answer's `Retry-After` (seconds or an HTTP date).
Duration? weatherRetryAfter(String? header, {required DateTime now}) {
  if (header == null) return null;
  final seconds = int.tryParse(header.trim());
  if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
  final at = _httpDate(header);
  if (at == null) return null;
  final wait = at.difference(now.toUtc());
  return wait.isNegative ? Duration.zero : wait;
}

DateTime? _httpDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return HttpDate.parse(raw.trim());
  } on Object {
    return null;
  }
}

/// The time of the next request after an answer (200 or 304) at [now]: not
/// before the server's `Expires` and not before [kWeatherMinInterval], but
/// never later than [kWeatherMaxWait].
DateTime weatherNextAfterAnswer(DateTime now, Duration? serverTtl) {
  var wait = serverTtl ?? kWeatherMinInterval;
  if (wait < kWeatherMinInterval) wait = kWeatherMinInterval;
  if (wait > kWeatherMaxWait) wait = kWeatherMaxWait;
  return now.toUtc().add(wait);
}

/// The time of the next request after a 429 at [now]: the server's
/// `Retry-After`, but at least [kWeatherMinInterval].
DateTime weatherNextAfterThrottle(DateTime now, Duration? retryAfter) {
  var wait = retryAfter ?? kWeatherMinInterval;
  if (wait < kWeatherMinInterval) wait = kWeatherMinInterval;
  if (wait > kWeatherMaxWait) wait = kWeatherMaxWait;
  return now.toUtc().add(wait);
}

/// The time of the next request after a failure at [now].
DateTime weatherNextAfterFailure(DateTime now) =>
    now.toUtc().add(kWeatherRetryGap);

/// Whether the card may ask for [place] at [now]. Never without a place.
/// A forecast for another place (the place was changed) is due at once;
/// otherwise the stored [nextAttempt] decides.
bool weatherFetchDue({
  required WeatherPlace? place,
  required WeatherCache? cache,
  required DateTime? nextAttempt,
  required DateTime now,
}) {
  if (place == null) return false;
  if (cache == null || !cache.isFor(place)) {
    return nextAttempt == null || !now.toUtc().isBefore(nextAttempt);
  }
  if (nextAttempt == null) return true;
  // A stored time far ahead (clock set back) never blocks for longer than
  // the longest allowed wait.
  if (nextAttempt.difference(now.toUtc()) > kWeatherMaxWait) return true;
  return !now.toUtc().isBefore(nextAttempt);
}

// ---------------------------------------------------------------------------
// Place search (Nominatim)
// ---------------------------------------------------------------------------

/// Nominatim's limit: at most one request per second.
const kGeocodeMinGap = Duration(seconds: 1);

/// Shortest and longest query sent.
const kGeocodeQueryMin = 2;
const kGeocodeQueryMax = 120;

/// The query as sent, or null when it should not be sent at all.
String? geocodeQuery(String raw) {
  final q = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (q.length < kGeocodeQueryMin) return null;
  return q.length <= kGeocodeQueryMax ? q : q.substring(0, kGeocodeQueryMax);
}

/// One search hit: a short [name] for the card and the full [label] to tell
/// places of the same name apart.
class GeocodeResult {
  const GeocodeResult({
    required this.name,
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String label;
  final double latitude;
  final double longitude;

  /// The place to store, rounded.
  WeatherPlace toPlace() =>
      WeatherPlace(name: name, latitude: latitude, longitude: longitude);
}

/// The hits of a Nominatim `format=jsonv2` answer. Entries without usable
/// coordinates are dropped; null when the body is not such an answer.
/// Hits that round to the same spot and name appear once.
List<GeocodeResult>? parseNominatimResults(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final results = <GeocodeResult>[];
  final seen = <String>{};
  for (final item in decoded) {
    if (item is! Map) continue;
    final lat = double.tryParse('${item['lat']}');
    final lon = double.tryParse('${item['lon']}');
    if (lat == null || lon == null) continue;
    if (!_validLatitude(lat) || !_validLongitude(lon)) continue;
    final display = item['display_name'];
    final rawName = item['name'];
    final label = display is String ? display.trim() : '';
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : label.split(',').first.trim();
    if (name.isEmpty) continue;
    final key =
        '$name|${weatherRoundCoordinate(lat)}|${weatherRoundCoordinate(lon)}';
    if (!seen.add(key)) continue;
    results.add(
      GeocodeResult(
        name: name,
        label: label.isEmpty ? name : label,
        latitude: lat,
        longitude: lon,
      ),
    );
  }
  return results;
}
