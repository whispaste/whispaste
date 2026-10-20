/// Settings information architecture (WP-23b, `07-settings-ia.md` §2–4).
///
/// Eight areas in three groups. The navigation shows them, the page renders
/// the selected one, and deep links address a **row id** (kebab-case, e.g.
/// `general-hotkey-dictation`) that resolves to its area and section.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overline above a block of areas in the navigation.
enum SettingsGroup { app, dictation, system }

/// One settings area. [id] is stable and doubles as the ValueKey suffix.
enum SettingsArea {
  general(SettingsGroup.app),
  appearance(SettingsGroup.app),
  shortcuts(SettingsGroup.dictation),
  recording(SettingsGroup.dictation),
  speech(SettingsGroup.dictation),
  textInsert(SettingsGroup.dictation),
  privacy(SettingsGroup.system),
  advanced(SettingsGroup.system),
  about(SettingsGroup.system);

  const SettingsArea(this.group);

  final SettingsGroup group;

  String get id => name;
}

/// Areas of one group, in navigation order.
List<SettingsArea> settingsAreasIn(SettingsGroup group) => [
  for (final area in SettingsArea.values)
    if (area.group == group) area,
];

/// Currently selected area. Kept in memory for the life of the app, so
/// reopening Settings returns to the last area (spec §2 "Zustand").
class SettingsAreaNotifier extends Notifier<SettingsArea> {
  @override
  SettingsArea build() => SettingsArea.general;

  void select(SettingsArea area) => state = area;
}

final settingsAreaProvider =
    NotifierProvider<SettingsAreaNotifier, SettingsArea>(
      SettingsAreaNotifier.new,
    );

/// Section keys each area renders, top to bottom. The keys are the widget
/// anchors on the page (see `SettingsPage`), not the row ids above.
const Map<SettingsArea, List<String>> kSettingsAreaSections = {
  SettingsArea.general: ['interface', 'updates'],
  SettingsArea.shortcuts: ['hotkey'],
  SettingsArea.appearance: ['appearance', 'overlay', 'floatingButton'],
  SettingsArea.recording: ['audio', 'recordingSafety', 'sound'],
  SettingsArea.speech: ['stt'],
  SettingsArea.textInsert: [
    'afterTranscription',
    'textProcessing',
    'smartMode',
  ],
  SettingsArea.privacy: ['privacy', 'history', 'settingsPortability'],
  SettingsArea.advanced: ['betaChannel', 'advanced', 'automationApi'],
  SettingsArea.about: ['about'],
};
