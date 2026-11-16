/// The rules of the news block (#1568): reading RSS and Atom safely, the
/// hourly fetch interval and the stored state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/news_feed.dart';
import 'package:whispaste/core/overview/overview_logic.dart';

final _feedUrl = Uri.parse('https://news.example.org/feed.xml');

NewsFeed _parse(String body) => parseNewsFeed(body, feedUrl: _feedUrl);

Matcher _refused(NewsFeedError error) =>
    throwsA(isA<NewsFeedException>().having((e) => e.error, 'error', error));

const _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>Example &amp; Co</title>
  <item>
    <title>First post</title>
    <link>https://news.example.org/first/</link>
    <description>Full text that must never be kept.</description>
    <pubDate>Sat, 17 Oct 2026 08:30:00 +0200</pubDate>
  </item>
  <item>
    <title>Relative link</title>
    <link>/second/</link>
    <pubDate>Fri, 16 Oct 2026 00:00:00 GMT</pubDate>
  </item>
  <item>
    <title>Guid only</title>
    <guid>https://news.example.org/third/</guid>
  </item>
  <item><title>No link at all</title></item>
  <item><link>https://news.example.org/untitled/</link></item>
</channel></rss>''';

const _atom = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title type="text">Atom Example</title>
  <entry>
    <title type="html">&lt;b&gt;Bold&lt;/b&gt; release</title>
    <link rel="edit" href="https://news.example.org/edit/1"/>
    <link rel="alternate" href="https://news.example.org/posts/1"/>
    <summary>Never kept.</summary>
    <updated>2026-11-01T10:00:00+01:00</updated>
  </entry>
  <entry>
    <title>Plain link</title>
    <link href="posts/2"/>
    <published>2026-11-02T00:00:00Z</published>
  </entry>
</feed>''';

