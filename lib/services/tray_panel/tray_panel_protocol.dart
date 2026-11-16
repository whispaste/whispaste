/// Wire contract of the tray / menu bar panel (#920).
///
/// The panel is a render-only surface: the main engine owns recording,
/// hotkeys and paste, and sends a [TrayPanelContent] snapshot (labels already
/// localized) to the panel engine. The snapshot is derived from the same
/// command tree as the native tray menu ([buildTrayPanelContent]), and the
/// panel answers with the id of the command the user picked, so every surface
/// does the same thing and nothing can drift between menu and panel.
library;

import '../../core/recording/recording_state.dart';
import '../app_commands/app_command.dart';
import '../app_commands/tray_command_catalog.dart';

/// What the panel header and the primary button show.
enum TrayPanelPhase {
  ready,
  recording,
  transcribing;

  static TrayPanelPhase parse(Object? raw) => TrayPanelPhase.values.firstWhere(
    (p) => p.name == raw,
    orElse: () => TrayPanelPhase.ready,
  );
}

/// Maps the recording phase onto the panel's three states. Refining counts as
/// transcribing: the primary button is inert in both.
TrayPanelPhase trayPanelPhaseOf(RecordingPhase phase) => switch (phase) {
  RecordingPhase.recording => TrayPanelPhase.recording,
  RecordingPhase.transcribing ||
  RecordingPhase.refining => TrayPanelPhase.transcribing,
  RecordingPhase.idle ||
  RecordingPhase.done ||
  RecordingPhase.error => TrayPanelPhase.ready,
};

/// Action ids the panel engine reports besides plain command ids.
abstract final class TrayPanelAction {
  /// The Dictate / Stop button.
  static const primary = 'primary';
}

/// Command id of "All recordings": opens the window on the history page. The
/// native menu has no such entry; it lives in the panel only.
const trayOpenHistoryId = 'open_history';

/// Label key of [trayOpenHistoryId] and of the overflow button.
const trayAllRecordingsLabelKey = 'trayAllRecordings';
const trayPanelMoreLabelKey = 'trayPanelMore';

/// How many recent recordings the panel lists (the menu lists more).
const trayPanelRecentLimit = 3;

/// Stable ids of the quick switches; the testID is `tray-panel-switch-<id>`.
abstract final class TrayPanelSwitchIds {
  static const microphone = 'microphone';
  static const language = 'language';
  static const profile = 'profile';
  static const smartMode = 'smart-mode';
}

