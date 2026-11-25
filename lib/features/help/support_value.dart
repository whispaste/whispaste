/// The value line of the support page (#2202): what WhisPaste has already
/// done for this user, from figures the app keeps locally anyway (dictated
/// words, estimated typing time saved). Nothing new is collected or sent.
///
/// Research (`internal-notes` §3): showing the value
/// before the ask works better than the ask alone. The line appears only from
/// [kSupportValueMinWords] words on, so a new user never reads a tiny number.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/data/analytics_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/overview/overview_logic.dart';
import '../analytics/analytics_page.dart' show formatAnalyticsDuration;
import '../overview/overview_providers.dart';

final _log = AppLogger('SupportValue');

/// Fewer dictated words than this show no value line.
const int kSupportValueMinWords = 1000;

/// The all-time figures the value line names.
typedef SupportValue = ({int words, int savedMinutes});

/// The value line's figures, or null below [kSupportValueMinWords] words or
/// without any saved typing time. Pure, so the threshold is unit-testable.
SupportValue? supportValueFrom(AnalyticsData data) {
  if (data.totalWords < kSupportValueMinWords) return null;
  if (data.timeSavedMinutes <= 0) return null;
  return (words: data.totalWords, savedMinutes: data.timeSavedMinutes);
}

/// The localized value line, e.g. "So far you have dictated 12,345 words
/// with WhisPaste and saved about 4.1 h of typing."
String supportValueText(L10n l10n, String languageCode, SupportValue value) =>
    l10n.supportValueLine(
      NumberFormat.decimalPattern(languageCode).format(value.words),
      formatAnalyticsDuration(l10n, languageCode, value.savedMinutes),
    );

/// All-time figures for the value line. Any failure yields no line: the page
/// never shows zeros or an error for it.
final supportValueProvider = FutureProvider.autoDispose<SupportValue?>((
  ref,
) async {
  try {
    final data = await ref.watch(
      overviewFiguresProvider(OverviewPeriod.all).future,
    );
    return supportValueFrom(data);
  } on Object catch (e) {
    _log.debug('support value line skipped: $e');
    return null;
  }
});
