/// The "Neuigkeiten" block of the Übersicht (#1568, part of #196): the pure
/// rules for reading RSS and Atom feeds, the fetch interval and the stored
/// state.
///
/// Only the title, the source, the date and the link of an entry are kept.
/// No summary, no full text, no image: the block points to the article, it
/// does not reproduce it. Everything here works on plain values, so the rules
/// are tested without network, storage or widgets.
///
/// Safety of the parser:
/// * A document with a document type declaration (`<!DOCTYPE`, which is where
///   entities are declared) is refused before parsing. `package:xml` never
///   loads external resources and only knows the five XML entities plus
///   numeric references, so neither an external entity nor an entity
///   expansion ("billion laughs") can run.
/// * Input above [kNewsFeedMaxBytes] is refused unread; at most
///   [kNewsFeedMaxItems] entries per feed are kept.
/// * Links must be `http`/`https` with a host and without user info, so a
///   feed cannot hand the browser a `javascript:`, `file:` or look-alike link.
/// * Control characters and bidirectional overrides are removed from titles,
///   so a title cannot disguise itself or a source.
library;

import 'dart:convert';

import 'package:xml/xml.dart';

/// Largest feed body read, in bytes. Typical feeds stay far below; a larger
/// answer is refused instead of parsed.
const int kNewsFeedMaxBytes = 2 * 1024 * 1024;

/// Entries kept per feed.
const int kNewsFeedMaxItems = 20;

/// Feeds a user can follow.
const int kNewsFeedMaxFeeds = 5;

/// Entries the block shows, newest first across all feeds.
const int kNewsShownItems = 5;

/// A feed is asked again at the earliest after this time (Nordstern: only
/// while the Übersicht is visible, never in the background).
const Duration kNewsFetchInterval = Duration(minutes: 60);

/// Longest kept title and source name, in characters.
const int _kMaxTitleLength = 300;
const int _kMaxSourceLength = 80;

/// One entry of a feed: what the block shows and where a click leads.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.link,
    required this.source,
    this.date,
  });

  final String title;

  /// `http`/`https` only (see [newsSafeLink]).
  final String link;

  /// The feed's own name, or its host when it has none.
  final String source;

  /// Publication or update time in UTC; null when the feed gives none.
  final DateTime? date;

  Map<String, Object?> toJson() => {
    't': title,
    'l': link,
    's': source,
    if (date != null) 'd': date!.toUtc().millisecondsSinceEpoch,
  };

  /// Null for anything that is not a well-formed stored entry, so a damaged
  /// value never breaks the block.
  static NewsItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['t'];
    final link = raw['l'];
    final source = raw['s'];
    final date = raw['d'];
    if (title is! String || link is! String || source is! String) return null;
    if (newsSafeLink(link) == null) return null;
    return NewsItem(
      title: title,
      link: link,
      source: source,
      date: date is int
          ? DateTime.fromMillisecondsSinceEpoch(date, isUtc: true)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NewsItem &&
      other.title == title &&
      other.link == link &&
      other.source == source &&
      other.date == date;

  @override
  int get hashCode => Object.hash(title, link, source, date);

  @override
  String toString() => 'NewsItem($title, $link, $source, $date)';
}

/// Why a feed could not be read.
enum NewsFeedError {
  /// More than [kNewsFeedMaxBytes].
  tooLarge,

  /// Declares a document type (and so possibly entities): refused.
  doctype,

  /// Not well-formed XML.
  malformed,

  /// Well-formed, but neither RSS nor Atom.
  notAFeed,
}

class NewsFeedException implements Exception {
  const NewsFeedException(this.error);

  final NewsFeedError error;

  @override
  String toString() => 'NewsFeedException(${error.name})';
}

/// The parsed feed: its name and up to [kNewsFeedMaxItems] entries in feed
/// order.
class NewsFeed {
  const NewsFeed({required this.source, required this.items});

  final String source;
  final List<NewsItem> items;
}

final RegExp _doctype = RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false);

