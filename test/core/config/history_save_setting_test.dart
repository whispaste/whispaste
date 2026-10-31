/// The "Aufnahmen speichern" switch (history-off feature) lives in
/// [HistorySettings]: default on, portable, round-trips through the map.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  test('saving is on by default, so existing installs keep their history', () {
    expect(HistorySettings.defaults.saveHistory, isTrue);
  });

  test('the switch round-trips through its stored map', () {
    const off = HistorySettings(saveHistory: false);
    final restored = HistorySettings.fromMap(off.toMap());
    expect(restored.saveHistory, isFalse);
    expect(restored, off);
  });

  test('a missing stored value reads as on', () {
    expect(HistorySettings.fromMap(const {}).saveHistory, isTrue);
  });

  test('copyWith changes only the switch', () {
    final changed = HistorySettings.defaults.copyWith(saveHistory: false);
    expect(changed.saveHistory, isFalse);
    expect(
      changed.historyMaxEntries,
      HistorySettings.defaults.historyMaxEntries,
    );
  });
}
