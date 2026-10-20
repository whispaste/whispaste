/// Guard: every id handed to the settings deep link (`settingsScrollTargetProvider`
/// or an `openSettings('…')` call) is a real row id in `kSettingsSearchTable`
/// or a registered legacy key. An unknown id resolves to no anchor, so the
/// link silently lands nowhere (the `text-smart-mode` regression, DEV-18).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';

// `\s*` and the optional comma also match line breaks, so a call wrapped by
// the formatter (`.notifier,` / `)` / `.set(` on separate lines) is found too.
final RegExp _scrollTargetSet = RegExp(
  r"settingsScrollTargetProvider\.notifier,?\s*\)\s*\.set\(\s*'([^']+)'",
);
final RegExp _openSettingsCall = RegExp(r"openSettings\(\s*'([^']+)'");

Set<String> _targetIdsIn(String source) {
  final ids = <String>{};
  for (final re in [_scrollTargetSet, _openSettingsCall]) {
    for (final m in re.allMatches(source)) {
      ids.add(m.group(1)!);
    }
  }
  return ids;
}

Set<String> _targetIdsInLib() {
  final ids = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    ids.addAll(_targetIdsIn(entity.readAsStringSync()));
  }
  return ids;
}

void main() {
  test('deep-link targets in lib/ are known row ids or legacy keys', () {
    final targets = _targetIdsInLib();
    expect(targets, isNotEmpty, reason: 'scan found no deep-link targets');

    final known = {
      ...kSettingsSearchTable.map((e) => e.rowId),
      ...kLegacySettingsDeepLinkRowIds.keys,
    };
    expect(
      targets.difference(known),
      isEmpty,
      reason:
          'deep-link ids with no row or legacy key (they resolve to nothing)',
    );
  });

  test('scanner finds a deep-link call wrapped over several lines', () {
    const wrapped = '''
      ref.read(
        settingsScrollTargetProvider.notifier,
      )
      .set(
        'text-smart-mode-preset',
      );
    ''';
    const inline =
        "ref.read(settingsScrollTargetProvider.notifier).set('stt-model');";
    expect(_targetIdsIn(wrapped), {'text-smart-mode-preset'});
    expect(_targetIdsIn(inline), {'stt-model'});
  });

  test('every legacy key points at a real row id', () {
    final rowIds = kSettingsSearchTable.map((e) => e.rowId).toSet();
    for (final entry in kLegacySettingsDeepLinkRowIds.entries) {
      expect(
        rowIds.contains(entry.value),
        isTrue,
        reason: '${entry.key} -> ${entry.value} is not a row id',
      );
    }
  });
}
