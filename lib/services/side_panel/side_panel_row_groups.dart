/// Groups side-panel rows under day headers.
///
/// Pure: the caller passes the clock and labels in, so the grouping is
/// unit-testable without a widget tree. The result is the flat list the lazy
/// panel list renders: a header whenever the calendar day changes, then the
/// rows of that day in their incoming order.
library;

import 'package:intl/intl.dart';

import 'side_panel_snapshot.dart';

/// One item of the panel list: a day header or a row.
sealed class SidePanelListItem {
  const SidePanelListItem();
}

/// A day header such as "Today", "Yesterday" or a formatted date.
final class SidePanelDateHeader extends SidePanelListItem {
  const SidePanelDateHeader(this.label, this.day);

  final String label;

  /// The calendar day, local time, midnight. Used for the stable test id.
  final DateTime day;
}

/// A row. Rows without a [SidePanelRow.createdAt] appear without a header.
final class SidePanelRowItem extends SidePanelListItem {
  const SidePanelRowItem(this.row);

  final SidePanelRow row;
}

/// Flattens [rows] (newest first) into headers and rows.
///
/// [now] decides which day counts as today and yesterday. [todayLabel] and
/// [yesterdayLabel] are the localized words; any older day is formatted with
/// [locale], falling back to the default format if the locale has no date
/// data.
List<SidePanelListItem> groupSidePanelRows(
  List<SidePanelRow> rows, {
  required DateTime now,
  required String todayLabel,
  required String yesterdayLabel,
  required String locale,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final items = <SidePanelListItem>[];
  DateTime? currentDay;

  for (final row in rows) {
    final createdAt = row.createdAt;
    if (createdAt == null) {
      items.add(SidePanelRowItem(row));
      continue;
    }
    final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (day != currentDay) {
      currentDay = day;
      items.add(
        SidePanelDateHeader(
          _dayLabel(
            day,
            today: today,
            yesterday: yesterday,
            todayLabel: todayLabel,
            yesterdayLabel: yesterdayLabel,
            locale: locale,
          ),
          day,
        ),
      );
    }
    items.add(SidePanelRowItem(row));
  }
  return items;
}

String _dayLabel(
  DateTime day, {
  required DateTime today,
  required DateTime yesterday,
  required String todayLabel,
  required String yesterdayLabel,
  required String locale,
}) {
  if (day == today) return todayLabel;
  if (day == yesterday) return yesterdayLabel;
  try {
    return DateFormat.yMMMd(locale).format(day);
  } on Object {
    // intl throws ArgumentError for an unknown locale and Exception for
    // missing locale data; either way the default format still renders.
    return DateFormat.yMMMd().format(day);
  }
}
