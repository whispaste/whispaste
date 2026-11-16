/// Hand-over points of the news block (#1568): the menu entry switches the
/// stored block on, the suggestion adds the blog feed, an entry hands its link
/// to the browser, and the sources dialog removes a feed. Elements are found
/// by testID; layout and wording are judged by eye, not tested.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/overview/news_feed.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_customize_menu.dart';
import 'package:whispaste/features/overview/overview_news.dart';
import 'package:whispaste/features/overview/overview_providers.dart';
import 'package:whispaste/services/news_feed_service.dart';

import '../../fixtures/test_helpers.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

class _MemoryStore implements NewsFeedStore {
  _MemoryStore(this.feeds);

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

/// Answers every feed with one entry that links to `<feed>/post`.
class _OneEntryFetcher implements NewsFeedFetcher {
  final calls = <String>[];

  @override
  Future<NewsFeed?> fetch(Uri url) async {
    calls.add(url.toString());
    return NewsFeed(
      source: url.host,
      items: [
        NewsItem(
          title: 'Post',
          link: url.resolve('post').toString(),
          source: url.host,
          date: DateTime.utc(2026, 11, 1),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('the menu entry switches the off-by-default block on', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: OverviewCustomizeMenu())),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OverviewCustomizeMenu)),
    );
    expect(
      container.read(overviewPrefsProvider).isBlockShown(OverviewBlock.news),
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('overview-customize')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is CheckboxMenuButton &&
            w.key == const ValueKey('overview-customize-news'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(overviewPrefsProvider).isBlockShown(OverviewBlock.news),
      isTrue,
    );
  });

  Future<(_MemoryStore, _OneEntryFetcher, _FakeUrlLauncher)> pumpBlock(
    WidgetTester tester, {
    List<String> feeds = const [],
  }) async {
    final launcher = _FakeUrlLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    final store = _MemoryStore([...feeds]);
    final fetcher = _OneEntryFetcher();
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: SingleChildScrollView(child: OverviewNews())),
        locale: const Locale('en'),
        overrides: [
          newsFeedStoreProvider.overrideWithValue(store),
          newsFeedFetcherProvider.overrideWithValue(fetcher),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return (store, fetcher, launcher);
  }

  testWidgets('the suggestion adds the blog feed, which is asked at once', (
    tester,
  ) async {
    final (store, fetcher, _) = await pumpBlock(tester);
    expect(fetcher.calls, isEmpty, reason: 'no feed, no request');
    await tester.tap(find.bySemanticsIdentifier('overview-news-add-blog'));
    await tester.pumpAndSettle();
    expect(store.feeds, [blogFeedUrl('en')]);
    expect(fetcher.calls, [blogFeedUrl('en')]);
  });

  testWidgets('an entry hands its link to the browser', (tester) async {
    const feed = 'https://a.example/feed.xml';
    final (_, _, launcher) = await pumpBlock(tester, feeds: [feed]);
    await tester.tap(find.bySemanticsIdentifier('overview-news-open-0'));
    await tester.pumpAndSettle();
    expect(launcher.launched, ['https://a.example/post']);
  });

  testWidgets('the sources dialog removes a feed with its entries', (
    tester,
  ) async {
    const feed = 'https://a.example/feed.xml';
    final (store, _, _) = await pumpBlock(tester, feeds: [feed]);
    await tester.tap(find.bySemanticsIdentifier('overview-news-all'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('overview-news-source-remove-0'),
    );
    await tester.pumpAndSettle();
    expect(store.feeds, isEmpty);
    expect(store.records, isEmpty);
    await tester.tap(find.byKey(const ValueKey('overview-news-sources-done')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overview-news-no-sources')),
      findsOneWidget,
    );
  });
}
