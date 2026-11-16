/// The Markdown copy of a history entry uses the app language for its field
/// labels (UIA-HIS-20).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/history_page.dart';

HistoryEntry _entry() => HistoryEntry(
  id: 'e1',
  content: 'Hallo Welt',
  title: 'Notiz',
  timestamp: DateTime(2026, 10, 19, 14, 5),
  durationSec: 3,
  processingDurationSec: 1,
  language: 'de',
  languageHint: '',
  tags: '',
  pinned: false,
  source: 'mic',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0,
  archived: false,
  titleEdited: false,
  colorSlot: 0,
);

void main() {
  test('field labels follow the app language (UIA-HIS-20)', () async {
    final de = await L10n.delegate.load(const Locale('de'));

    final md = formatHistoryEntryAsMarkdown(_entry(), de);

    expect(md, contains('**${de.historyMdDate}:**'));
    expect(md, contains('**${de.historyMdModel}:**'));
    expect(md, isNot(contains('**Date:**')));
    expect(md, isNot(contains('**Model:**')));
  });
}
