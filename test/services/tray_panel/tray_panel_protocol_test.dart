// Hand-over points of the tray panel (#920): phase mapping, selection and
// order of the entries taken from the tray command tree, action validation,
// snapshot round trip. No layout or rendering.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/tray_panel/tray_panel_protocol.dart';

const _sep = AppCommand.separator();

List<AppCommand> _tree({
  bool actionNeeded = false,
  bool onboarding = false,
  bool locked = false,
  int recentCount = 5,
  bool profiles = true,
  bool mic = true,
  bool sidePanel = true,
}) => [
  if (actionNeeded) ...[
    const AppCommand(id: 'download_model', labelKey: '⚠ Download the model'),
    _sep,
  ],
  const AppCommand(id: 'status', labelKey: '● Ready', enabled: false),
  _sep,
  if (onboarding) ...[
    const AppCommand(id: 'resume_onboarding', labelKey: 'trayResume'),
    _sep,
  ],
  const AppCommand(id: 'toggle_recording', labelKey: 'trayStartRecording'),
  const AppCommand(id: 'transcribe_file', labelKey: 'trayTranscribeFile'),
  const AppCommand(
    id: 'speech-model-submenu',
    labelKey: 'traySpeechModel',
    children: [AppCommand(id: 'stt:a', labelKey: 'A', checked: true)],
  ),
  const AppCommand(
    id: 'lang-submenu',
    labelKey: 'trayLanguage',
    children: [
      AppCommand(id: 'lang:auto', labelKey: 'auto', checked: false),
      AppCommand(id: 'lang:de', labelKey: 'Deutsch', checked: true),
      AppCommand(id: 'lang-more', labelKey: 'more'),
    ],
  ),
  const AppCommand(
    id: 'smart-mode-submenu',
    labelKey: 'navSmartMode',
    children: [
      AppCommand(id: 'smart:off', labelKey: 'Off', checked: true),
      AppCommand(id: 'smart:mail', labelKey: 'Mail', checked: false),
    ],
  ),
  const AppCommand(
    id: 'output-submenu',
    labelKey: 'trayOutput',
    children: [AppCommand(id: 'out:paste', labelKey: 'Paste', checked: true)],
  ),
  if (profiles)
    const AppCommand(
      id: 'profile-submenu',
      labelKey: 'trayProfile',
      children: [
        AppCommand(id: 'profile-auto', labelKey: 'Auto', checked: true),
        AppCommand(id: 'profile-none', labelKey: 'None', checked: false),
        _sep,
        AppCommand(id: 'profile:p1', labelKey: 'Work', checked: false),
      ],
    ),
  AppCommand(
    id: 'recent-submenu',
    labelKey: 'trayRecentRecordings',
    children: locked
        ? const [AppCommand(id: 'unlock_history', labelKey: 'unlock')]
        : [
            for (var i = 0; i < recentCount; i++)
              AppCommand(id: 'recent-$i', labelKey: 'Text $i'),
          ],
  ),
  if (mic)
    const AppCommand(
      id: 'mic-submenu',
      labelKey: 'trayMicrophone',
      children: [
        AppCommand(id: 'mic:default', labelKey: 'System', checked: true),
        _sep,
        AppCommand(id: 'mic:USB', labelKey: 'USB', checked: false),
      ],
    ),
  _sep,
  if (sidePanel) const AppCommand(id: 'side_panel', labelKey: 'traySide'),
  const AppCommand(id: 'show', labelKey: 'trayOpenApp'),
  const AppCommand(id: 'settings', labelKey: 'traySettings'),
  const AppCommand(id: 'feedback', labelKey: 'trayFeedback'),
  const AppCommand(id: 'coffee', labelKey: 'trayCoffee'),
  _sep,
  const AppCommand(id: 'quit', labelKey: 'trayQuit'),
];

TrayPanelContent _build(
  List<AppCommand> commands, {
  TrayPanelPhase phase = TrayPanelPhase.ready,
}) => buildTrayPanelContent(
  commands: commands,
  labels: const {'trayOpenApp': 'Open WhisPaste', 'trayLanguage': 'Language'},
  phase: phase,
  statusLabel: 'Ready',
  primaryLabel: 'Dictate',
  shortcut: 'Ctrl+Space',
);