/// Parses an RSS 2.0, RSS 1.0 (RDF) or Atom document fetched from [feedUrl].
/// Relative links are resolved against [feedUrl]; the host of [feedUrl] names
/// a feed without a title. Throws [NewsFeedException].
NewsFeed parseNewsFeed(String body, {required Uri feedUrl}) {
  // Characters, not bytes; a UTF-8 body has at least as many bytes, so this
  // never lets more through than the byte limit of the fetch.
  if (body.length > kNewsFeedMaxBytes) {
    throw const NewsFeedException(NewsFeedError.tooLarge);
  }
  if (_doctype.hasMatch(body)) {
    throw const NewsFeedException(NewsFeedError.doctype);
  }
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException {
    throw const NewsFeedException(NewsFeedError.malformed);
  }
  final root = doc.rootElement;
  final fallbackSource = _clean(feedUrl.host, _kMaxSourceLength);
  switch (root.localName.toLowerCase()) {
    case 'rss':
      final channel = _child(root, 'channel');
      if (channel == null) {
        throw const NewsFeedException(NewsFeedError.notAFeed);
      }
      final source = _sourceName(_childText(channel, 'title'), fallbackSource);
      return NewsFeed(
        source: source,
        items: _rssItems(
          channel.childElements,
          feedUrl: feedUrl,
          source: source,
        ),
      );
    case 'rdf':
      final channel = _child(root, 'channel');
      final source = _sourceName(
        channel == null ? null : _childText(channel, 'title'),
        fallbackSource,
      );
      return NewsFeed(
        source: source,
        items: _rssItems(root.childElements, feedUrl: feedUrl, source: source),
      );
    case 'feed':
      final source = _sourceName(_childText(root, 'title'), fallbackSource);
      return NewsFeed(
        source: source,
        items: _atomEntries(root, feedUrl: feedUrl, source: source),
      );
  }
  throw const NewsFeedException(NewsFeedError.notAFeed);
}

String _sourceName(String? raw, String fallback) {
  final name = raw == null ? '' : _clean(raw, _kMaxSourceLength);
  return name.isEmpty ? fallback : name;
}

List<NewsItem> _rssItems(
  Iterable<XmlElement> elements, {
  required Uri feedUrl,
  required String source,
}) {
  final items = <NewsItem>[];
  for (final item in elements) {
    if (items.length >= kNewsFeedMaxItems) break;
    if (item.localName.toLowerCase() != 'item') continue;
    final title = _clean(_childText(item, 'title') ?? '', _kMaxTitleLength);
    var link = _resolveLink(_childText(item, 'link'), feedUrl);
    if (link == null) {
      final guid = _child(item, 'guid');
      if (guid != null && guid.getAttribute('isPermaLink') != 'false') {
        link = _resolveLink(guid.innerText, feedUrl);
      }
    }
    if (title.isEmpty || link == null) continue;
    final date = parseNewsDate(
      _childText(item, 'pubDate') ?? _childText(item, 'date'),
    );
    items.add(NewsItem(title: title, link: link, source: source, date: date));
  }
  return items;
}

List<NewsItem> _atomEntries(
  XmlElement feed, {
  required Uri feedUrl,
  required String source,
}) {
  final items = <NewsItem>[];
  for (final entry in feed.childElements) {
    if (items.length >= kNewsFeedMaxItems) break;
    if (entry.localName.toLowerCase() != 'entry') continue;
    final title = _clean(_childText(entry, 'title') ?? '', _kMaxTitleLength);
    String? link;
    for (final l in entry.childElements) {
      if (l.localName.toLowerCase() != 'link') continue;
      final rel = l.getAttribute('rel');
      if (rel != null && rel != 'alternate') continue;
      link = _resolveLink(l.getAttribute('href'), feedUrl);
      if (link != null) break;
    }
    if (title.isEmpty || link == null) continue;
    final date = parseNewsDate(
      _childText(entry, 'published') ?? _childText(entry, 'updated'),
    );
    items.add(NewsItem(title: title, link: link, source: source, date: date));
  }
  return items;
}

XmlElement? _child(XmlElement parent, String localName) {
  for (final e in parent.childElements) {
    if (e.localName.toLowerCase() == localName.toLowerCase()) return e;
  }
  return null;
}

String? _childText(XmlElement parent, String localName) =>
    _child(parent, localName)?.innerText;

String? _resolveLink(String? raw, Uri base) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final Uri parsed;
  try {
    parsed = base.resolve(text);
  } on FormatException {
    return null;
  }
  return newsSafeLink(parsed.toString());
}

/// [raw] when it is an absolute `http`/`https` address with a host and without
/// user info; otherwise null. A `javascript:`, `file:`, `data:` link or one of
/// the form `https://trusted.example@other.example` never reaches the browser.
String? newsSafeLink(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw.trim());
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri.toString();
}