void main() {
  group('parseNewsFeed reads', () {
    test('RSS 2.0: title, link, source and date, nothing else', () {
      final feed = _parse(_rss);
      expect(feed.source, 'Example & Co');
      expect(feed.items.map((i) => i.title), [
        'First post',
        'Relative link',
        'Guid only',
      ]);
      expect(feed.items.map((i) => i.link), [
        'https://news.example.org/first/',
        'https://news.example.org/second/',
        'https://news.example.org/third/',
      ]);
      expect(feed.items.first.date, DateTime.utc(2026, 10, 17, 6, 30));
      expect(feed.items[1].date, DateTime.utc(2026, 10, 16));
      expect(feed.items[2].date, isNull);
      expect(feed.items.every((i) => i.source == 'Example & Co'), isTrue);
      expect(
        feed.items.map((i) => i.toJson().toString()).join(),
        isNot(contains('Full text')),
      );
    });

    test('Atom: the alternate link, markup in a title removed', () {
      final feed = _parse(_atom);
      expect(feed.source, 'Atom Example');
      expect(feed.items.map((i) => i.title), ['Bold release', 'Plain link']);
      expect(feed.items.map((i) => i.link), [
        'https://news.example.org/posts/1',
        'https://news.example.org/posts/2',
      ]);
      expect(feed.items.first.date, DateTime.utc(2026, 11, 1, 9));
    });

    test('RSS 1.0 (RDF)', () {
      final feed = _parse('''<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel><title>RDF Example</title></channel>
  <item><title>One</title><link>https://rdf.example.org/1</link>
    <dc:date>2026-09-01T12:00:00Z</dc:date></item>
</rdf:RDF>''');
      expect(feed.source, 'RDF Example');
      expect(feed.items.single.link, 'https://rdf.example.org/1');
      expect(feed.items.single.date, DateTime.utc(2026, 9, 1, 12));
    });

    test('a feed without a title is named by its host', () {
      final feed = _parse(
        '<rss><channel><item><title>A</title>'
        '<link>https://a.example/</link></item></channel></rss>',
      );
      expect(feed.source, 'news.example.org');
    });

    test('keeps at most kNewsFeedMaxItems entries', () {
      final items = List.generate(
        kNewsFeedMaxItems + 10,
        (i) =>
            '<item><title>T$i</title><link>https://a.example/$i</link></item>',
      ).join();
      final feed = _parse('<rss><channel>$items</channel></rss>');
      expect(feed.items, hasLength(kNewsFeedMaxItems));
    });
  });

  group('parseNewsFeed refuses malicious or broken feeds', () {
    test('an entity expansion bomb is refused before parsing', () {
      const bomb = '''<?xml version="1.0"?>
<!DOCTYPE lolz [
  <!ENTITY lol "lol">
  <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
  <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
]>
<rss><channel><item><title>&lol3;</title>
<link>https://a.example/</link></item></channel></rss>''';
      expect(() => _parse(bomb), _refused(NewsFeedError.doctype));
    });

    test('an external entity is refused, nothing is read from disk', () {
      const xxe = '''<?xml version="1.0"?>
<!doctype rss [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<rss><channel><item><title>&xxe;</title>
<link>https://a.example/</link></item></channel></rss>''';
      expect(() => _parse(xxe), _refused(NewsFeedError.doctype));
    });

    test('an undeclared entity stays text, it is never resolved', () {
      final feed = _parse(
        '<rss><channel><item><title>A &xxe; B</title>'
        '<link>https://a.example/</link></item></channel></rss>',
      );
      expect(feed.items.single.title, 'A &xxe; B');
    });

    test('a feed above the size limit is not parsed', () {
      final huge = '<rss><channel>${' ' * kNewsFeedMaxBytes}</channel></rss>';
      expect(() => _parse(huge), _refused(NewsFeedError.tooLarge));
    });

    test('broken XML', () {
      expect(
        () => _parse('<rss><channel><item><title>x</item></rss>'),
        _refused(NewsFeedError.malformed),
      );
      expect(() => _parse(''), _refused(NewsFeedError.malformed));
    });

    test('an HTML page or other XML is not a feed', () {
      expect(
        () => _parse('<html><body>Hello</body></html>'),
        _refused(NewsFeedError.notAFeed),
      );
      expect(() => _parse('<rss/>'), _refused(NewsFeedError.notAFeed));
    });

    test('script, file and look-alike links are dropped', () {
      final feed = _parse('''<rss><channel>
<item><title>Script</title><link>javascript:alert(1)</link></item>
<item><title>File</title><link>file:///etc/passwd</link></item>
<item><title>Data</title><link>data:text/html,hi</link></item>
<item><title>Look-alike</title><link>https://bank.example@evil.example/</link></item>
<item><title>Good</title><link>https://good.example/</link></item>
</channel></rss>''');
      expect(feed.items.map((i) => i.title), ['Good']);
    });

    test('control and direction-changing characters leave titles', () {
      final feed = _parse(
        '<rss><channel><title>Src&#x202E;evil</title><item>'
        '<title>A&#x202E;B&#x7;C\nD</title>'
        '<link>https://a.example/</link></item></channel></rss>',
      );
      expect(feed.items.single.title, 'A B C D');
      expect(feed.source, 'Src evil');
    });

    test('an overlong title is cut', () {
      final feed = _parse(
        '<rss><channel><item><title>${'x' * 1000}</title>'
        '<link>https://a.example/</link></item></channel></rss>',
      );
      expect(feed.items.single.title.length, lessThanOrEqualTo(300));
    });
  });

  group('parseNewsDate', () {
    test('RFC 822 with names, offsets and two-digit years', () {
      expect(
        parseNewsDate('Tue, 03 Nov 2026 02:21:58 GMT'),
        DateTime.utc(2026, 11, 3, 2, 21, 58),
      );
      expect(
        parseNewsDate('3 Nov 26 10:00 EST'),
        DateTime.utc(2026, 11, 3, 15),
      );
      expect(
        parseNewsDate('Tue, 3 Nov 2026 10:00:00 -0130'),
        DateTime.utc(2026, 11, 3, 11, 30),
      );
    });

    test('ISO 8601', () {
      expect(
        parseNewsDate('2026-11-03T10:00:00+02:00'),
        DateTime.utc(2026, 11, 3, 8),
      );
    });

    test('unreadable dates are null', () {
      expect(parseNewsDate(null), isNull);
      expect(parseNewsDate(''), isNull);
      expect(parseNewsDate('yesterday'), isNull);
      expect(parseNewsDate('3 Foo 2026 10:00 GMT'), isNull);
      expect(parseNewsDate('3 Nov 2026 10:00 XYZ'), isNull);
    });
  });

  group('fetch interval', () {
    final now = DateTime.utc(2026, 11, 15, 12);

    test('a feed never asked is due', () {
      expect(newsFetchDue(lastAttempt: null, now: now), isTrue);
    });

    test('not again within the hour, also after a failure', () {
      expect(
        newsFetchDue(
          lastAttempt: now.subtract(const Duration(minutes: 59)),
          now: now,
        ),
        isFalse,
      );
      expect(
        newsFetchDue(lastAttempt: now.subtract(kNewsFetchInterval), now: now),
        isTrue,
      );
      expect(kNewsFetchInterval, const Duration(minutes: 60));
    });

    test('a clock that went back does not block the block', () {
      expect(
        newsFetchDue(lastAttempt: now.add(const Duration(hours: 3)), now: now),
        isTrue,
      );
    });

    test('only the due feeds are asked, the wait is to the next one', () {
      const a = 'https://a.example/feed';
      const b = 'https://b.example/feed';
      final records = {
        a: NewsFeedRecord(
          lastAttempt: now.subtract(const Duration(minutes: 20)),
        ),
        b: NewsFeedRecord(
          lastAttempt: now.subtract(const Duration(minutes: 50)),
        ),
      };
      expect(newsFeedsDue(feeds: [a, b], records: records, now: now), isEmpty);
      expect(
        newsNextFetchIn(feeds: [a, b], records: records, now: now),
        const Duration(minutes: 10),
      );
      expect(
        newsFeedsDue(
          feeds: [a, b, 'https://c.example/'],
          records: records,
          now: now,
        ),
        ['https://c.example/'],
      );
      expect(
        newsNextFetchIn(feeds: const [], records: records, now: now),
        isNull,
      );
    });
  });

  group('shown entries', () {
    NewsItem item(String id, DateTime? date, {String source = 'S'}) => NewsItem(
      title: id,
      link: 'https://a.example/$id',
      source: source,
      date: date,
    );

    test('newest first across feeds, one per link, undated last', () {
      final records = {
        'https://a.example/f': NewsFeedRecord(
          items: [
            item('a1', DateTime.utc(2026, 11, 1)),
            item('none', null),
            item('dup', DateTime.utc(2026, 10, 1)),
          ],
        ),
        'https://b.example/f': NewsFeedRecord(
          items: [
            item('b1', DateTime.utc(2026, 11, 3)),
            item('dup', DateTime.utc(2026, 10, 1)),
          ],
        ),
        'https://removed.example/f': NewsFeedRecord(
          items: [item('gone', DateTime.utc(2026, 12, 1))],
        ),
      };
      final shown = newsShownItems(
        feeds: const ['https://a.example/f', 'https://b.example/f'],
        records: records,
      );
      expect(shown.map((i) => i.title), ['b1', 'a1', 'dup', 'none']);
      expect(
        newsShownItems(
          feeds: const ['https://a.example/f', 'https://b.example/f'],
          records: records,
          count: 2,
        ),
        hasLength(2),
      );
    });
  });

  group('stored state', () {
    test('records round-trip', () {
      final records = {
        'https://a.example/f': NewsFeedRecord(
          source: 'A',
          items: [
            NewsItem(
              title: 'T',
              link: 'https://a.example/1',
              source: 'A',
              date: DateTime.utc(2026, 11, 1),
            ),
          ],
          lastAttempt: DateTime.utc(2026, 11, 15, 10),
          lastSuccess: DateTime.utc(2026, 11, 15, 9),
          failed: true,
        ),
      };
      final back = newsRecordsFromStored(newsRecordsToStored(records));
      final r = back['https://a.example/f']!;
      expect(r.source, 'A');
      expect(r.items, records['https://a.example/f']!.items);
      expect(r.lastAttempt, DateTime.utc(2026, 11, 15, 10));
      expect(r.lastSuccess, DateTime.utc(2026, 11, 15, 9));
      expect(r.failed, isTrue);
    });

    test('damaged or tampered values give nothing instead of failing', () {
      expect(newsRecordsFromStored(null), isEmpty);
      expect(newsRecordsFromStored('{not json'), isEmpty);
      expect(newsRecordsFromStored('[1,2]'), isEmpty);
      final tampered = newsRecordsFromStored(
        '{"javascript:x": {}, "https://a.example/": {"i": '
        '[{"t": "x", "l": "javascript:alert(1)", "s": "s"}, 5]}}',
      );
      expect(tampered.keys, ['https://a.example/']);
      expect(tampered.values.single.items, isEmpty);
    });

    test('the feed list keeps safe, unique addresses up to the limit', () {
      final stored = [
        'https://a.example/f',
        'https://a.example/f',
        'file:///etc/passwd',
        for (var i = 0; i < 10; i++) 'https://n$i.example/f',
      ].join('\n');
      final feeds = newsFeedsFromStored(stored);
      expect(feeds.first, 'https://a.example/f');
      expect(feeds, hasLength(kNewsFeedMaxFeeds));
      expect(feeds, isNot(contains('file:///etc/passwd')));
      expect(newsFeedsFromStored(newsFeedsToStored(feeds)), feeds);
      expect(newsFeedsFromStored(null), isEmpty);
    });
  });

  group('adding an address', () {
    test('https is added when no scheme is given', () {
      expect(
        normalizeNewsFeedUrl('  whispaste.de/blog/feed.xml '),
        'https://whispaste.de/blog/feed.xml',
      );
      expect(
        normalizeNewsFeedUrl('http://example.org/rss'),
        'http://example.org/rss',
      );
    });

    test('no address, other schemes and user info are refused', () {
      for (final bad in [
        '',
        'blog',
        'ftp://example.org/feed',
        'javascript:alert(1)',
        'https://a.example@b.example/',
        'https://exa mple.org/',
      ]) {
        expect(normalizeNewsFeedUrl(bad), isNull, reason: bad);
      }
    });

    test('a repeated address and a full list are named', () {
      const feeds = ['https://a.example/f'];
      expect(
        newsFeedUrlProblem('a.example/f', feeds),
        NewsFeedUrlProblem.duplicate,
      );
      expect(newsFeedUrlProblem('nope', feeds), NewsFeedUrlProblem.invalid);
      expect(newsFeedUrlProblem('b.example/f', feeds), isNull);
      final full = [
        for (var i = 0; i < kNewsFeedMaxFeeds; i++) 'https://n$i.example/',
      ];
      expect(newsFeedUrlProblem('b.example/f', full), NewsFeedUrlProblem.full);
    });
  });

  test('the news block is off until it is switched on', () {
    expect(OverviewBlock.news.shownByDefault, isFalse);
    expect(
      overviewBlockShown(OverviewBlock.news, hidden: const {}, shown: const {}),
      isFalse,
    );
    expect(
      overviewShownBlocksFromStored(
        overviewShownBlocksToStored({OverviewBlock.news}),
      ),
      {OverviewBlock.news},
    );
  });
}
