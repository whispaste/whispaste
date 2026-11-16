/// Guard: every jump into Settings lands on a real place (DEV-18, #1616).
///
/// Jump ids come from literals in lib/ (`settingsScrollTargetProvider…set`,
/// `openSettings`, `_openSettingsRow`, `openSetting`, `settings:<row>`
/// overview targets) and from the tables that compute them at runtime (the
/// recording error → row map, the API-key provider rows, the Smart Mode fix
/// rows, the overview tips, the not-shown fallbacks). Each one must resolve to
/// a row in `kSettingsSearchTable` (or a registered legacy key) whose area a
/// jump can reach. An unknown id would land nowhere; the page logs it, this
/// test keeps it from shipping. Help jumps that name a manual chapter must
/// name one that exists.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';
import 'package:whispaste/features/settings/sections/api_keys_section.dart';
import 'package:whispaste/services/smart_mode/smart_mode_text_model.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

// `\s*` and the optional comma also match line breaks, so a call wrapped by
// the formatter (`.notifier,` / `)` / `.set(` on separate lines) is found too.
final RegExp _scrollTargetSet = RegExp(
  r"settingsScrollTargetProvider\.notifier,?\s*\)\s*\.set\(\s*'([^']+)'",
);
final RegExp _openSettingsCall = RegExp(r"openSettings\(\s*'([^']+)'");
final RegExp _openSettingsRowCall = RegExp(
  r"_openSettingsRow\(\s*ref,\s*(?:\w+\s*\?\?\s*)?'([^']+)'",
);
final RegExp _openSettingCall = RegExp(r"openSetting\(\s*'([^']+)'");
final RegExp _overviewSettingsTarget = RegExp(r"'settings:([^']+)'");
final RegExp _chapterSlug = RegExp(r"chapterSlug:\s*'([^']+)'");

Set<String> _matchesIn(String source, Iterable<RegExp> patterns) => {
  for (final re in patterns)
    for (final m in re.allMatches(source)) m.group(1)!,
};

Set<String> _targetIdsIn(String source) => _matchesIn(source, [
  _scrollTargetSet,
  _openSettingsCall,
  _openSettingsRowCall,
  _openSettingCall,
  _overviewSettingsTarget,
]);

Iterable<String> _libSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/generated/')) continue;
    yield entity.readAsStringSync();
  }
}

/// Ids computed at runtime, so no literal scan sees them.
Set<String> _computedTargetIds() {
  final errorCodes = RegExp(r"'([a-z][a-z0-9_]+)'")
      .allMatches(
        File('lib/widgets/recording_behavior.dart').readAsStringSync(),
      )
      .map((m) => m.group(1)!)
      .toSet();
  return {
    for (final code in errorCodes)
      for (final provider in SttProviderType.values)
        ?settingsRowForRecordingError(code, provider),
    for (final p in ApiKeyProvider.values) p.rowId,
    for (final s in SmartModeTextModelStatus.values) ?smartModeFixRowId(s),
    for (final tip in OverviewTip.values)
      if (tip.target.startsWith('settings:'))
        tip.target.substring('settings:'.length),
    ...kSettingsRowFallbacks.keys,
    ...kSettingsRowFallbacks.values,
  };
}

void main() {
  final rowIds = kSettingsSearchTable.map((e) => e.rowId).toSet();
  final known = {...rowIds, ...kLegacySettingsDeepLinkRowIds.keys};

  test('jump targets in lib/ are known row ids or legacy keys', () {
    final targets = {for (final s in _libSources()) ..._targetIdsIn(s)};
    expect(targets, isNotEmpty, reason: 'scan found no deep-link targets');
    expect(
      targets.difference(known),
      isEmpty,
      reason: 'jump ids with no row or legacy key (they resolve to nothing)',
    );
  });

  test('computed jump targets are known row ids', () {
    final computed = _computedTargetIds();
    // The cloud key error must reach every provider's own key row.
    expect(
      computed,
      containsAll([
        'api-keys-openai',
        'api-keys-deepgram',
        'speech-custom-endpoint-key',
      ]),
    );
    expect(computed.difference(rowIds), isEmpty);
  });

  test('every jump target has a place a jump can open', () {
    final targets = {
      for (final s in _libSources()) ..._targetIdsIn(s),
      ..._computedTargetIds(),
    };
    for (final target in targets) {
      final entry = settingsRowAnchorFor(target);
      expect(entry, isNotNull, reason: target);
      // A settings area, or a page of its own the jump hands over to.
      final reachable =
          entry!.hostArea != null ||
          entry.area == SettingsRowArea.smartMode ||
          entry.area == SettingsRowArea.help;
      expect(reachable, isTrue, reason: '$target has no page to open');
    }
  });

  test('an unknown id resolves to nothing, never to a fallback row', () {
    expect(settingsRowAnchorFor('no-such-row'), isNull);
    expect(settingsRowShownFor('no-such-row', (_) => false), isNull);
  });

  test('fallback chains end on a row and do not loop', () {
    for (final start in kSettingsRowFallbacks.keys) {
      final seen = <String>{};
      String? id = start;
      while (id != null) {
        expect(seen.add(id), isTrue, reason: 'loop from $start at $id');
        id = kSettingsRowFallbacks[id];
      }
      // The last row of a chain shows in every configuration of its area.
      expect(seen.last, 'speech-provider', reason: start);
    }
  });

  test('a row not shown lands on the next row along its chain', () {
    final shown = {'speech-provider', 'stt-model'};
    expect(settingsRowShownFor('speech-gpu', shown.contains), 'stt-model');
    expect(settingsRowShownFor('speech-language', shown.contains), 'stt-model');
    expect(
      settingsRowShownFor('speech-custom-endpoint-key', shown.contains),
      'speech-provider',
    );
    expect(settingsRowShownFor('stt-model', shown.contains), 'stt-model');
  });

  test('manual chapters named by help jumps exist', () {
    final slugs = manualChapters.map((c) => c.slug).toSet();
    final named = {
      for (final s in _libSources()) ..._matchesIn(s, [_chapterSlug]),
    };
    expect(named.difference(slugs), isEmpty);
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
    expect(
      _targetIdsIn("_openSettingsRow(ref, fixRow ?? 'text-smart-mode-preset')"),
      {'text-smart-mode-preset'},
    );
    expect(
      _targetIdsIn("overviewOpenTarget(ref, 'settings:privacy-history-save')"),
      {'privacy-history-save'},
    );
  });

  test('every legacy key points at a real row id', () {
    for (final entry in kLegacySettingsDeepLinkRowIds.entries) {
      expect(
        rowIds.contains(entry.value),
        isTrue,
        reason: '${entry.key} -> ${entry.value} is not a row id',
      );
    }
  });
}
