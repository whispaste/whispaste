import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_urls.dart' show blogFeedUrl;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/news_feed.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/news_feed_service.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_text_field.dart';
import '../../widgets/wp_text_link.dart';

/// "Quellen" of the news block (#1568): the chosen feeds with a remove button,
/// a field for a new address, and the WhisPaste blog as a suggestion. Every
/// change is saved at once; "Fertig" only closes. The subtitle says what
/// leaves the computer: the request to each chosen address, as for any page
/// opened in a browser.
Future<void> showNewsSourcesDialog(BuildContext context) =>
    showWpFormDialog<void>(
      context: context,
      builder: (context, animation) => _NewsSourcesDialog(animation: animation),
    );

class _NewsSourcesDialog extends ConsumerStatefulWidget {
  const _NewsSourcesDialog({required this.animation});

  final Animation<double> animation;

  @override
  ConsumerState<_NewsSourcesDialog> createState() => _NewsSourcesDialogState();
}

class _NewsSourcesDialogState extends ConsumerState<_NewsSourcesDialog> {
  final _address = TextEditingController();
  NewsFeedUrlProblem? _problem;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _add(String input) async {
    final problem = await ref.read(newsFeedProvider.notifier).addFeed(input);
    if (!mounted) return;
    setState(() => _problem = problem);
    if (problem == null && input == _address.text) _address.clear();
  }

  String _problemText(L10n l10n, NewsFeedUrlProblem p) => switch (p) {
    NewsFeedUrlProblem.invalid => l10n.overviewNewsSourceInvalid,
    NewsFeedUrlProblem.duplicate => l10n.overviewNewsSourceDuplicate,
    NewsFeedUrlProblem.full => l10n.overviewNewsSourceFull(kNewsFeedMaxFeeds),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final s = ref.watch(newsFeedProvider);
    final blog = blogFeedUrl(lang);
    final full = s.feeds.length >= kNewsFeedMaxFeeds;
    final problem = _problem;

    String status(String url) {
      final r = s.records[url];
      if (r == null) return l10n.overviewNewsSourcePending;
      if (r.failed && r.items.isEmpty) return l10n.overviewNewsSourceFailed;
      return r.source ?? Uri.parse(url).host;
    }

    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.overviewNewsSourcesTitle,
      subtitle: l10n.overviewNewsSourcesSubtitle,
      fields: [
        if (s.feeds.isEmpty)
          Text(
            key: const ValueKey('overview-news-sources-none'),
            l10n.overviewNewsSourcesNone,
            style: WpTextStyles.rowNote,
          )
        else
          for (final (i, url) in s.feeds.indexed) ...[
            if (i > 0) const WpRowDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status(url),
                          style: WpTextStyles.rowTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Addresses read left to right in every language.
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            url,
                            style: WpTextStyles.rowNote,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  WpIconButton.ghost(
                    testId: 'overview-news-source-remove-$i',
                    icon: LucideIcons.trash2,
                    tooltip: l10n.overviewNewsSourceRemove,
                    semanticsLabel: l10n.overviewNewsSourceRemoveItem(url),
                    onPressed: () => unawaited(
                      ref.read(newsFeedProvider.notifier).removeFeed(url),
                    ),
                  ),
                ],
              ),
            ),
          ],
        const SizedBox(height: WpSpacing.lg),
        if (!full) ...[
          Row(
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Semantics(
                    identifier: 'overview-news-source-field',
                    child: WpTextField(
                      key: const ValueKey('overview-news-source-field'),
                      controller: _address,
                      variant: WpTextFieldVariant.form,
                      hintText: 'https://example.org/feed.xml',
                      semanticsLabel: l10n.overviewNewsSourceField,
                      autofocus: true,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      onChanged: (_) {
                        if (_problem != null) setState(() => _problem = null);
                      },
                      onSubmitted: (v) => unawaited(_add(v)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              WpButton(
                testId: 'overview-news-source-add',
                label: l10n.overviewNewsSourceAdd,
                variant: WpButtonVariant.secondary,
                onPressed: () => unawaited(_add(_address.text)),
              ),
            ],
          ),
          if (!s.feeds.contains(blog)) ...[
            const SizedBox(height: WpSpacing.sm),
            WpTextLink(
              testID: 'overview-news-sources-add-blog',
              label: l10n.overviewNewsAddBlog,
              onPressed: () => unawaited(_add(blog)),
            ),
          ],
        ] else
          Text(
            l10n.overviewNewsSourceFull(kNewsFeedMaxFeeds),
            style: WpTextStyles.rowNote,
          ),
        if (problem != null) ...[
          const SizedBox(height: WpSpacing.sm),
          Semantics(
            liveRegion: true,
            child: WpErrorNotice(
              key: const ValueKey('overview-news-source-error'),
              cause: _problemText(l10n, problem),
            ),
          ),
        ],
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.overviewNewsSourcesDone,
          testId: 'overview-news-sources-done',
          role: WpDialogActionRole.primary,
        ),
      ],
    );
  }
}
