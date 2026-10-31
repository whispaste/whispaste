/// The engine dropdown names the recommended engine, and only that one
/// (UIA-RT-03: one "Empfohlen" answer, not one per axis).
library;

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart'
    show sttEngineDropdownLabels;

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  test('Parakeet carries the badge when Parakeet is recommended', () {
    final labels = sttEngineDropdownLabels(l10n, parakeetRecommended: true);

    expect(labels, [
      l10n.settingsSttEngineWhisper,
      '${l10n.settingsSttEngineParakeet} · ${l10n.settingsSttEngineRecommended}',
    ]);
  });

  test('no entry carries the badge when Whisper is recommended', () {
    final labels = sttEngineDropdownLabels(l10n, parakeetRecommended: false);

    expect(labels, [
      l10n.settingsSttEngineWhisper,
      l10n.settingsSttEngineParakeet,
    ]);
    expect(
      labels.where((l) => l.contains(l10n.settingsSttEngineRecommended)),
      isEmpty,
    );
  });
}
