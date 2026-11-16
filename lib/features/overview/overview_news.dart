import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_urls.dart' show blogFeedUrl;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/news_feed.dart';
import '../../core/overview/overview_logic.dart'
    show OverviewDay, overviewDayOf;
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/app_identity/app_category.dart';
import '../../services/news_feed_service.dart';
import '../../widgets/external_link.dart';
import '../../widgets/wp_app_icon.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';
import '../history/widgets/history_helpers.dart' show formatHistoryTime;
import 'overview_news_sources_dialog.dart';
import 'overview_rows.dart';
import 'overview_window_active.dart';

/// "Neuigkeiten" (#1568): the newest entries of the RSS or Atom feeds the user
/// chose, in the same card and rows as the recordings and notes
/// ([OverviewRowsCard]). Only title, source and date; a click opens the
/// article in the browser. Off by default, switched on under "Übersicht
/// anpassen"; "Quellen" picks the feeds, the WhisPaste blog is suggested.
///
/// Feeds are asked only while this block is on the page and the window is
/// active, each at most once an hour ([NewsFeedNotifier]).
class OverviewNews extends ConsumerStatefulWidget {
  const OverviewNews({super.key});

  @override
  ConsumerState<OverviewNews> createState() => _OverviewNewsState();
}

class _OverviewNewsState extends ConsumerState<OverviewNews>
    with WidgetsBindingObserver, OverviewWindowActive {
  @override
  void onWindowActive(bool active) {
    ref.read(newsFeedProvider.notifier).setActive(active: active);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final s = ref.watch(newsFeedProvider);
    final items = s.items;
    Widget? empty;
    if (items.isEmpty) {
      if (!s.loaded) {
        empty = const SizedBox.shrink();
      } else if (s.feeds.isEmpty) {
        empty = const _NoSources();
      } else {
        empty = _Quiet(
          testId: 'overview-news-empty',
          text: s.allFailed
              ? l10n.overviewNewsUnreachable
              : s.fetching || s.feeds.any((f) => s.records[f] == null)
              ? l10n.overviewNewsLoading
              : l10n.overviewNewsNoItems,
        );
      }
    }
    return OverviewRowsCard(
      key: const ValueKey('overview-news'),
      title: l10n.overviewNewsTitle,
      testId: 'overview-news',
      allLabel: l10n.overviewNewsSources,
      allKind: WpLinkKind.action,
      onAll: () => unawaited(showNewsSourcesDialog(context)),
      empty: empty,
      rows: [
        for (final (i, item) in items.indexed)
          _NewsRow(
            key: ValueKey('overview-news-item-$i'),
            index: i,
            item: item,
          ),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.testId, required this.text});

  final String testId;
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(key: ValueKey(testId), text, style: WpTextStyles.rowNote),
  );
}

/// No feed chosen yet: one sentence and the suggested source.
class _NoSources extends ConsumerWidget {
  const _NoSources();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Wrap(
      key: const ValueKey('overview-news-no-sources'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.sm,
      runSpacing: WpSpacing.xs,
      children: [
        Text(l10n.overviewNewsNoSources, style: WpTextStyles.rowTitle),
        WpTextLink(
          testID: 'overview-news-add-blog',
          label: l10n.overviewNewsAddBlog,
          onPressed: () => unawaited(
            ref.read(newsFeedProvider.notifier).addFeed(blogFeedUrl(lang)),
          ),
        ),
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({super.key, required this.index, required this.item});

  final int index;
  final NewsItem item;

  /// Today the time, else "yesterday" or a short date (year only when it
  /// differs), as in the notes rows.
  String _when(BuildContext context, L10n l10n) {
    final date = item.date;
    if (date == null) return '';
    final t = date.toLocal();
    final now = clock.now();
    final locale = Localizations.localeOf(context).toString();
    return switch (overviewDayOf(t, now)) {
      OverviewDay.today => formatHistoryTime(t),
      OverviewDay.yesterday => l10n.historyYesterday,
      OverviewDay.earlier =>
        (t.year == now.year
                ? DateFormat.MMMd(locale)
                : DateFormat.yMMMd(locale))
            .format(t),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    void open() => unawaited(openExternalUrl(context, item.link));
    return OverviewRow(
      time: _when(context, l10n),
      timeWidth: 64,
      leading: const ExcludeSemantics(
        child: WpAppCategoryTile(
          category: AppCategory.browser,
          size: WpIconSize.xl,
        ),
      ),
      text: item.title,
      subtitle: item.source,
      onOpen: open,
      actions: [
        WpIconButton.ghost(
          testId: 'overview-news-open-$index',
          icon: LucideIcons.externalLink,
          tooltip: l10n.overviewNewsOpen,
          semanticsLabel: l10n.overviewNewsOpenItem(item.title),
          onPressed: open,
        ),
      ],
    );
  }
}
