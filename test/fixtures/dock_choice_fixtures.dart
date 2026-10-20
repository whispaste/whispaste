import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/recording_dock.dart';

/// A Smart Mode dropdown showing [label], with two presets and a footer.
WpDockChoiceSet dockTestSmartMode({
  required String label,
  String current = 'off',
  ValueChanged<String>? onChanged,
  String? note,
}) => WpDockChoiceSet(
  id: 'smart-mode',
  note: note,
  menuId: 'smart-mode',
  overline: 'Smart Mode',
  icon: LucideIcons.sparkles,
  choices: const [
    WpDockChoice(value: 'off', label: 'Aus'),
    WpDockChoice(value: 'cleanup', label: 'Bereinigen'),
  ],
  current: current,
  currentLabel: label,
  onChanged: onChanged ?? (_) {},
  searchHint: 'Search…',
  noMatchesLabel: 'No matches',
  footerLabel: 'Smart-Mode-Einstellungen…',
  onFooterTap: () {},
);

/// A language dropdown showing [label], with auto-detect and two languages.
WpDockChoiceSet dockTestLanguage({
  required String label,
  String current = 'de',
  ValueChanged<String>? onChanged,
}) => WpDockChoiceSet(
  id: 'language',
  menuId: 'language',
  overline: 'Language',
  icon: LucideIcons.languages,
  choices: const [
    WpDockChoice(value: 'auto', label: 'Auto-detect'),
    WpDockChoice(value: 'de', label: 'Deutsch'),
    WpDockChoice(value: 'en', label: 'English'),
  ],
  current: current,
  currentLabel: label,
  onChanged: onChanged ?? (_) {},
  searchHint: 'Search…',
  noMatchesLabel: 'No matches',
);

/// The speech-recognition dropdown: two on-device engines and a cloud group.
WpDockChoiceSet dockTestEngine({
  String label = 'Whisper · small',
  String current = 'whisper',
  ValueChanged<String>? onChanged,
  bool lockedWhileBusy = false,
  String? lockedReason,
}) => WpDockChoiceSet(
  id: 'engine',
  lockedReason: lockedReason,
  menuId: 'stt',
  overline: 'Speech recognition',
  icon: LucideIcons.audioLines,
  choices: const [
    WpDockChoice(value: 'whisper', label: 'Whisper', group: 'On device'),
    WpDockChoice(value: 'parakeet', label: 'Parakeet', group: 'On device'),
    WpDockChoice(value: 'openAI', label: 'OpenAI', group: 'Cloud'),
  ],
  current: current,
  currentLabel: label,
  onChanged: onChanged ?? (_) {},
  searchHint: 'Search…',
  noMatchesLabel: 'No matches',
  footerLabel: 'Manage models…',
  onFooterTap: () {},
  lockedWhileBusy: lockedWhileBusy,
);
