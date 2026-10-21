/// The command tree of the tray menu (MZ-01).
///
/// Pure: the tray service passes the current state in as plain values, and the
/// result is the same tree the tray adapter renders. Menu bar and title-bar
/// menus will read the same builders.
library;

import 'package:flutter/foundation.dart' show immutable;

import '../../core/l10n/generated/app_localizations.dart';
import '../tray_mic_menu.dart';
import 'app_command.dart';

/// Ids of the tray's own entries. They are also the keys of the native tray
/// menu, so they stay as they were before the command model.
abstract final class TrayCommandIds {
  static const status = 'status';
  static const toggleRecording = 'toggle_recording';
  static const transcribeFile = 'transcribe_file';
  static const speechModel = 'speech-model-submenu';
  static const language = 'lang-submenu';
  static const smartMode = 'smart-mode-submenu';
  static const output = 'output-submenu';
  static const profile = 'profile-submenu';
  static const microphone = 'mic-submenu';
  static const sidePanel = 'side_panel';
  static const show = 'show';
  static const settings = 'settings';
  static const feedback = 'feedback';
  static const quit = 'quit';
  static const recentRecordings = 'recent-submenu';
  static const unlockHistory = 'unlock_history';

  /// The fixed ids, for guards that check the tree is complete.
  static const all = [
    recentRecordings,
    unlockHistory,
    status,
    toggleRecording,
    transcribeFile,
    speechModel,
    language,
    smartMode,
    output,
    profile,
    microphone,
    sidePanel,
    show,
    settings,
    feedback,
    quit,
  ];
}

/// Prefix of the ids of recent-recording items; the recording id follows it.
const trayRecentIdPrefix = 'recent-';

/// Most recent recordings the tray submenu lists.
const trayRecentLimit = 5;

/// Menu id of the recent recording [id].
String trayRecentKey(String id) => '$trayRecentIdPrefix$id';

/// The recording id behind a recent-item id, or null for any other id.
String? trayRecentIdFromKey(String key) => key.startsWith(trayRecentIdPrefix)
    ? key.substring(trayRecentIdPrefix.length)
    : null;

/// Longest text preview a recent-recording item shows, ellipsis included.
const trayRecentLabelMaxLength = 48;

/// Text preview of a recent recording: its first non-blank line, cut with an
/// ellipsis when it is longer than [trayRecentLabelMaxLength].
String trayRecentLabel(String content) {
  final line = content
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return '\u2026';
  if (line.length <= trayRecentLabelMaxLength) return line;
  return '${line.substring(0, trayRecentLabelMaxLength - 1)}\u2026';
}

/// Whether recent-recording items show their text (decision 2026-10-21):
/// always, unless a history PIN is set. With a PIN the items show only time
/// and word count, even while the history is unlocked.
bool trayTextPreviewEnabled({required String historyPin}) => historyPin.isEmpty;

/// Everything the tray menu shows, as plain values.
@immutable
class TrayMenuState {
  const TrayMenuState({
    required this.isRecording,
    required this.micDeviceLabels,
    required this.selectedMic,
    this.languageCommands,
    this.speechModelCommands,
    this.smartModeCommands = const [],
    this.outputCommands = const [],
    this.profileCommands = const [],
    this.actionNeeded,
    this.sidePanelAvailable = false,
    this.toggleShortcut,
    this.recentRecordings = const [],
    this.historyLocked = false,
  });

  /// Whether a recording is running (drives the toggle label and status).
  final bool isRecording;

  /// Enumerated devices including the system-default pseudo-device.
  final List<String> micDeviceLabels;

  /// The persisted microphone choice (or the default sentinel).
  final String selectedMic;

  /// The Language submenu, or null where the engine picks the language.
  final List<AppCommand>? languageCommands;

  /// The Sprachmodell submenu, or null where it is not offered.
  final List<AppCommand>? speechModelCommands;

  /// The Smart Mode submenu entries; the submenu is hidden when empty.
  final List<AppCommand> smartModeCommands;

  /// The after-transcription submenu entries; hidden when empty.
  final List<AppCommand> outputCommands;

  /// The Profil submenu entries (automatic, none, then the profiles); hidden
  /// when empty, that is when no profile exists.
  final List<AppCommand> profileCommands;

  /// The dictation hotkey as displayed text, shown next to the toggle entry.
  final String? toggleShortcut;

  /// A pending "action needed" entry: its id and its text.
  final ({String id, String label})? actionNeeded;

  /// Whether the side panel entry is shown.
  final bool sidePanelAvailable;

  /// Latest recordings, newest first: id and a label of date and word count.
  /// The label never carries the text. Empty while [historyLocked].
  final List<({String id, String label})> recentRecordings;

  /// A PIN is set and the history has not been unlocked. The submenu then
  /// offers only the unlock entry, so locked text never reaches the menu.
  final bool historyLocked;
}

