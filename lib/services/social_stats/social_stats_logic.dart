/// Live project numbers for the "Mitmachen" block: the answer contract of
/// `GET /v1/public/social-stats`, the storage format and the timing rules.
/// Pure Dart, no network and no clock of its own, so every rule is tested
/// with a fixed time.
library;

import 'dart:convert';

/// The only answer schema this app reads.
const int kSocialStatsSchema = 1;

/// At most one network attempt per this span, successful or not.
const Duration kSocialStatsAttemptGap = Duration(hours: 24);

/// A stored number older than this is no longer shown; its label stays.
const Duration kSocialStatsMaxAge = Duration(days: 7);

/// One usable answer, stamped with the time this app received it.
class SocialStatsSnapshot {
  const SocialStatsSnapshot({
    required this.stars,
    required this.subscribers,
    required this.fetchedAt,
  });

  /// Null when the server has no number (hidden, or not sent).
  final int? stars;
  final int? subscribers;
  final DateTime fetchedAt;
}

/// What the block shows. A null number means: show the label and the benefit
/// line, no number. Never an error text.
class SocialStatsView {
  const SocialStatsView({this.stars, this.subscribers});

  final int? stars;
  final int? subscribers;
}

/// Reads one answer body. Returns null when the answer is not usable: not
/// JSON, another schema, a missing field, or a count that is not a whole
/// number of zero or more. A null count inside a valid answer is "no number".
SocialStatsSnapshot? parseSocialStats(
  String body, {
  required DateTime fetchedAt,
}) {
  final Object? data;
  try {
    data = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (data is! Map<String, Object?>) return null;
  if (data['schema'] != kSocialStatsSchema) return null;
  if (data['updatedAt'] is! String || data['stale'] is! bool) return null;

  final github = data['github'];
  final youtube = data['youtube'];
  if (github is! Map<String, Object?> || youtube is! Map<String, Object?>) {
    return null;
  }
  if (!github.containsKey('stars') || !youtube.containsKey('subscribers')) {
    return null;
  }
  final stars = github['stars'];
  final subscribers = youtube['subscribers'];
  if (!_isCountOrNull(stars) || !_isCountOrNull(subscribers)) return null;

  return SocialStatsSnapshot(
    stars: stars as int?,
    subscribers: subscribers as int?,
    fetchedAt: fetchedAt,
  );
}

bool _isCountOrNull(Object? value) =>
    value == null || (value is int && value >= 0);

/// The numbers to show now: none when there is no answer or it is older than
/// [kSocialStatsMaxAge].
SocialStatsView socialStatsView(SocialStatsSnapshot? snapshot, DateTime now) {
  if (snapshot == null) return const SocialStatsView();
  if (now.difference(snapshot.fetchedAt) > kSocialStatsMaxAge) {
    return const SocialStatsView();
  }
  return SocialStatsView(
    stars: snapshot.stars,
    subscribers: snapshot.subscribers,
  );
}

/// True when the last attempt is at least [kSocialStatsAttemptGap] old, or
/// never happened. A stored time in the future (the clock was set back) also
/// counts as due, once.
bool socialStatsFetchDue({
  required DateTime? lastAttempt,
  required DateTime now,
}) {
  if (lastAttempt == null) return true;
  final since = now.difference(lastAttempt);
  if (since.isNegative) return true;
  return since >= kSocialStatsAttemptGap;
}

/// Storage format for the last usable answer (one app setting).
String encodeSocialStatsSnapshot(SocialStatsSnapshot snapshot) => jsonEncode({
  'stars': snapshot.stars,
  'subscribers': snapshot.subscribers,
  'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
});

/// Reads the stored answer; null when the stored text is missing or broken.
SocialStatsSnapshot? decodeSocialStatsSnapshot(String? raw) {
  if (raw == null) return null;
  final Object? data;
  try {
    data = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (data is! Map<String, Object?>) return null;
  final stars = data['stars'];
  final subscribers = data['subscribers'];
  final fetchedAt = data['fetchedAt'];
  if (!_isCountOrNull(stars) || !_isCountOrNull(subscribers)) return null;
  if (fetchedAt is! int) return null;
  return SocialStatsSnapshot(
    stars: stars as int?,
    subscribers: subscribers as int?,
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt, isUtc: true),
  );
}