/// One pressable row: a command id and its final text.
class TrayPanelEntry {
  const TrayPanelEntry({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, Object> toMap() => {'id': id, 'label': label};

  static TrayPanelEntry? tryParse(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return TrayPanelEntry(
      id: raw['id'] as String,
      label: raw['label'] is String ? raw['label'] as String : '',
    );
  }
}

/// One choice of a switch picker. [checked] is null for a plain entry such as
/// "More languages…", which opens the window instead of switching.
class TrayPanelOption {
  const TrayPanelOption({required this.id, required this.label, this.checked});

  final String id;
  final String label;
  final bool? checked;

  Map<String, Object> toMap() => {
    'id': id,
    'label': label,
    'checked': ?checked,
  };

  static TrayPanelOption? tryParse(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return TrayPanelOption(
      id: raw['id'] as String,
      label: raw['label'] is String ? raw['label'] as String : '',
      checked: raw['checked'] is bool ? raw['checked'] as bool : null,
    );
  }
}

/// A quick switch: its name, the current choice and the picker options.
class TrayPanelSwitch {
  const TrayPanelSwitch({
    required this.id,
    required this.label,
    required this.value,
    required this.enabled,
    required this.options,
  });

  final String id;
  final String label;

  /// Text of the checked option ('' when none is checked).
  final String value;

  /// False while the choice is locked (the microphone during a dictation).
  final bool enabled;
  final List<TrayPanelOption> options;

  Map<String, Object> toMap() => {
    'id': id,
    'label': label,
    'value': value,
    'enabled': enabled,
    'options': [for (final o in options) o.toMap()],
  };

  static TrayPanelSwitch? tryParse(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final options = raw['options'];
    return TrayPanelSwitch(
      id: raw['id'] as String,
      label: raw['label'] is String ? raw['label'] as String : '',
      value: raw['value'] is String ? raw['value'] as String : '',
      enabled: raw['enabled'] != false,
      options: [
        if (options is List)
          for (final o in options) ?TrayPanelOption.tryParse(o),
      ],
    );
  }
}

/// Snapshot the panel paints. All strings are localized by the main engine so
/// the panel engine needs no language logic of its own.
class TrayPanelContent {
  const TrayPanelContent({
    required this.phase,
    required this.statusLabel,
    required this.primaryLabel,
    required this.shortcut,
    this.banner,
    this.switches = const [],
    this.recentLabel = '',
    this.recent = const [],
    this.recentAll,
    this.recentUnlock,
    required this.openApp,
    required this.settings,
    this.overflowLabel = '',
    this.overflow = const [],
  });

  final TrayPanelPhase phase;
  final String statusLabel;
  final String primaryLabel;

  /// Hotkey text shown as a keycap next to the primary button ('' = none).
  final String shortcut;

  /// Something that needs the user first: a missing model, a permission, or a
  /// paused setup. Shown above everything else.
  final TrayPanelEntry? banner;
  final List<TrayPanelSwitch> switches;
  final String recentLabel;
  final List<TrayPanelEntry> recent;
  final TrayPanelEntry? recentAll;
  final TrayPanelEntry? recentUnlock;
  final TrayPanelEntry openApp;
  final TrayPanelEntry settings;
  final String overflowLabel;

  /// Rarely used entries behind the "…" button; quit is always the last one.
  final List<TrayPanelEntry> overflow;

  /// Every command id the panel can report besides [TrayPanelAction.primary].
  Set<String> get commandIds => {
    ?banner?.id,
    for (final s in switches)
      if (s.enabled)
        for (final o in s.options) o.id,
    for (final r in recent) r.id,
    ?recentAll?.id,
    ?recentUnlock?.id,
    openApp.id,
    settings.id,
    for (final o in overflow) o.id,
  };

  Map<String, Object> toMap() => {
    'phase': phase.name,
    'statusLabel': statusLabel,
    'primaryLabel': primaryLabel,
    'shortcut': shortcut,
    if (banner != null) 'banner': banner!.toMap(),
    'switches': [for (final s in switches) s.toMap()],
    'recentLabel': recentLabel,
    'recent': [for (final r in recent) r.toMap()],
    if (recentAll != null) 'recentAll': recentAll!.toMap(),
    if (recentUnlock != null) 'recentUnlock': recentUnlock!.toMap(),
    'openApp': openApp.toMap(),
    'settings': settings.toMap(),
    'overflowLabel': overflowLabel,
    'overflow': [for (final o in overflow) o.toMap()],
  };

  static TrayPanelContent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final openApp = TrayPanelEntry.tryParse(raw['openApp']);
    final settings = TrayPanelEntry.tryParse(raw['settings']);
    if (openApp == null || settings == null) return null;
    String text(String key) => raw[key] is String ? raw[key] as String : '';
    List<T> list<T>(String key, T? Function(Object?) parse) => [
      if (raw[key] is List)
        for (final e in raw[key] as List) ?parse(e),
    ];
    return TrayPanelContent(
      phase: TrayPanelPhase.parse(raw['phase']),
      statusLabel: text('statusLabel'),
      primaryLabel: text('primaryLabel'),
      shortcut: text('shortcut'),
      banner: TrayPanelEntry.tryParse(raw['banner']),
      switches: list('switches', TrayPanelSwitch.tryParse),
      recentLabel: text('recentLabel'),
      recent: list('recent', TrayPanelEntry.tryParse),
      recentAll: TrayPanelEntry.tryParse(raw['recentAll']),
      recentUnlock: TrayPanelEntry.tryParse(raw['recentUnlock']),
      openApp: openApp,
      settings: settings,
      overflowLabel: text('overflowLabel'),
      overflow: list('overflow', TrayPanelEntry.tryParse),
    );
  }
}

/// The tray command id behind a panel [action], or null when it does nothing:
/// the primary button while transcribing, and any id that is not on the
/// panel the user saw ([content]), so a stale or forged id never runs.
String? trayCommandForPanelAction(String action, TrayPanelContent content) {
  if (action == TrayPanelAction.primary) {
    return content.phase == TrayPanelPhase.transcribing
        ? null
        : TrayCommandIds.toggleRecording;
  }
  return content.commandIds.contains(action) ? action : null;
}

/// Derives the panel from the native tray command tree [commands] (see
/// `buildTrayCommands`), so menu and panel always offer the same choices.
///
/// Selection and order:
/// - banner: the action-needed entry, else "Resume setup";
/// - switches: microphone (only with more than one device, locked while
///   [phase] is recording), language, then profile when profiles exist,
///   otherwise Smart Mode;
/// - recent: the first [trayPanelRecentLimit] recordings plus "All
///   recordings", or only the unlock entry while the history is locked;
/// - footer: open app and settings; overflow: transcribe file, side panel,
///   feedback, quit. Speech model, output and the coffee link stay in the
///   menu (right click).
TrayPanelContent buildTrayPanelContent({
  required List<AppCommand> commands,
  required Map<String, String> labels,
  required TrayPanelPhase phase,
  required String statusLabel,
  required String primaryLabel,
  required String shortcut,
}) {
  String label(String key) => labels[key] ?? key;
  AppCommand? byId(String id) {
    for (final c in commands) {
      if (c.id == id) return c;
    }
    return null;
  }

  TrayPanelEntry? entry(String id) {
    final c = byId(id);
    return c == null
        ? null
        : TrayPanelEntry(id: c.id, label: label(c.labelKey));
  }

  // The action-needed entry is the only one ahead of the status line.
  final first = commands.isEmpty ? null : commands.first;
  final actionNeeded =
      first != null &&
          !first.isSeparator &&
          first.id != TrayCommandIds.status &&
          byId(TrayCommandIds.status) != null
      ? TrayPanelEntry(
          id: first.id,
          label: first.labelKey.replaceFirst(RegExp(r'^⚠\s*'), ''),
        )
      : null;

  TrayPanelSwitch? switchOf(
    String switchId,
    String commandId, {
    bool enabled = true,
  }) {
    final c = byId(commandId);
    if (c == null || !c.isSubmenu) return null;
    final options = [
      for (final o in c.children)
        if (!o.isSeparator && o.enabled && !o.isSubmenu)
          TrayPanelOption(
            id: o.id,
            label: label(o.labelKey),
            checked: o.checked,
          ),
    ];
    if (options.isEmpty) return null;
    final checked = options.where((o) => o.checked ?? false);
    return TrayPanelSwitch(
      id: switchId,
      label: label(c.labelKey),
      value: checked.isEmpty ? '' : checked.first.label,
      enabled: enabled,
      options: options,
    );
  }

  final recentNode = byId(TrayCommandIds.recentRecordings);
  final recentChildren = recentNode?.children ?? const <AppCommand>[];
  final locked = recentChildren.any(
    (c) => c.id == TrayCommandIds.unlockHistory,
  );
  final recent = locked
      ? const <TrayPanelEntry>[]
      : [
          for (final c in recentChildren.take(trayPanelRecentLimit))
            TrayPanelEntry(id: c.id, label: label(c.labelKey)),
        ];

  return TrayPanelContent(
    phase: phase,
    statusLabel: statusLabel,
    primaryLabel: primaryLabel,
    shortcut: shortcut,
    banner: actionNeeded ?? entry(TrayCommandIds.resumeOnboarding),
    switches: [
      ?switchOf(
        TrayPanelSwitchIds.microphone,
        TrayCommandIds.microphone,
        enabled: phase != TrayPanelPhase.recording,
      ),
      ?switchOf(TrayPanelSwitchIds.language, TrayCommandIds.language),
      ?(switchOf(TrayPanelSwitchIds.profile, TrayCommandIds.profile) ??
          switchOf(TrayPanelSwitchIds.smartMode, TrayCommandIds.smartMode)),
    ],
    recentLabel: label('trayRecentRecordings'),
    recent: recent,
    recentAll: recent.isEmpty
        ? null
        : TrayPanelEntry(
            id: trayOpenHistoryId,
            label: label(trayAllRecordingsLabelKey),
          ),
    recentUnlock: locked
        ? TrayPanelEntry(
            id: TrayCommandIds.unlockHistory,
            label: label('trayUnlockRecordings'),
          )
        : null,
    openApp:
        entry(TrayCommandIds.show) ??
        TrayPanelEntry(id: TrayCommandIds.show, label: label('trayOpenApp')),
    settings:
        entry(TrayCommandIds.settings) ??
        TrayPanelEntry(
          id: TrayCommandIds.settings,
          label: label('traySettings'),
        ),
    overflowLabel: label(trayPanelMoreLabelKey),
    overflow: [
      ?entry(TrayCommandIds.transcribeFile),
      ?entry(TrayCommandIds.sidePanel),
      ?entry(TrayCommandIds.feedback),
      ?entry(TrayCommandIds.quit),
    ],
  );
}