final RegExp _tags = RegExp(r'<[^>]*>');
final RegExp _space = RegExp(r'\s+');

/// Control characters (C0, DEL, C1) and the bidirectional embedding,
/// override and isolate marks.
final RegExp _unsafeChars = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  unicode: true,
);

const Map<String, String> _htmlEntities = {
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
  '&amp;': '&',
};

/// One line of plain text: markup a feed escaped into the title (Atom
/// `type="html"`) is dropped, the common HTML entities left after that are
/// decoded, unsafe characters removed, whitespace collapsed, and the result
/// cut at [max] characters.
String _clean(String raw, int max) {
  var s = raw.replaceAll(_tags, ' ');
  // `&amp;` last, so `&amp;lt;` stays the text "&lt;" instead of becoming "<".
  for (final e in _htmlEntities.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  s = s.replaceAll(_unsafeChars, ' ').replaceAll(_space, ' ').trim();
  if (s.length > max) s = '${s.substring(0, max - 1).trimRight()}…';
  return s;
}

const Map<String, int> _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

const Map<String, int> _zones = {
  'gmt': 0,
  'ut': 0,
  'utc': 0,
  'z': 0,
  'est': -5,
  'edt': -4,
  'cst': -6,
  'cdt': -5,
  'mst': -7,
  'mdt': -6,
  'pst': -8,
  'pdt': -7,
};

final RegExp _rfc822 = RegExp(
  r'^(?:[a-z]{3,},?\s*)?(\d{1,2})\s+([a-z]{3})[a-z]*\.?\s+(\d{2,4})'
  r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([a-z]+|[+-]\d{4})?$',
  caseSensitive: false,
);

/// The date of an entry in UTC: RFC 822 (RSS `pubDate`) or ISO 8601 (Atom,
/// Dublin Core). Null when it cannot be read; such entries sort last.
DateTime? parseNewsDate(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc();
  final m = _rfc822.firstMatch(text);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m.group(3)!);
  if (year < 100) year += year < 50 ? 2000 : 1900;
  final zone = m.group(7)?.toLowerCase();
  var offsetMinutes = 0;
  if (zone != null) {
    if (zone.startsWith('+') || zone.startsWith('-')) {
      final sign = zone.startsWith('-') ? -1 : 1;
      offsetMinutes =
          sign *
          (int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3)));
    } else {
      final hours = _zones[zone];
      if (hours == null) return null;
      offsetMinutes = hours * 60;
    }
  }
  final local = DateTime.utc(
    year,
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4) ?? '0'),
    int.parse(m.group(5) ?? '0'),
    int.parse(m.group(6) ?? '0'),
  );
  return local.subtract(Duration(minutes: offsetMinutes));
}

// ---------------------------------------------------------------------------
// Feed addresses
// ---------------------------------------------------------------------------

/// Why an address cannot be added.
enum NewsFeedUrlProblem { invalid, duplicate, full }

/// The address the user typed, as it is stored: trimmed, `https://` added when
/// no scheme is given. Null when it is not an `http`/`https` address with a
/// host (see [newsSafeLink]).
String? normalizeNewsFeedUrl(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  if (!text.contains('://')) text = 'https://$text';
  final safe = newsSafeLink(text);
  if (safe == null) return null;
  final uri = Uri.parse(safe);
  // A bare word ("blog") is no address; a host needs a dot or is localhost.
  if (!uri.host.contains('.') && uri.host != 'localhost') return null;
  return safe;
}

/// What is wrong with adding [input] to [feeds], or null when it can be
/// added.
NewsFeedUrlProblem? newsFeedUrlProblem(String input, List<String> feeds) {
  final url = normalizeNewsFeedUrl(input);
  if (url == null) return NewsFeedUrlProblem.invalid;
  if (feeds.contains(url)) return NewsFeedUrlProblem.duplicate;
  if (feeds.length >= kNewsFeedMaxFeeds) return NewsFeedUrlProblem.full;
  return null;
}

/// The stored list of feed addresses (one per line). Unsafe or repeated lines
/// and anything above [kNewsFeedMaxFeeds] are dropped.
List<String> newsFeedsFromStored(String? raw) {
  final out = <String>[];
  for (final line in (raw ?? '').split('\n')) {
    final url = newsSafeLink(line);
    if (url == null || out.contains(url)) continue;
    out.add(url);
    if (out.length >= kNewsFeedMaxFeeds) break;
  }
  return out;
}

