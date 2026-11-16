/// System variables for snippet bodies and replacements (#663).
///
/// Syntax: `{$name}` or `{$name:format}`. The field placeholders of
/// interactive snippets are `{{name}}` (see `interactive_snippet_composer`),
/// so the two syntaxes can never match the same text.
///
/// Variables: `date`, `time` (optional ICU pattern, e.g. `{$date:yyyy-MM-dd}`;
/// default is the system locale's short form), `clipboard`, `title`, and
/// `cursor` (a mark: removed from the text, its position is reported).
/// An unknown name or an unusable format stays in the text verbatim.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart' show Clipboard;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Names a snippet may use.
const List<String> systemVariableNames = [
  'date',
  'time',
  'clipboard',
  'title',
  'cursor',
];

final RegExp _variablePattern = RegExp(r'\{\$([A-Za-z]+)(?::([^{}]*))?\}');

/// Outcome of [resolveSystemVariables].
class SystemVariablesResult {
  const SystemVariablesResult(this.text, {this.cursorFromEnd});

  /// The text with every known variable replaced.
  final String text;

  /// Characters between the `{$cursor}` mark and the end of [text], or null
  /// when the text has no mark. The first mark wins; later ones are removed.
  final int? cursorFromEnd;
}

/// Replaces the known variables in [template] in one pass: a value that
/// itself contains `{$...}` (e.g. from the clipboard) is never expanded again.
///
/// [now] and [locale] make the result deterministic; [clipboard] is the
/// plain-text clipboard (empty when empty or not text).
SystemVariablesResult resolveSystemVariables(
  String template, {
  required DateTime now,
  required String locale,
  String clipboard = '',
  String title = '',
}) {
  if (!template.contains(r'{$')) return SystemVariablesResult(template);
  final out = StringBuffer();
  var last = 0;
  int? cursorOffset;
  for (final m in _variablePattern.allMatches(template)) {
    final name = m.group(1)!;
    final format = m.group(2);
    String? value;
    switch (name) {
      case 'date':
        value = _formatDate(now, locale, format, time: false);
      case 'time':
        value = _formatDate(now, locale, format, time: true);
      case 'clipboard':
        value = clipboard;
      case 'title':
        value = title;
      case 'cursor':
        value = '';
        cursorOffset ??= out.length + (m.start - last);
    }
    if (value == null) continue; // unknown: stays visible
    out
      ..write(template.substring(last, m.start))
      ..write(value);
    last = m.end;
  }
  out.write(template.substring(last));
  final text = out.toString();
  return SystemVariablesResult(
    text,
    cursorFromEnd: cursorOffset == null ? null : text.length - cursorOffset,
  );
}

/// Variables in [text] the resolver would leave untouched (unknown name or
/// invalid date format), in order of appearance, without duplicates. The
/// editor warns about them on save.
List<String> unknownSystemVariables(String text) {
  final seen = <String>{};
  for (final m in _variablePattern.allMatches(text)) {
    final name = m.group(1)!;
    final format = m.group(2);
    final known = systemVariableNames.contains(name);
    final badFormat =
        (name == 'date' || name == 'time') &&
        format != null &&
        _formatDate(DateTime(2000), 'en', format, time: name == 'time') == null;
    if (!known || badFormat) seen.add(m.group(0)!);
  }
  return seen.toList();
}

String? _formatDate(
  DateTime now,
  String locale,
  String? format, {
  required bool time,
}) {
  try {
    return _format(now, Intl.canonicalizedLocale(locale), format, time);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  } on Exception {
    // Symbols for this locale are not loaded (sync callers): the built-in
    // English data keeps the output usable instead of leaving the variable.
    try {
      return _format(now, 'en_US', format, time);
    } on FormatException {
      return null;
    }
  }
}

String _format(DateTime now, String loc, String? format, bool time) {
  if (format == null || format.isEmpty) {
    return (time ? DateFormat.jm(loc) : DateFormat.yMd(loc)).format(now);
  }
  return DateFormat(format, loc).format(now);
}

/// Loads the date symbols once so [resolveSystemVariables] works for every
/// app language. Call before the first resolution.
Future<void> ensureSystemVariableLocales() => initializeDateFormatting();

/// Resolves [template] against the live system: current time, the system
/// locale and the local plain-text clipboard (read only when the template
/// uses it, never sent anywhere; empty or non-text clipboard gives '').
Future<SystemVariablesResult> resolveSystemVariablesLive(
  String template, {
  String title = '',
}) async {
  if (!template.contains(r'{$')) return SystemVariablesResult(template);
  var clipboard = '';
  if (template.contains(r'{$clipboard')) {
    try {
      clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } on Object {
      clipboard = '';
    }
  }
  await ensureSystemVariableLocales();
  return resolveSystemVariables(
    template,
    now: DateTime.now(),
    locale: Platform.localeName,
    clipboard: clipboard,
    title: title,
  );
}
