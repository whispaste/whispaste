/// Where the Help page should open: a tab, and optionally a handbook chapter.
///
/// Set before navigating to the Help page; the page consumes it on mount (or
/// as it changes while open) and clears it, so a later manual visit starts on
/// the handbook again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tabs of the Help page, in tab order.
enum HelpTab { manual, intro, support, diagnostics }

/// A deep link into the Help page.
class HelpTarget {
  const HelpTarget({required this.tab, this.chapterSlug, this.query});

  final HelpTab tab;

  /// Handbook chapter to show when [tab] is [HelpTab.manual]; null keeps the
  /// first chapter. Matches `ManualChapter.slug`.
  final String? chapterSlug;

  /// Text to put into the handbook search when [tab] is [HelpTab.manual],
  /// e.g. a Settings search without a match (UIA-SET-11); null leaves it empty.
  final String? query;

  @override
  bool operator ==(Object other) =>
      other is HelpTarget &&
      other.tab == tab &&
      other.chapterSlug == chapterSlug &&
      other.query == query;

  @override
  int get hashCode => Object.hash(tab, chapterSlug, query);
}

class HelpTargetNotifier extends Notifier<HelpTarget?> {
  @override
  HelpTarget? build() => null;

  void set(HelpTarget? target) => state = target;
}

final helpTargetProvider = NotifierProvider<HelpTargetNotifier, HelpTarget?>(
  HelpTargetNotifier.new,
);