String newsFeedsToStored(List<String> feeds) => feeds.join('\n');

// ---------------------------------------------------------------------------
// Fetch interval and stored results
// ---------------------------------------------------------------------------

/// What is known about one feed: its last attempt, its last success and the
/// entries from that success.
class NewsFeedRecord {
  const NewsFeedRecord({
    this.source,
    this.items = const [],
    this.lastAttempt,
    this.lastSuccess,
    this.failed = false,
  });

  /// The feed's name from the last success.
  final String? source;
  final List<NewsItem> items;
  final DateTime? lastAttempt;
  final DateTime? lastSuccess;

  /// The last attempt failed (offline, refused, not a feed). The entries of
  /// the last success stay.
  final bool failed;

  Map<String, Object?> toJson() => {
    if (source != null) 's': source,
    'i': [for (final i in items) i.toJson()],
    if (lastAttempt != null) 'a': lastAttempt!.toUtc().millisecondsSinceEpoch,
    if (lastSuccess != null) 'o': lastSuccess!.toUtc().millisecondsSinceEpoch,
    if (failed) 'f': true,
  };

  static NewsFeedRecord fromJson(Object? raw) {
    if (raw is! Map) return const NewsFeedRecord();
    DateTime? time(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true) : null;
    final items = raw['i'];
    return NewsFeedRecord(
      source: raw['s'] is String ? raw['s'] as String : null,
      items: [
        if (items is List)
          for (final i in items.take(kNewsFeedMaxItems)) ?NewsItem.fromJson(i),
      ],
      lastAttempt: time(raw['a']),
      lastSuccess: time(raw['o']),
      failed: raw['f'] == true,
    );
  }
}

/// The stored records by feed address, from their JSON form. Damaged input
/// gives an empty map: the next visit simply asks again.
Map<String, NewsFeedRecord> newsRecordsFromStored(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final e in decoded.entries)
        if (e.key is String && newsSafeLink(e.key as String) != null)
          e.key as String: NewsFeedRecord.fromJson(e.value),
    };
  } on FormatException {
    return {};
  }
}

String newsRecordsToStored(Map<String, NewsFeedRecord> records) =>
    jsonEncode({for (final e in records.entries) e.key: e.value.toJson()});

/// Whether a feed last asked at [lastAttempt] may be asked at [now]. Never
/// asked: yes. A clock that went back counts as due, so the block cannot get
/// stuck until the clock catches up.
bool newsFetchDue({required DateTime? lastAttempt, required DateTime now}) {
  if (lastAttempt == null) return true;
  if (now.isBefore(lastAttempt)) return true;
  return now.difference(lastAttempt) >= kNewsFetchInterval;
}

/// The feeds of [feeds] that may be asked at [now].
List<String> newsFeedsDue({
  required List<String> feeds,
  required Map<String, NewsFeedRecord> records,
  required DateTime now,
}) => [
  for (final f in feeds)
    if (newsFetchDue(lastAttempt: records[f]?.lastAttempt, now: now)) f,
];

/// How long until the next of [feeds] is due, or null when there are none.
/// Zero when one is due now.
Duration? newsNextFetchIn({
  required List<String> feeds,
  required Map<String, NewsFeedRecord> records,
  required DateTime now,
}) {
  Duration? next;
  for (final f in feeds) {
    final last = records[f]?.lastAttempt;
    final wait = newsFetchDue(lastAttempt: last, now: now)
        ? Duration.zero
        : kNewsFetchInterval - now.difference(last!);
    if (next == null || wait < next) next = wait;
  }
  return next;
}

/// The entries the block shows: from [feeds] only, one per link, newest
/// first, undated last, at most [count].
List<NewsItem> newsShownItems({
  required List<String> feeds,
  required Map<String, NewsFeedRecord> records,
  int count = kNewsShownItems,
}) {
  final seen = <String>{};
  final all = <NewsItem>[
    for (final f in feeds)
      for (final i in records[f]?.items ?? const <NewsItem>[])
        if (seen.add(i.link)) i,
  ];
  // A stable sort keeps the feed order among entries with the same date.
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final da = a.$2.date;
      final db = b.$2.date;
      if (da != null && db != null && da != db) return db.compareTo(da);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return a.$1.compareTo(b.$1);
    });
  return [for (final (_, i) in indexed.take(count)) i];
}
