import 'package:intl/intl.dart';

/// Localized deadline of a parked recording's audio, e.g. "26.10.26, 14:05".
///
/// Settings → Privacy and the history detail both use it, so the same record
/// shows the same text in both places.
String formatKeptUntil(String locale, DateTime expiresAt) =>
    DateFormat.yMd(locale).add_Hm().format(expiresAt.toLocal());