void main() {
  test('every recording phase maps onto one of the three panel states', () {
    expect(
      trayPanelPhaseOf(RecordingPhase.recording),
      TrayPanelPhase.recording,
    );
    expect(
      trayPanelPhaseOf(RecordingPhase.transcribing),
      TrayPanelPhase.transcribing,
    );
    expect(
      trayPanelPhaseOf(RecordingPhase.refining),
      TrayPanelPhase.transcribing,
    );
    for (final p in [
      RecordingPhase.idle,
      RecordingPhase.done,
      RecordingPhase.error,
    ]) {
      expect(trayPanelPhaseOf(p), TrayPanelPhase.ready);
    }
  });

  test('the panel takes its entries and their order from the menu tree', () {
    final c = _build(_tree());
    expect(c.banner, isNull);
    expect(c.switches.map((s) => s.id), ['microphone', 'language', 'profile']);
    final language = c.switches[1];
    expect(language.label, 'Language');
    expect(language.value, 'Deutsch');
    expect(language.options.map((o) => o.id), [
      'lang:auto',
      'lang:de',
      'lang-more',
    ]);
    expect(language.options.last.checked, isNull);
    // Separators inside a submenu are dropped, the order is kept.
    expect(c.switches[2].options.map((o) => o.id), [
      'profile-auto',
      'profile-none',
      'profile:p1',
    ]);
    expect(c.recent.map((r) => r.id), ['recent-0', 'recent-1', 'recent-2']);
    expect(c.recentAll?.id, trayOpenHistoryId);
    expect(c.recentUnlock, isNull);
    expect(c.openApp.id, 'show');
    expect(c.openApp.label, 'Open WhisPaste');
    expect(c.settings.id, 'settings');
    // Speech model, output and the coffee link stay in the menu.
    expect(c.overflow.map((o) => o.id), [
      'transcribe_file',
      'side_panel',
      'feedback',
      'quit',
    ]);
    expect(c.commandIds, isNot(contains('coffee')));
    expect(c.commandIds, isNot(contains('stt:a')));
  });

  test('optional parts follow the menu: no profiles, one mic, no history', () {
    final c = _build(
      _tree(profiles: false, mic: false, recentCount: 0, sidePanel: false),
    );
    expect(c.switches.map((s) => s.id), ['language', 'smart-mode']);
    expect(c.switches.last.value, 'Off');
    expect(c.recent, isEmpty);
    expect(c.recentAll, isNull);
    expect(c.overflow.map((o) => o.id), [
      'transcribe_file',
      'feedback',
      'quit',
    ]);
  });

  test('locked history shows only the unlock entry', () {
    final c = _build(_tree(locked: true));
    expect(c.recent, isEmpty);
    expect(c.recentAll, isNull);
    expect(c.recentUnlock?.id, 'unlock_history');
  });

  test('the banner prefers the action-needed entry over resume setup', () {
    final both = _build(_tree(actionNeeded: true, onboarding: true));
    expect(both.banner?.id, 'download_model');
    expect(both.banner?.label, 'Download the model');
    final onboarding = _build(_tree(onboarding: true));
    expect(onboarding.banner?.id, 'resume_onboarding');
  });

  test('the microphone is locked while recording', () {
    final c = _build(_tree(), phase: TrayPanelPhase.recording);
    expect(c.switches.first.id, 'microphone');
    expect(c.switches.first.enabled, isFalse);
    expect(trayCommandForPanelAction('mic:USB', c), isNull);
    expect(trayCommandForPanelAction('lang:auto', c), 'lang:auto');
  });

  test('only ids on the panel and the primary button are accepted', () {
    final ready = _build(_tree());
    expect(
      trayCommandForPanelAction(TrayPanelAction.primary, ready),
      'toggle_recording',
    );
    expect(trayCommandForPanelAction('recent-2', ready), 'recent-2');
    expect(trayCommandForPanelAction('recent-3', ready), isNull);
    expect(trayCommandForPanelAction('quit', ready), 'quit');
    expect(trayCommandForPanelAction('coffee', ready), isNull);
    expect(trayCommandForPanelAction('nope', ready), isNull);
    final busy = _build(_tree(), phase: TrayPanelPhase.transcribing);
    expect(trayCommandForPanelAction(TrayPanelAction.primary, busy), isNull);
  });

  test('the snapshot survives the channel round trip', () {
    final content = _build(_tree(actionNeeded: true));
    final parsed = TrayPanelContent.tryParse(content.toMap())!;
    expect(parsed.toMap(), content.toMap());
    expect(TrayPanelContent.tryParse('garbage'), isNull);
    expect(TrayPanelPhase.parse('unknown'), TrayPanelPhase.ready);
  });
}