/// Label table of the tray: the ARB keys the tree refers to, resolved in the
/// app's current language.
Map<String, String> trayLabelsFor(L10n l) => {
  'trayStartRecording': l.trayStartRecording,
  'trayStopRecording': l.trayStopRecording,
  'trayStatusRecording': l.trayStatusRecording,
  'trayStatusReady': l.trayStatusReady,
  'trayTranscribeFile': l.trayTranscribeFile,
  'trayMicrophone': l.trayMicrophone,
  'trayLanguage': l.trayLanguage,
  'trayLanguageMore': l.trayLanguageMore,
  'trayProfile': l.trayProfile,
  'trayProfileAutomatic': l.trayProfileAutomatic,
  'trayProfileNone': l.trayProfileNone,
  'trayRecentRecordings': l.trayRecentRecordings,
  'trayUnlockRecordings': l.trayUnlockRecordings,
  'traySpeechModel': l.traySpeechModel,
  'navSmartMode': l.navSmartMode,
  'settingsAfterTranscription': l.settingsAfterTranscription,
  'dockMenuSttLockedReason': l.dockMenuSttLockedReason,
  'smartModePresetOff': l.smartModePresetOff,
  'smartModePresetCleanup': l.smartModePresetCleanup,
  'smartModePresetConcise': l.smartModePresetConcise,
  'smartModePresetTranslate': l.smartModePresetTranslate,
  'settingsLanguageAutoDetect': l.settingsLanguageAutoDetect,
  'settingsMicSystemDefault': l.settingsMicSystemDefault,
  'trayOpenSidePanel': l.trayOpenSidePanel,
  'trayOpenApp': l.trayOpenApp,
  'traySettings': l.traySettings,
  'trayFeedback': l.trayFeedback,
  'trayQuit': l.trayQuit,
};

/// The tray command tree for [state]. [labels] comes from [trayLabelsFor].
///
/// Order and separators are fixed: an optional action-needed entry, the
/// status line, the recording and file entries, the microphone and language
/// submenus, then the window, settings and quit entries.
List<AppCommand> buildTrayCommands(
  TrayMenuState state,
  Map<String, String> labels,
) {
  final statusDot = state.isRecording ? '🔴' : '🟢';
  final statusKey = state.isRecording
      ? 'trayStatusRecording'
      : 'trayStatusReady';
  final statusText = labels[statusKey] ?? statusKey;
  final action = state.actionNeeded;
  // Mirror the settings dropdown: no submenu when only the default
  // pseudo-device was enumerated — there is nothing to switch to.
  final hasRealMicDevices = state.micDeviceLabels.length > 1;
  final languageCommands = state.languageCommands;
  final speechModelCommands = state.speechModelCommands;
  final smartModeCommands = state.smartModeCommands;
  final outputCommands = state.outputCommands;
  final profileCommands = state.profileCommands;

  return [
    if (action != null) ...[
      AppCommand(id: action.id, labelKey: '⚠ ${action.label}'),
      const AppCommand.separator(),
    ],
    AppCommand(
      id: TrayCommandIds.status,
      labelKey: '$statusDot $statusText',
      enabled: false,
    ),
    const AppCommand.separator(),
    AppCommand(
      id: TrayCommandIds.toggleRecording,
      labelKey: state.isRecording ? 'trayStopRecording' : 'trayStartRecording',
      shortcut: state.toggleShortcut,
    ),
    const AppCommand(
      id: TrayCommandIds.transcribeFile,
      labelKey: 'trayTranscribeFile',
    ),
    if (speechModelCommands != null)
      AppCommand(
        id: TrayCommandIds.speechModel,
        labelKey: 'traySpeechModel',
        children: speechModelCommands,
      ),
    if (languageCommands != null)
      AppCommand(
        id: TrayCommandIds.language,
        labelKey: 'trayLanguage',
        children: languageCommands,
      ),
    if (smartModeCommands.isNotEmpty)
      AppCommand(
        id: TrayCommandIds.smartMode,
        labelKey: 'navSmartMode',
        children: smartModeCommands,
      ),
    if (outputCommands.isNotEmpty)
      AppCommand(
        id: TrayCommandIds.output,
        labelKey: 'settingsAfterTranscription',
        children: outputCommands,
      ),
    if (profileCommands.isNotEmpty)
      AppCommand(
        id: TrayCommandIds.profile,
        labelKey: 'trayProfile',
        children: profileCommands,
      ),
    if (state.historyLocked)
      const AppCommand(
        id: TrayCommandIds.recentRecordings,
        labelKey: 'trayRecentRecordings',
        children: [
          AppCommand(
            id: TrayCommandIds.unlockHistory,
            labelKey: 'trayUnlockRecordings',
          ),
        ],
      )
    else if (state.recentRecordings.isNotEmpty)
      AppCommand(
        id: TrayCommandIds.recentRecordings,
        labelKey: 'trayRecentRecordings',
        children: [
          for (final r in state.recentRecordings)
            AppCommand(id: trayRecentKey(r.id), labelKey: r.label),
        ],
      ),
    if (hasRealMicDevices)
      AppCommand(
        id: TrayCommandIds.microphone,
        labelKey: 'trayMicrophone',
        children: buildMicrophoneCommands(
          deviceLabels: state.micDeviceLabels,
          selectedLabel: state.selectedMic,
          systemDefaultLabelKey: 'settingsMicSystemDefault',
        ),
      ),
    const AppCommand.separator(),
    if (state.sidePanelAvailable)
      const AppCommand(
        id: TrayCommandIds.sidePanel,
        labelKey: 'trayOpenSidePanel',
      ),
    const AppCommand(id: TrayCommandIds.show, labelKey: 'trayOpenApp'),
    const AppCommand(id: TrayCommandIds.settings, labelKey: 'traySettings'),
    const AppCommand(id: TrayCommandIds.feedback, labelKey: 'trayFeedback'),
    const AppCommand.separator(),
    const AppCommand(id: TrayCommandIds.quit, labelKey: 'trayQuit'),
  ];
}
