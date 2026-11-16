/// Immutable section classes that partition [AppSettings] into 16 coherent groups.
///
/// Each section is self-contained: it knows its own defaults, how to read from
/// and write to the shared flat storage map (`Map<String,String>`), and how to
/// copy-with-changes.  Storage keys are identical to the old flat schema so no
/// data migration is required.
///
/// Usage:
/// ```dart
/// // Deep mutation via sections
/// final updated = settings.copyWithSections(
///   stt: settings.stt.copyWith(model: 'whisper-large-v3-turbo'),
/// );
/// ```
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, listEquals;
import 'package:flutter/widgets.dart' show StringCharacters;

import 'automation_hooks.dart';
import 'language_favorites.dart' as fav;
import 'quality_tier.dart' show QualityTier;
import 'settings_enums.dart';

// ---------------------------------------------------------------------------
// Private helpers (mirrored from settings_provider to keep the file self-contained)
// ---------------------------------------------------------------------------

bool _readBool(Map<String, String> v, String key, bool fallback) {
  final s = v[key];
  if (s == null) return fallback;
  return s == 'true';
}

double _readDouble(Map<String, String> v, String key, double fallback) =>
    double.tryParse(v[key] ?? '') ?? fallback;

int _readInt(Map<String, String> v, String key, int fallback) =>
    int.tryParse(v[key] ?? '') ?? fallback;

bool _sameStrings(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

/// JSON-array string list. Anything that is not a list of strings (missing
/// key, corrupt value) reads as the empty list.
List<String> _readStringList(Map<String, String> v, String key) {
  final raw = v[key];
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is String) item,
    ];
  } on FormatException {
    return const [];
  }
}

/// Like [_readInt] for an absent "unset" field; a port outside 1024..65535
/// is dropped on load (ticket A-N9, C-N-3).
int? _readNullableInt(Map<String, String> v, String key) =>
    _portInRange(int.tryParse(v[key] ?? ''));

/// Sentinel for `copyWith` parameters that must distinguish "not passed"
/// from "explicitly set to null" — see [AutomationApiSettings.copyWith].
const _unset = Object();

Map<QualityTier, double>? _readBenchmarkRtf(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final result = <QualityTier, double>{};
    for (final entry in json.entries) {
      final tier = QualityTier.values.firstWhere(
        (t) => t.name == entry.key,
        orElse: () => throw FormatException('Unknown tier: ${entry.key}'),
      );
      result[tier] = (entry.value as num).toDouble();
    }
    return result;
  } catch (_) {
    return null;
  }
}

String _writeBenchmarkRtf(Map<QualityTier, double>? rtfMap) {
  if (rtfMap == null || rtfMap.isEmpty) return '';
  final json = <String, double>{};
  for (final entry in rtfMap.entries) {
    json[entry.key.name] = entry.value;
  }
  return jsonEncode(json);
}

DateTime? _readDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Migrates legacy model identifiers to the current downloadable set
/// (`whisper-small`, `whisper-medium`, `whisper-large-v3-turbo`).
///
/// Covers both old display-name values (`'Fast (Tiny)'` etc.) and removed
/// model IDs (`whisper-tiny`, `whisper-base`, `whisper-large-v3`). Each
/// legacy value maps to the tier representative — see [sttModels].
String _migrateModelId(String raw) => switch (raw) {
  'Fast (Tiny)' || 'whisper-tiny' || 'whisper-base' => 'whisper-small',
  'Balanced (Small)' => 'whisper-small',
  'High Quality (Medium)' => 'whisper-medium',
  'Best Quality (Large)' || 'whisper-large-v3' => 'whisper-large-v3-turbo',
  _ => raw,
};

// ===========================================================================
// Section 1 — Interface
// ===========================================================================

class InterfaceSettings {
  const InterfaceSettings({
    this.locale = 'en',
    this.launchAtStartup = false,
    this.startMinimized = false,
    this.showNotifications = true,
    this.notifyPasteProblems = true,
    this.notifySmartModeFallback = true,
    this.notifyMicrophoneProblems = true,
    this.showBackendUtilization = true,
    this.sidePanelEnabled = false,
    this.sidePanelEdge = SidePanelEdge.left,
    this.clipboardExcludedApps,
    this.appearance = AppearanceMode.navy,
  });

  final String locale;
  final bool launchAtStartup;
  final bool startMinimized;
  final bool showNotifications;

  /// Category switch under [showNotifications]: native notifications for
  /// paste problems (blocked, no target, elevated target, unknown failure).
  /// Dock bounce and taskbar flash are not affected; they stay the fallback.
  final bool notifyPasteProblems;

  /// Category switch under [showNotifications]: informational notice that
  /// Smart Mode fell back to the raw transcript. The paste itself succeeded.
  final bool notifySmartModeFallback;

  /// Category switch under [showNotifications]: the microphone delivers no
  /// signal shortly after the start (possibly muted or the wrong input).
  final bool notifyMicrophoneProblems;

  /// Whether the status bar shows the CPU/GPU backend-utilization chip
  /// (`_BackendUtilizationChip` in `status_bar.dart`). Default on: the
  /// GPU→CPU silent-fallback investigation that added this chip was
  /// discoverable by the user only because they happened to notice slower
  /// transcription — most users would never think to look.
  final bool showBackendUtilization;

  /// Whether the clipboard quick-paste side panel's hover trigger is armed
  /// at all (`SidePanelService`/native edge sensors). Default off (since
  /// 2026-10-30; existing installs keep it on, see `_migrateSidePanelDefault`).
  /// An always-on-top hover-activated edge zone is exactly the kind of thing
  /// some users want to turn off entirely rather than just tolerate.
  final bool sidePanelEnabled;

  /// Which screen edge the side panel docks to and slides out from. Default
  /// left matches the panel's original, still-most-common placement; users
  /// who keep desktop icons/taskbar shortcuts along the left edge (issue
  /// #150) can move it to the right instead.
  final SidePanelEdge sidePanelEdge;

  /// Apps whose copies never enter the clipboard history, as a JSON list of
  /// platform-specific identifiers (bundle id / exe name). `null` = never
  /// edited: the platform's password-manager defaults apply.
  final String? clipboardExcludedApps;

  /// Appearance mode (AR-21). Stored under `appearance`, not the retired
  /// `theme_mode` key, so values left over from the old toggle stay inert.
  final AppearanceMode appearance;

  static const InterfaceSettings defaults = InterfaceSettings();

  factory InterfaceSettings.fromMap(Map<String, String> v) => InterfaceSettings(
    locale: v['locale'] ?? defaults.locale,
    launchAtStartup: _readBool(
      v,
      'launch_at_startup',
      defaults.launchAtStartup,
    ),
    startMinimized: _readBool(v, 'start_minimized', defaults.startMinimized),
    showNotifications: _readBool(
      v,
      'show_notifications',
      defaults.showNotifications,
    ),
    notifyPasteProblems: _readBool(
      v,
      'notify_paste_problems',
      defaults.notifyPasteProblems,
    ),
    notifySmartModeFallback: _readBool(
      v,
      'notify_smart_mode_fallback',
      defaults.notifySmartModeFallback,
    ),
    notifyMicrophoneProblems: _readBool(
      v,
      'notify_microphone_problems',
      defaults.notifyMicrophoneProblems,
    ),
    showBackendUtilization: _readBool(
      v,
      'show_backend_utilization',
      defaults.showBackendUtilization,
    ),
    sidePanelEnabled: _readBool(
      v,
      'side_panel_enabled',
      defaults.sidePanelEnabled,
    ),
    sidePanelEdge: SidePanelEdge.fromValue(v['side_panel_edge']),
    clipboardExcludedApps: v['clipboard_excluded_apps'],
    appearance: AppearanceMode.fromValue(v['appearance']),
  );

  // No `theme_mode` entry since 2026-08-11. The key's row in `app_settings`
  // survives untouched — migrations here are additive-only — but nothing
  // writes it any more and nothing reads it back, so a value left over from
  // a user who once picked Light is inert rather than authoritative.
  Map<String, String> toMap() => {
    'locale': locale,
    'launch_at_startup': '$launchAtStartup',
    'start_minimized': '$startMinimized',
    'show_notifications': '$showNotifications',
    'notify_paste_problems': '$notifyPasteProblems',
    'notify_smart_mode_fallback': '$notifySmartModeFallback',
    'notify_microphone_problems': '$notifyMicrophoneProblems',
    'show_backend_utilization': '$showBackendUtilization',
    'side_panel_enabled': '$sidePanelEnabled',
    'side_panel_edge': sidePanelEdge.value,
    'clipboard_excluded_apps': ?clipboardExcludedApps,
    'appearance': appearance.value,
  };

  InterfaceSettings copyWith({
    String? locale,
    bool? launchAtStartup,
    bool? startMinimized,
    bool? showNotifications,
    bool? notifyPasteProblems,
    bool? notifySmartModeFallback,
    bool? notifyMicrophoneProblems,
    bool? showBackendUtilization,
    bool? sidePanelEnabled,
    SidePanelEdge? sidePanelEdge,
    String? clipboardExcludedApps,
    AppearanceMode? appearance,
  }) => InterfaceSettings(
    locale: locale ?? this.locale,
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    startMinimized: startMinimized ?? this.startMinimized,
    showNotifications: showNotifications ?? this.showNotifications,
    notifyPasteProblems: notifyPasteProblems ?? this.notifyPasteProblems,
    notifySmartModeFallback:
        notifySmartModeFallback ?? this.notifySmartModeFallback,
    notifyMicrophoneProblems:
        notifyMicrophoneProblems ?? this.notifyMicrophoneProblems,
    showBackendUtilization:
        showBackendUtilization ?? this.showBackendUtilization,
    sidePanelEnabled: sidePanelEnabled ?? this.sidePanelEnabled,
    sidePanelEdge: sidePanelEdge ?? this.sidePanelEdge,
    clipboardExcludedApps: clipboardExcludedApps ?? this.clipboardExcludedApps,
    appearance: appearance ?? this.appearance,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterfaceSettings &&
          locale == other.locale &&
          launchAtStartup == other.launchAtStartup &&
          startMinimized == other.startMinimized &&
          showNotifications == other.showNotifications &&
          notifyPasteProblems == other.notifyPasteProblems &&
          notifySmartModeFallback == other.notifySmartModeFallback &&
          notifyMicrophoneProblems == other.notifyMicrophoneProblems &&
          showBackendUtilization == other.showBackendUtilization &&
          sidePanelEnabled == other.sidePanelEnabled &&
          sidePanelEdge == other.sidePanelEdge &&
          clipboardExcludedApps == other.clipboardExcludedApps &&
          appearance == other.appearance;

  @override
  int get hashCode => Object.hash(
    locale,
    launchAtStartup,
    startMinimized,
    showNotifications,
    notifyPasteProblems,
    notifySmartModeFallback,
    notifyMicrophoneProblems,
    showBackendUtilization,
    sidePanelEnabled,
    sidePanelEdge,
    clipboardExcludedApps,
    appearance,
  );
}

// ===========================================================================
// Section 2 — Audio Input
// ===========================================================================

/// Keys offered for cancelling a dictation. Escape is the default; F12 is the
/// alternative for users whose apps already bind Escape.
const cancelDictationKeyEscape = 'escape';
const cancelDictationKeyChoices = [cancelDictationKeyEscape, 'f12'];

/// Default Hold-or-Tap threshold (Automatisch): 250 ms, per product decision.
const defaultHoldOrTapThresholdMs = 250;
const minHoldOrTapThresholdMs = 150;
const maxHoldOrTapThresholdMs = 1500;

int _readHoldOrTapThresholdMs(Map<String, String> v) {
  final raw = int.tryParse(v['hold_or_tap_threshold_ms'] ?? '');
  if (raw == null) return defaultHoldOrTapThresholdMs;
  return raw.clamp(minHoldOrTapThresholdMs, maxHoldOrTapThresholdMs);
}

/// Range of the manual input volume (#1611), in dB: never silent, at most
/// +18 dB. Stored as a linear factor in `input_gain` (the key predates dB).
const double minInputGainDb = -12;
const double maxInputGainDb = 18;

/// Reads `input_gain` bounded to [minInputGainDb]..[maxInputGainDb]. A
/// missing, unreadable, NaN or infinite value falls back to the default 1.0;
/// zero and negative values (mute, phase flip) become the minimum. Used for
/// stored settings and imports alike (both go through `fromMap`).
double readInputGain(String? raw) {
  final value = double.tryParse(raw ?? '');
  if (value == null || !value.isFinite) return 1.0;
  final min = math.pow(10, minInputGainDb / 20).toDouble();
  final max = math.pow(10, maxInputGainDb / 20).toDouble();
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// Whether `auto_level` is on in [v]. Additive key (#1611): settings written
/// before it exist read it from `input_gain`. The default 1.0 (also new
/// installs) means on; a value the user chose keeps the manual mode.
bool _readAutoLevel(Map<String, String> v) {
  final stored = v['auto_level'];
  if (stored != null) return stored == 'true';
  return readInputGain(v['input_gain']) == 1.0;
}

class AudioInputSettings {
  const AudioInputSettings({
    this.microphone = 'Default',
    this.pushToTalk = true,
    this.holdOrTap = false,
    this.holdOrTapThresholdMs = defaultHoldOrTapThresholdMs,
    this.shortPressHintHidden = false,
    this.cancelDictationKey = cancelDictationKeyEscape,
    this.inputGain = 1.0,
    this.autoLevel = true,
    this.microphonePriority = const [],
    this.pauseMediaWhileRecording = false,
  });

  /// Key that cancels a running dictation. One of [cancelDictationKeyChoices].
  final String cancelDictationKey;

  final String microphone;

  /// Ordered device labels, most preferred first. Used when the explicit
  /// [microphone] is absent (unplugged) or set to "Default". Virtual and
  /// loopback inputs are never picked from this list.
  final List<String> microphonePriority;

  final bool pushToTalk;

  /// Pause running music/video while recording and resume what was paused
  /// afterwards (#563). Opt-in.
  final bool pauseMediaWhileRecording;

  /// Hold-or-Tap hybrid (sub-option of [pushToTalk]): with both on, a short
  /// tap toggles and a longer hold acts as push-to-talk. Ignored while
  /// [pushToTalk] is off, so an older build that does not know this key
  /// degrades gracefully to plain push-to-talk.
  final bool holdOrTap;

  /// Hold-or-Tap threshold in milliseconds: a press released earlier latches
  /// the recording (tap), a longer press is push-to-talk (hold). Clamped to
  /// [minHoldOrTapThresholdMs]..[maxHoldOrTapThresholdMs] on read.
  final int holdOrTapThresholdMs;

  /// The user chose "Don't show again" on the short-press card (#877).
  /// Additive key: older settings files simply read `false`.
  final bool shortPressHintHidden;

  /// Manual input volume as a linear factor ("Eingangslautstärke", #1611).
  /// `1.0` is identity. The settings UI shows it in dB
  /// ([minInputGainDb]..[maxInputGainDb]); reads are bounded by
  /// [readInputGain]. Applied by `PcmGainProcessor` only while [autoLevel]
  /// is off. No platform gain control is involved on any system.
  final double inputGain;

  /// "Lautstärke automatisch angleichen" (#1611): after the stop, before the
  /// WAV goes to recognition, quiet speech is raised to a steady level
  /// (`speech_leveler.dart`). On for new installs; see [_readAutoLevel] for
  /// settings written before the key existed.
  final bool autoLevel;

  static const AudioInputSettings defaults = AudioInputSettings();

  factory AudioInputSettings.fromMap(Map<String, String> v) =>
      AudioInputSettings(
        microphone: v['microphone'] ?? defaults.microphone,
        pushToTalk: _readBool(v, 'push_to_talk', defaults.pushToTalk),
        holdOrTap: _readBool(v, 'hold_or_tap', defaults.holdOrTap),
        holdOrTapThresholdMs: _readHoldOrTapThresholdMs(v),
        shortPressHintHidden: _readBool(
          v,
          'short_press_hint_hidden',
          defaults.shortPressHintHidden,
        ),
        cancelDictationKey:
            cancelDictationKeyChoices.contains(v['cancel_dictation_key'])
            ? v['cancel_dictation_key']!
            : defaults.cancelDictationKey,
        inputGain: readInputGain(v['input_gain']),
        autoLevel: _readAutoLevel(v),
        microphonePriority: _readStringList(v, 'microphone_priority'),
        pauseMediaWhileRecording: _readBool(
          v,
          'pause_media_while_recording',
          defaults.pauseMediaWhileRecording,
        ),
      );

  Map<String, String> toMap() => {
    'microphone': microphone,
    'push_to_talk': '$pushToTalk',
    'hold_or_tap': '$holdOrTap',
    'hold_or_tap_threshold_ms': '$holdOrTapThresholdMs',
    'short_press_hint_hidden': '$shortPressHintHidden',
    'cancel_dictation_key': cancelDictationKey,
    'input_gain': '$inputGain',
    'auto_level': '$autoLevel',
    'microphone_priority': jsonEncode(microphonePriority),
    'pause_media_while_recording': '$pauseMediaWhileRecording',
  };

  AudioInputSettings copyWith({
    String? microphone,
    bool? pushToTalk,
    bool? holdOrTap,
    int? holdOrTapThresholdMs,
    bool? shortPressHintHidden,
    String? cancelDictationKey,
    double? inputGain,
    bool? autoLevel,
    List<String>? microphonePriority,
    bool? pauseMediaWhileRecording,
  }) => AudioInputSettings(
    microphone: microphone ?? this.microphone,
    pushToTalk: pushToTalk ?? this.pushToTalk,
    holdOrTap: holdOrTap ?? this.holdOrTap,
    holdOrTapThresholdMs: holdOrTapThresholdMs ?? this.holdOrTapThresholdMs,
    shortPressHintHidden: shortPressHintHidden ?? this.shortPressHintHidden,
    cancelDictationKey: cancelDictationKey ?? this.cancelDictationKey,
    inputGain: inputGain ?? this.inputGain,
    autoLevel: autoLevel ?? this.autoLevel,
    microphonePriority: microphonePriority ?? this.microphonePriority,
    pauseMediaWhileRecording:
        pauseMediaWhileRecording ?? this.pauseMediaWhileRecording,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioInputSettings &&
          microphone == other.microphone &&
          pushToTalk == other.pushToTalk &&
          holdOrTap == other.holdOrTap &&
          holdOrTapThresholdMs == other.holdOrTapThresholdMs &&
          shortPressHintHidden == other.shortPressHintHidden &&
          cancelDictationKey == other.cancelDictationKey &&
          inputGain == other.inputGain &&
          autoLevel == other.autoLevel &&
          _sameStrings(microphonePriority, other.microphonePriority) &&
          pauseMediaWhileRecording == other.pauseMediaWhileRecording;

  @override
  int get hashCode => Object.hash(
    microphone,
    pushToTalk,
    holdOrTap,
    holdOrTapThresholdMs,
    shortPressHintHidden,
    cancelDictationKey,
    inputGain,
    autoLevel,
    Object.hashAll(microphonePriority),
    pauseMediaWhileRecording,
  );
}

// ===========================================================================
// Section 3 — Recording Safety
// ===========================================================================

class RecordingSafetySettings {
  const RecordingSafetySettings({
    this.deadMicTimeout = 3.0,
    this.autoStopSilence = 0.0,
  });

  final double deadMicTimeout;
  final double autoStopSilence;

  static const RecordingSafetySettings defaults = RecordingSafetySettings();

  factory RecordingSafetySettings.fromMap(Map<String, String> v) =>
      RecordingSafetySettings(
        deadMicTimeout: _readDouble(
          v,
          'dead_mic_timeout',
          defaults.deadMicTimeout,
        ),
        autoStopSilence: _readDouble(
          v,
          'auto_stop_silence',
          defaults.autoStopSilence,
        ),
      );

  Map<String, String> toMap() => {
    'dead_mic_timeout': '$deadMicTimeout',
    'auto_stop_silence': '$autoStopSilence',
  };

  RecordingSafetySettings copyWith({
    double? deadMicTimeout,
    double? autoStopSilence,
  }) => RecordingSafetySettings(
    deadMicTimeout: deadMicTimeout ?? this.deadMicTimeout,
    autoStopSilence: autoStopSilence ?? this.autoStopSilence,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingSafetySettings &&
          deadMicTimeout == other.deadMicTimeout &&
          autoStopSilence == other.autoStopSilence;

  @override
  int get hashCode => Object.hash(deadMicTimeout, autoStopSilence);
}

// ===========================================================================
// Section 4 — STT
// ===========================================================================
/// Written forms ("Schreibformen") switches: the master switch and one per
/// kind (e-mail, web address, date, time, money). Each kind is ignored while
/// the master is off.
class WrittenFormSettings {
  const WrittenFormSettings({
    this.enabled = true,
    this.email = true,
    this.url = true,
    this.date = true,
    this.time = true,
    this.money = true,
  });

  final bool enabled;
  final bool email;
  final bool url;
  final bool date;
  final bool time;
  final bool money;

  WrittenFormSettings copyWith({
    bool? enabled,
    bool? email,
    bool? url,
    bool? date,
    bool? time,
    bool? money,
  }) => WrittenFormSettings(
    enabled: enabled ?? this.enabled,
    email: email ?? this.email,
    url: url ?? this.url,
    date: date ?? this.date,
    time: time ?? this.time,
    money: money ?? this.money,
  );

  @override
  bool operator ==(Object other) =>
      other is WrittenFormSettings &&
      enabled == other.enabled &&
      email == other.email &&
      url == other.url &&
      date == other.date &&
      time == other.time &&
      money == other.money;

  @override
  int get hashCode => Object.hash(enabled, email, url, date, time, money);
}

class SttSettings {
  const SttSettings({
    this.provider = 'On Device',
    this.model = 'whisper-medium',
    this.language = 'Auto-detect',
    this.idleTimeoutMinutes = 0,
    this.customVocabulary = '',
    this.engine = 'whisper',
    this.punctuationPriming = true,
    this.stripPunctuation = false,
    this.vadEnabled = true,
    this.numericOnlyMode = false,
    this.removeFillerWords = false,
    this.voiceLineBreaks = true,
    this.spokenPunctuation = false,
    this.writtenForms = const WrittenFormSettings(),
    this.favoriteLanguages = const [],
    this.languageCycleHotkeyEnabled = false,
    this.languageCycleHotkeyKey = 'L',
    this.languageCycleHotkeyKeyDisplay = '',
    this.languageCycleHotkeyModifiers = 'ctrl+shift',
  });

  final String provider;
  final String model;
  final String language;

  /// Up to [maxFavoriteLanguages] recognition-language codes the user marked
  /// as favorites. They feed the dock's favorites block, the tray submenu and
  /// the "next favorite language" hotkey. Empty by default.
  final List<String> favoriteLanguages;

  /// Off by default. When on, the "next favorite language" hotkey cycles the
  /// recognition language through [favoriteLanguages]. Stored like the other
  /// secondary hotkeys (see [SnippetPickerHotkeySettings]).
  final bool languageCycleHotkeyEnabled;
  final String languageCycleHotkeyKey;
  final String languageCycleHotkeyKeyDisplay;
  final String languageCycleHotkeyModifiers;

  static const int maxFavoriteLanguages = fav.maxFavoriteLanguages;

  /// Minutes before idle STT server is shut down (0 = keep alive, default; -1 = auto).
  final int idleTimeoutMinutes;

  /// User-defined vocabulary terms (names, jargon) passed as Whisper prompt
  /// prefix to improve recognition of domain-specific words.
  final String customVocabulary;

  /// On-device engine sub-selection (`whisper` | `parakeet`). Irrelevant when
  /// [provider] is a cloud provider. See [OnDeviceEngine].
  final String engine;

  /// Whether a short, punctuated example prompt is used to bias Whisper
  /// towards punctuated output when neither [customVocabulary] nor a rolling
  /// context prompt is available (see `resolvePunctuationPrimingPrompt` in
  /// `punctuation_priming_prompts.dart`). Whisper's prompt mechanism works
  /// through style mimicry, so this never overrides [customVocabulary] —
  /// it only fills the gap when there is nothing else to prime with.
  /// Default on because it costs no extra latency (same greedy decoding,
  /// just a short prefix) — opt-out exists for users who want raw,
  /// unprimed model output (e.g. verbatim technical dictation).
  final bool punctuationPriming;

  /// Whether sentence-level punctuation (periods, commas, question/
  /// exclamation marks, colons, semicolons, and the em/en dash + ellipsis
  /// some STT engines insert as clause connectors) is deterministically
  /// stripped from the final transcript before it is saved/pasted — see
  /// `stripPunctuation` in `text_transforms.dart`. A period/comma inside a
  /// number (decimal point, thousands separator, version number, price) is
  /// never removed, regardless of this setting.
  ///
  /// Unlike [punctuationPriming] (a Whisper-only prompt nudge that cannot
  /// reliably suppress punctuation the model adds on its own), this is a
  /// plain text post-processing step applied uniformly after transcription
  /// regardless of engine or provider — on-device Whisper, Parakeet, and
  /// every cloud provider all go through the same code path
  /// (`RecordingOrchestrator`), so the toggle behaves identically everywhere.
  final bool stripPunctuation;

  /// Whether whisper.cpp's built-in Voice Activity Detection pre-pass runs
  /// before decoding — the mitigation for Whisper's documented
  /// trailing-silence/low-confidence hallucination class (e.g. fabricated
  /// "Vielen Dank." closings tacked onto the real transcript). Only affects
  /// the on-device Whisper engine ([engine] `'whisper'`); Parakeet and
  /// cloud providers are unaffected. No-op if the platform build hasn't
  /// bundled the VAD model (see `assets/models/vad/NOTICE.md`) — never an
  /// error. Default on (opt-out) — negligible cost (~2.5ms of VAD compute
  /// per second of audio, see the "Vielen Dank" investigation) and
  /// validated to preserve genuinely spoken trailing content (real endings,
  /// mid-utterance pauses, quiet/fading speech) before being wired in.
  final bool vadEnabled;

  /// Whether the finished transcript is rendered exclusively as digits
  /// (`[0-9.,-]`) — see `toNumericOnly` in `number_transforms.dart`. All-or-
  /// nothing: a transcript that isn't fully convertible is left unchanged.
  final bool numericOnlyMode;

  /// Whether unambiguous hesitation fillers ("äh", "ähm", "uh", "um", ...)
  /// are removed from the final transcript before Smart Mode and text
  /// replacements run — see `removeFillerWords` in `text_transforms.dart`.
  /// Same engine-independent post-processing path as [stripPunctuation].
  /// Default off: a dictation stays verbatim unless the user opts in.
  final bool removeFillerWords;

  /// Whether spoken line-break commands ("new paragraph", "neue Zeile", ...)
  /// are turned into real line breaks, after filler removal and before Smart
  /// Mode and text replacements — see `applyVoiceLineBreaks` in
  /// `voice_line_breaks.dart`. Default on: spoken paragraph commands are the
  /// point of the feature, and a dictation without those phrases is untouched.
  final bool voiceLineBreaks;

  /// Whether spoken punctuation commands ("Komma", "comma", "punto", ...)
  /// become the marks they name, after line breaks in the pipeline — see
  /// `applyVoicePunctuation` in `voice_punctuation.dart`. Default off: a
  /// dictation keeps the words it was spoken with unless the user opts in.
  final bool spokenPunctuation;

  /// The written forms ("Schreibformen"): the master switch and one switch
  /// per kind. Runs after line breaks, before the dictionary replacements.
  /// See `applyWrittenForms` in `lib/services/itn/itn_pipeline.dart`.
  final WrittenFormSettings writtenForms;

  static const SttSettings defaults = SttSettings();

  /// Parses the persisted comma-separated codes: trimmed, de-duplicated,
  /// empty entries dropped and capped at [maxFavoriteLanguages].
  static List<String> parseFavoriteLanguages(String raw) =>
      fav.parseFavoriteLanguageList(raw);

  factory SttSettings.fromMap(Map<String, String> v) => SttSettings(
    provider: v['stt_provider'] ?? defaults.provider,
    model: _migrateModelId(v['stt_model'] ?? defaults.model),
    language: v['stt_language'] ?? defaults.language,
    idleTimeoutMinutes: _readInt(
      v,
      'stt_idle_timeout_minutes',
      defaults.idleTimeoutMinutes,
    ),
    customVocabulary: v['custom_vocabulary'] ?? defaults.customVocabulary,
    engine: v['stt_engine'] ?? defaults.engine,
    punctuationPriming: _readBool(
      v,
      'stt_punctuation_priming',
      defaults.punctuationPriming,
    ),
    stripPunctuation: _readBool(
      v,
      'stt_strip_punctuation',
      defaults.stripPunctuation,
    ),
    vadEnabled: _readBool(v, 'stt_vad_enabled', defaults.vadEnabled),
    numericOnlyMode: _readBool(
      v,
      'stt_numeric_only_mode',
      defaults.numericOnlyMode,
    ),
    removeFillerWords: _readBool(
      v,
      'stt_remove_filler_words',
      defaults.removeFillerWords,
    ),
    voiceLineBreaks: _readBool(
      v,
      'stt_voice_line_breaks',
      defaults.voiceLineBreaks,
    ),
    spokenPunctuation: _readBool(
      v,
      'stt_spoken_punctuation',
      defaults.spokenPunctuation,
    ),
    writtenForms: WrittenFormSettings(
      enabled: _readBool(v, 'stt_written_forms', defaults.writtenForms.enabled),
      email: _readBool(
        v,
        'stt_written_form_email',
        defaults.writtenForms.email,
      ),
      url: _readBool(v, 'stt_written_form_url', defaults.writtenForms.url),
      date: _readBool(v, 'stt_written_form_date', defaults.writtenForms.date),
      time: _readBool(v, 'stt_written_form_time', defaults.writtenForms.time),
      money: _readBool(
        v,
        'stt_written_form_money',
        defaults.writtenForms.money,
      ),
    ),
    favoriteLanguages: parseFavoriteLanguages(
      v['stt_favorite_languages'] ?? '',
    ),
    languageCycleHotkeyEnabled: _readBool(
      v,
      'stt_language_cycle_hotkey_enabled',
      false,
    ),
    languageCycleHotkeyKey: v['stt_language_cycle_hotkey_key'] ?? 'L',
    languageCycleHotkeyKeyDisplay:
        v['stt_language_cycle_hotkey_key_display'] ?? '',
    languageCycleHotkeyModifiers:
        v['stt_language_cycle_hotkey_modifiers'] ?? 'ctrl+shift',
  );

  Map<String, String> toMap() => {
    'stt_provider': provider,
    'stt_model': model,
    'stt_language': language,
    'stt_idle_timeout_minutes': '$idleTimeoutMinutes',
    'custom_vocabulary': customVocabulary,
    'stt_engine': engine,
    'stt_punctuation_priming': '$punctuationPriming',
    'stt_strip_punctuation': '$stripPunctuation',
    'stt_vad_enabled': '$vadEnabled',
    'stt_numeric_only_mode': '$numericOnlyMode',
    'stt_remove_filler_words': '$removeFillerWords',
    'stt_voice_line_breaks': '$voiceLineBreaks',
    'stt_spoken_punctuation': '$spokenPunctuation',
    'stt_written_forms': '${writtenForms.enabled}',
    'stt_written_form_email': '${writtenForms.email}',
    'stt_written_form_url': '${writtenForms.url}',
    'stt_written_form_date': '${writtenForms.date}',
    'stt_written_form_time': '${writtenForms.time}',
    'stt_written_form_money': '${writtenForms.money}',
    'stt_favorite_languages': favoriteLanguages.join(','),
    'stt_language_cycle_hotkey_enabled': '$languageCycleHotkeyEnabled',
    'stt_language_cycle_hotkey_key': languageCycleHotkeyKey,
    'stt_language_cycle_hotkey_key_display': languageCycleHotkeyKeyDisplay,
    'stt_language_cycle_hotkey_modifiers': languageCycleHotkeyModifiers,
  };

  SttSettings copyWith({
    String? provider,
    String? model,
    String? language,
    int? idleTimeoutMinutes,
    String? customVocabulary,
    String? engine,
    bool? punctuationPriming,
    bool? stripPunctuation,
    bool? vadEnabled,
    bool? numericOnlyMode,
    bool? removeFillerWords,
    bool? voiceLineBreaks,
    bool? spokenPunctuation,
    WrittenFormSettings? writtenForms,
    List<String>? favoriteLanguages,
    bool? languageCycleHotkeyEnabled,
    String? languageCycleHotkeyKey,
    String? languageCycleHotkeyKeyDisplay,
    String? languageCycleHotkeyModifiers,
  }) => SttSettings(
    provider: provider ?? this.provider,
    model: model ?? this.model,
    language: language ?? this.language,
    idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
    customVocabulary: customVocabulary ?? this.customVocabulary,
    engine: engine ?? this.engine,
    punctuationPriming: punctuationPriming ?? this.punctuationPriming,
    stripPunctuation: stripPunctuation ?? this.stripPunctuation,
    vadEnabled: vadEnabled ?? this.vadEnabled,
    numericOnlyMode: numericOnlyMode ?? this.numericOnlyMode,
    removeFillerWords: removeFillerWords ?? this.removeFillerWords,
    voiceLineBreaks: voiceLineBreaks ?? this.voiceLineBreaks,
    spokenPunctuation: spokenPunctuation ?? this.spokenPunctuation,
    writtenForms: writtenForms ?? this.writtenForms,
    favoriteLanguages: favoriteLanguages == null
        ? this.favoriteLanguages
        : List.unmodifiable(favoriteLanguages),
    languageCycleHotkeyEnabled:
        languageCycleHotkeyEnabled ?? this.languageCycleHotkeyEnabled,
    languageCycleHotkeyKey:
        languageCycleHotkeyKey ?? this.languageCycleHotkeyKey,
    languageCycleHotkeyKeyDisplay:
        languageCycleHotkeyKeyDisplay ?? this.languageCycleHotkeyKeyDisplay,
    languageCycleHotkeyModifiers:
        languageCycleHotkeyModifiers ?? this.languageCycleHotkeyModifiers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SttSettings &&
          provider == other.provider &&
          model == other.model &&
          language == other.language &&
          idleTimeoutMinutes == other.idleTimeoutMinutes &&
          customVocabulary == other.customVocabulary &&
          engine == other.engine &&
          punctuationPriming == other.punctuationPriming &&
          stripPunctuation == other.stripPunctuation &&
          vadEnabled == other.vadEnabled &&
          numericOnlyMode == other.numericOnlyMode &&
          removeFillerWords == other.removeFillerWords &&
          voiceLineBreaks == other.voiceLineBreaks &&
          spokenPunctuation == other.spokenPunctuation &&
          writtenForms == other.writtenForms &&
          listEquals(favoriteLanguages, other.favoriteLanguages) &&
          languageCycleHotkeyEnabled == other.languageCycleHotkeyEnabled &&
          languageCycleHotkeyKey == other.languageCycleHotkeyKey &&
          languageCycleHotkeyKeyDisplay ==
              other.languageCycleHotkeyKeyDisplay &&
          languageCycleHotkeyModifiers == other.languageCycleHotkeyModifiers;

  @override
  int get hashCode => Object.hashAll([
    provider,
    model,
    language,
    idleTimeoutMinutes,
    customVocabulary,
    engine,
    punctuationPriming,
    stripPunctuation,
    vadEnabled,
    numericOnlyMode,
    removeFillerWords,
    voiceLineBreaks,
    spokenPunctuation,
    writtenForms,
    Object.hashAll(favoriteLanguages),
    languageCycleHotkeyEnabled,
    languageCycleHotkeyKey,
    languageCycleHotkeyKeyDisplay,
    languageCycleHotkeyModifiers,
  ]);
}

// ===========================================================================
// Section 5 — Sound
// ===========================================================================

class SoundSettings {
  const SoundSettings({
    this.recordStartSound = true,
    this.recordStopSound = true,
    this.transcriptionCompleteSound = true,
    this.durationWarningSound = true,
    this.errorSound = true,
    this.pasteSound = false,
    this.soundSet = SoundSet.bernstein,
    this.soundVolume = 80.0,
  });

  final bool recordStartSound;
  final bool recordStopSound;
  final bool transcriptionCompleteSound;
  final bool durationWarningSound;
  final bool errorSound;

  /// The very quiet cue after a successful paste. Sets without a paste cue
  /// ([SoundSet.classic]) stay silent. Off by default, also for existing
  /// installs (#1343): it is stored under `paste_cue_sound`, because the
  /// unused `paste_sound` key was saved as `true` by every install before
  /// the cue ever played, without the user choosing it.
  final bool pasteSound;
  final SoundSet soundSet;
  final double soundVolume;

  static const SoundSettings defaults = SoundSettings();

  factory SoundSettings.fromMap(Map<String, String> v) => SoundSettings(
    recordStartSound: _readBool(
      v,
      'record_start_sound',
      defaults.recordStartSound,
    ),
    recordStopSound: _readBool(
      v,
      'record_stop_sound',
      defaults.recordStopSound,
    ),
    transcriptionCompleteSound: _readBool(
      v,
      'transcription_complete_sound',
      defaults.transcriptionCompleteSound,
    ),
    durationWarningSound: _readBool(
      v,
      'duration_warning_sound',
      defaults.durationWarningSound,
    ),
    errorSound: _readBool(v, 'error_sound', defaults.errorSound),
    pasteSound: _readBool(v, 'paste_cue_sound', defaults.pasteSound),
    soundSet: SoundSet.fromValue(v['sound_set']),
    soundVolume: _readDouble(v, 'sound_volume', defaults.soundVolume),
  );

  Map<String, String> toMap() => {
    'record_start_sound': '$recordStartSound',
    'record_stop_sound': '$recordStopSound',
    'transcription_complete_sound': '$transcriptionCompleteSound',
    'duration_warning_sound': '$durationWarningSound',
    'error_sound': '$errorSound',
    'paste_cue_sound': '$pasteSound',
    'sound_set': soundSet.value,
    'sound_volume': '$soundVolume',
  };

  SoundSettings copyWith({
    bool? recordStartSound,
    bool? recordStopSound,
    bool? transcriptionCompleteSound,
    bool? durationWarningSound,
    bool? errorSound,
    bool? pasteSound,
    SoundSet? soundSet,
    double? soundVolume,
  }) => SoundSettings(
    recordStartSound: recordStartSound ?? this.recordStartSound,
    recordStopSound: recordStopSound ?? this.recordStopSound,
    transcriptionCompleteSound:
        transcriptionCompleteSound ?? this.transcriptionCompleteSound,
    durationWarningSound: durationWarningSound ?? this.durationWarningSound,
    errorSound: errorSound ?? this.errorSound,
    pasteSound: pasteSound ?? this.pasteSound,
    soundSet: soundSet ?? this.soundSet,
    soundVolume: soundVolume ?? this.soundVolume,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SoundSettings &&
          recordStartSound == other.recordStartSound &&
          recordStopSound == other.recordStopSound &&
          transcriptionCompleteSound == other.transcriptionCompleteSound &&
          durationWarningSound == other.durationWarningSound &&
          errorSound == other.errorSound &&
          pasteSound == other.pasteSound &&
          soundSet == other.soundSet &&
          soundVolume == other.soundVolume;

  @override
  int get hashCode => Object.hash(
    recordStartSound,
    recordStopSound,
    transcriptionCompleteSound,
    durationWarningSound,
    errorSound,
    pasteSound,
    soundSet,
    soundVolume,
  );
}

// ===========================================================================
// Section 6 — After Transcription
// ===========================================================================

class AfterTranscriptionSettings {
  const AfterTranscriptionSettings({this.afterTranscription = 'clipboard'});

  /// What happens after transcription: 'clipboard', 'paste',
  /// 'clipboard_and_paste', or 'nothing'
  final String afterTranscription;

  static const AfterTranscriptionSettings defaults =
      AfterTranscriptionSettings();

  factory AfterTranscriptionSettings.fromMap(Map<String, String> v) =>
      AfterTranscriptionSettings(
        afterTranscription:
            v['after_transcription'] ?? defaults.afterTranscription,
      );

  Map<String, String> toMap() => {'after_transcription': afterTranscription};

  AfterTranscriptionSettings copyWith({String? afterTranscription}) =>
      AfterTranscriptionSettings(
        afterTranscription: afterTranscription ?? this.afterTranscription,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AfterTranscriptionSettings &&
          afterTranscription == other.afterTranscription;

  @override
  int get hashCode => afterTranscription.hashCode;
}

/// Background preset for each retired `overlay_style` value (ADR 0024,
/// migration table). Glass and solid drew the same opaque navy pill (UX-013),
/// so both map to marine. Unknown values get no entry and fall back to the
/// default, like every other unknown preset name.
const Map<String, String> _legacyOverlayStyleBackground = {
  'glass': 'marine',
  'solid': 'marine',
};

/// Carries a retired `overlay_style` entry into the preset keys. An explicit
/// `overlay_background` or `overlay_wave` in [raw] always wins; the retired key
/// is removed either way. Used when reading stored settings (upgrade) and when
/// importing an export from an older version.
Map<String, String> migrateLegacyOverlayStyle(Map<String, String> raw) {
  if (!raw.containsKey('overlay_style')) return raw;
  final migrated = {...raw}..remove('overlay_style');
  migrated.putIfAbsent(
    'overlay_background',
    () => _legacyOverlayStyleBackground[raw['overlay_style']] ?? 'marine',
  );
  // The retired style had no wave colour; it always drew the cyan wave.
  migrated.putIfAbsent('overlay_wave', () => 'cyan');
  return migrated;
}

/// Wave preset that was retired (2026-10-29). Stored `neutral` loads as `ink`,
/// its light-background counterpart. `ink` is invalid on the dark backgrounds
/// and then moves to the replacement wave (see `OverlayWave.validOn`).
const Map<String, String> _retiredOverlayWaves = {'neutral': 'ink'};

/// Carries a retired wave preset in [raw] over to its successor (see
/// [_retiredOverlayWaves]). Used when reading stored settings and when
/// importing an export from an older version.
Map<String, String> migrateRetiredOverlayWave(Map<String, String> raw) {
  final successor = _retiredOverlayWaves[raw['overlay_wave']];
  if (successor == null) return raw;
  return {...raw, 'overlay_wave': successor};
}

// ===========================================================================
// Section 7 — Overlay
// ===========================================================================

class OverlaySettings {
  const OverlaySettings({
    this.showOverlay = false,
    this.overlayMode = 'floating',
    this.overlayStartPosition = 'top-center',
    this.overlaySize = 'compact',
    this.overlayBackground = 'amber',
    this.overlayWave = 'ink',
    this.showFloatingButton = false,
    this.overlayShowLiveTranscript = false,
    this.overlayQuietHint = true,
    this.overlayForm = 'pill',
    this.overlayWaveStyle = 'bars',
    this.overlayWaveFluid = false,
    this.overlayShowTimer = true,
    this.overlayShowCancel = true,
    this.overlayOpacity = '100',
    this.floatingButtonSize = 'medium',
    this.floatingButtonShape = 'round',
    this.floatingButtonRing = true,
    this.floatingButtonIdleOpacity = '100',
    this.floatingButtonIdleCapsule = false,
  });

  final bool showOverlay;

  /// 'floating' or 'off'.
  final String overlayMode;

  /// 'top-center', 'bottom-center', or 'last-position'.
  final String overlayStartPosition;

  /// 'normal' or 'compact'.
  final String overlaySize;

  /// Background preset: 'marine', 'graphit', 'gletscher' or 'amber' (ADR 0024).
  /// Replaces the retired `overlay_style` key, which is no longer written.
  final String overlayBackground;

  /// Wave colour preset: 'cyan', 'violett', 'amber', 'ink', 'white', 'coral' or 'mint'
  /// (ADR 0024). Retired 'neutral' is loaded as 'ink'.
  final String overlayWave;

  /// Window shape: 'pill' or 'rounded-rect' (other stored values read as 'pill')
  /// (ticket, see `OverlayForm` in `overlay_customization.dart`).
  final String overlayForm;

  /// Waveform drawing: 'bars', 'line', 'dots', 'ribbon' or 'pulse'
  /// (`OverlayWaveStyle`).
  final String overlayWaveStyle;

  /// Fluid, speech-reactive outline. Off gives a static outline. Reduce
  /// motion in the system overrides this (`OverlayPolicy`).
  final bool overlayWaveFluid;

  /// Elapsed-time label in the overlay.
  final bool overlayShowTimer;

  /// Cancel button in the overlay. Esc cancels regardless of this setting.
  final bool overlayShowCancel;

  /// Fill opacity as a percentage string: '100', '80' or '60'
  /// (`OverlayOpacity`). Clamped by `OverlayOpacityGate` at render time.
  final String overlayOpacity;

  /// Floating button disc size: 'small' (44), 'medium' (56) or 'large' (80).
  final String floatingButtonSize;

  /// Floating button shape: 'round' (disc) or 'square' (rounded square).
  final String floatingButtonShape;

  /// Recording ring around the floating button while recording.
  final bool floatingButtonRing;

  /// Resting opacity of the floating button when idle, as a percentage
  /// string: '100', '70' or '40'.
  final String floatingButtonIdleOpacity;

  final bool showFloatingButton;

  /// Idle form of the floating button: a small capsule that expands to the
  /// pill on hover ("Immer sichtbar"). Off keeps the disc.
  final bool floatingButtonIdleCapsule;

  /// Whether the overlay shows the live/partial recognized text (as far as
  /// the active STT engine has decoded it) instead of staying waveform-only.
  ///
  /// Defaults to `false`: the ticket 11 PRD explicitly keeps the existing,
  /// deliberately minimal waveform-only overlay as the default/selectable
  /// behaviour (privacy/reduction — no in-progress text on screen unless the
  /// user opts in), with live text as an opt-in error-transparency trade-off.
  final bool overlayShowLiveTranscript;

  /// Whether the overlay shows the quiet-microphone notice card (overlay F2).
  /// Settings > Overlay turns the hint off and on.
  final bool overlayQuietHint;

  static const OverlaySettings defaults = OverlaySettings();

  factory OverlaySettings.fromMap(Map<String, String> raw) {
    final v = migrateRetiredOverlayWave(migrateLegacyOverlayStyle(raw));
    return OverlaySettings(
      showOverlay: _readBool(v, 'show_overlay', defaults.showOverlay),
      overlayMode:
          v['overlay_mode'] ??
          (_readBool(v, 'show_overlay', defaults.showOverlay)
              ? defaults.overlayMode
              : OverlayMode.off.value),
      overlayStartPosition:
          v['overlay_start_position'] ?? defaults.overlayStartPosition,
      overlaySize: v['overlay_size'] ?? defaults.overlaySize,
      overlayBackground: v['overlay_background'] ?? defaults.overlayBackground,
      overlayWave: v['overlay_wave'] ?? defaults.overlayWave,
      overlayForm: v['overlay_form'] ?? defaults.overlayForm,
      overlayWaveStyle: v['overlay_wave_style'] ?? defaults.overlayWaveStyle,
      overlayWaveFluid: _readBool(
        v,
        'overlay_wave_fluid',
        defaults.overlayWaveFluid,
      ),
      overlayShowTimer: _readBool(
        v,
        'overlay_show_timer',
        defaults.overlayShowTimer,
      ),
      overlayShowCancel: _readBool(
        v,
        'overlay_show_cancel',
        defaults.overlayShowCancel,
      ),
      overlayOpacity: v['overlay_opacity'] ?? defaults.overlayOpacity,
      floatingButtonSize:
          v['overlay_button_size'] ?? defaults.floatingButtonSize,
      floatingButtonShape:
          v['overlay_button_shape'] ?? defaults.floatingButtonShape,
      floatingButtonRing: _readBool(
        v,
        'overlay_button_ring',
        defaults.floatingButtonRing,
      ),
      floatingButtonIdleOpacity:
          v['overlay_button_idle_opacity'] ??
          defaults.floatingButtonIdleOpacity,
      showFloatingButton: _readBool(
        v,
        'show_floating_button',
        defaults.showFloatingButton,
      ),
      floatingButtonIdleCapsule: _readBool(
        v,
        'overlay_button_idle_capsule',
        defaults.floatingButtonIdleCapsule,
      ),
      // 'floating_button_size' is intentionally not read — removed in issue 11.
      // Old configs may have it; the key is silently ignored (no migration needed).
      overlayShowLiveTranscript: _readBool(
        v,
        'overlay_show_live_transcript',
        defaults.overlayShowLiveTranscript,
      ),
      overlayQuietHint: _readBool(
        v,
        'overlay_quiet_hint',
        defaults.overlayQuietHint,
      ),
    );
  }

  Map<String, String> toMap() => {
    'show_overlay': '$showOverlay',
    'overlay_mode': overlayMode,
    'overlay_start_position': overlayStartPosition,
    'overlay_size': overlaySize,
    'overlay_background': overlayBackground,
    'overlay_wave': overlayWave,
    'overlay_form': overlayForm,
    'overlay_wave_style': overlayWaveStyle,
    'overlay_wave_fluid': '$overlayWaveFluid',
    'overlay_show_timer': '$overlayShowTimer',
    'overlay_show_cancel': '$overlayShowCancel',
    'overlay_opacity': overlayOpacity,
    'overlay_button_size': floatingButtonSize,
    'overlay_button_shape': floatingButtonShape,
    'overlay_button_ring': '$floatingButtonRing',
    'overlay_button_idle_opacity': floatingButtonIdleOpacity,
    'show_floating_button': '$showFloatingButton',
    'overlay_button_idle_capsule': '$floatingButtonIdleCapsule',
    'overlay_show_live_transcript': '$overlayShowLiveTranscript',
    'overlay_quiet_hint': '$overlayQuietHint',
  };

  // loam-ignore: complexity-hotspots – one `??` per field, no logic.
  OverlaySettings copyWith({
    bool? showOverlay,
    String? overlayMode,
    String? overlayStartPosition,
    String? overlaySize,
    String? overlayBackground,
    String? overlayWave,
    String? overlayForm,
    String? overlayWaveStyle,
    bool? overlayWaveFluid,
    bool? overlayShowTimer,
    bool? overlayShowCancel,
    String? overlayOpacity,
    String? floatingButtonSize,
    String? floatingButtonShape,
    bool? floatingButtonRing,
    String? floatingButtonIdleOpacity,
    bool? showFloatingButton,
    bool? floatingButtonIdleCapsule,
    bool? overlayShowLiveTranscript,
    bool? overlayQuietHint,
  }) => OverlaySettings(
    floatingButtonIdleCapsule:
        floatingButtonIdleCapsule ?? this.floatingButtonIdleCapsule,
    showOverlay: showOverlay ?? this.showOverlay,
    overlayMode: overlayMode ?? this.overlayMode,
    overlayStartPosition: overlayStartPosition ?? this.overlayStartPosition,
    overlaySize: overlaySize ?? this.overlaySize,
    overlayBackground: overlayBackground ?? this.overlayBackground,
    overlayWave: overlayWave ?? this.overlayWave,
    overlayForm: overlayForm ?? this.overlayForm,
    overlayWaveStyle: overlayWaveStyle ?? this.overlayWaveStyle,
    overlayWaveFluid: overlayWaveFluid ?? this.overlayWaveFluid,
    overlayShowTimer: overlayShowTimer ?? this.overlayShowTimer,
    overlayShowCancel: overlayShowCancel ?? this.overlayShowCancel,
    overlayOpacity: overlayOpacity ?? this.overlayOpacity,
    floatingButtonSize: floatingButtonSize ?? this.floatingButtonSize,
    floatingButtonShape: floatingButtonShape ?? this.floatingButtonShape,
    floatingButtonRing: floatingButtonRing ?? this.floatingButtonRing,
    floatingButtonIdleOpacity:
        floatingButtonIdleOpacity ?? this.floatingButtonIdleOpacity,
    showFloatingButton: showFloatingButton ?? this.showFloatingButton,
    overlayShowLiveTranscript:
        overlayShowLiveTranscript ?? this.overlayShowLiveTranscript,
    overlayQuietHint: overlayQuietHint ?? this.overlayQuietHint,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlaySettings &&
          showOverlay == other.showOverlay &&
          overlayMode == other.overlayMode &&
          overlayStartPosition == other.overlayStartPosition &&
          overlaySize == other.overlaySize &&
          overlayBackground == other.overlayBackground &&
          overlayWave == other.overlayWave &&
          overlayForm == other.overlayForm &&
          overlayWaveStyle == other.overlayWaveStyle &&
          overlayWaveFluid == other.overlayWaveFluid &&
          overlayShowTimer == other.overlayShowTimer &&
          overlayShowCancel == other.overlayShowCancel &&
          overlayOpacity == other.overlayOpacity &&
          floatingButtonSize == other.floatingButtonSize &&
          floatingButtonShape == other.floatingButtonShape &&
          floatingButtonRing == other.floatingButtonRing &&
          floatingButtonIdleOpacity == other.floatingButtonIdleOpacity &&
          showFloatingButton == other.showFloatingButton &&
          floatingButtonIdleCapsule == other.floatingButtonIdleCapsule &&
          overlayShowLiveTranscript == other.overlayShowLiveTranscript &&
          overlayQuietHint == other.overlayQuietHint;

  @override
  int get hashCode => Object.hash(
    showOverlay,
    overlayMode,
    overlayStartPosition,
    overlaySize,
    overlayBackground,
    overlayWave,
    overlayForm,
    overlayWaveStyle,
    overlayWaveFluid,
    overlayShowTimer,
    overlayShowCancel,
    overlayOpacity,
    floatingButtonSize,
    floatingButtonShape,
    floatingButtonRing,
    floatingButtonIdleOpacity,
    showFloatingButton,
    floatingButtonIdleCapsule,
    overlayShowLiveTranscript,
    overlayQuietHint,
  );
}

// ===========================================================================
// Section 8 — Cloud Provider
// ===========================================================================

class CloudProviderSettings {
  const CloudProviderSettings({
    this.openAiApiKey = '',
    this.deepgramApiKey = '',
    this.cloudSttProvider = 'openai',
    this.customEndpointUrl = '',
    this.customEndpointApiKey = '',
    this.customEndpointSttModel = '',
    this.customEndpointSmartModel = '',
  });

  // API keys are stored in secure storage — never persisted to SQLite.
  final String openAiApiKey;
  final String deepgramApiKey;
  final String cloudSttProvider;

  /// Own OpenAI-compatible server (W-M3): base address, e.g. `http://localhost:1234/v1`.
  final String customEndpointUrl;

  /// Optional key of that server; secure storage like the other keys.
  final String customEndpointApiKey;

  /// Model names for transcription and for Smart Mode on that server.
  final String customEndpointSttModel;
  final String customEndpointSmartModel;

  static const CloudProviderSettings defaults = CloudProviderSettings();

  factory CloudProviderSettings.fromMap(
    Map<String, String> v,
  ) => CloudProviderSettings(
    openAiApiKey: v['openai_api_key'] ?? defaults.openAiApiKey,
    deepgramApiKey: v['deepgram_api_key'] ?? defaults.deepgramApiKey,
    cloudSttProvider: v['cloud_stt_provider'] ?? defaults.cloudSttProvider,
    customEndpointUrl: v['custom_endpoint_url'] ?? defaults.customEndpointUrl,
    customEndpointApiKey:
        v['custom_endpoint_api_key'] ?? defaults.customEndpointApiKey,
    customEndpointSttModel:
        v['custom_endpoint_stt_model'] ?? defaults.customEndpointSttModel,
    customEndpointSmartModel:
        v['custom_endpoint_smart_model'] ?? defaults.customEndpointSmartModel,
  );

  Map<String, String> toMap() => {
    // API keys are stored in secure storage — always write empty string.
    'openai_api_key': '',
    'deepgram_api_key': '',
    'cloud_stt_provider': cloudSttProvider,
    'custom_endpoint_url': customEndpointUrl,
    'custom_endpoint_api_key': '',
    'custom_endpoint_stt_model': customEndpointSttModel,
    'custom_endpoint_smart_model': customEndpointSmartModel,
  };

  CloudProviderSettings copyWith({
    String? openAiApiKey,
    String? deepgramApiKey,
    String? cloudSttProvider,
    String? customEndpointUrl,
    String? customEndpointApiKey,
    String? customEndpointSttModel,
    String? customEndpointSmartModel,
  }) => CloudProviderSettings(
    openAiApiKey: openAiApiKey ?? this.openAiApiKey,
    deepgramApiKey: deepgramApiKey ?? this.deepgramApiKey,
    cloudSttProvider: cloudSttProvider ?? this.cloudSttProvider,
    customEndpointUrl: customEndpointUrl ?? this.customEndpointUrl,
    customEndpointApiKey: customEndpointApiKey ?? this.customEndpointApiKey,
    customEndpointSttModel:
        customEndpointSttModel ?? this.customEndpointSttModel,
    customEndpointSmartModel:
        customEndpointSmartModel ?? this.customEndpointSmartModel,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudProviderSettings &&
          openAiApiKey == other.openAiApiKey &&
          deepgramApiKey == other.deepgramApiKey &&
          cloudSttProvider == other.cloudSttProvider &&
          customEndpointUrl == other.customEndpointUrl &&
          customEndpointApiKey == other.customEndpointApiKey &&
          customEndpointSttModel == other.customEndpointSttModel &&
          customEndpointSmartModel == other.customEndpointSmartModel;

  @override
  int get hashCode => Object.hash(
    openAiApiKey,
    deepgramApiKey,
    cloudSttProvider,
    customEndpointUrl,
    customEndpointApiKey,
    customEndpointSttModel,
    customEndpointSmartModel,
  );
}

// ===========================================================================
// Section 9 — Behavior
// ===========================================================================

class BehaviorSettings {
  const BehaviorSettings({
    this.maxRecordDuration = 120,
    this.closeToTray = true,
    this.errorReporting = true,
    this.gpuAcceleration = 'auto',
    this.autoPasteDelay = 200,
    this.autoPasteBlocklist = '',
    this.textReplacementsEnabled = true,
    this.termSimilarityEnabled = true,
    this.replacementsCascade = true,
    this.snippetPickerTrigger = '',
    this.correctionLearningEnabled = true,
    this.cudaAcceleration = true,
    this.copyBlockedToClipboard = true,
    this.autoSendOnRelease = false,
    this.linuxAlwaysShiftPaste = false,
    this.restoreClipboardAfterPaste = true,
    this.restoreClipboardWithoutReceipt = false,
    this.fitDictationStart = true,
    this.pasteWithMarkdown = false,
    this.cudaEulaAccepted = '',
    this.repasteHotkeyEnabled = false,
    this.repasteHotkeyKey = 'V',
    this.repasteHotkeyKeyDisplay = '',
    this.repasteHotkeyModifiers = 'alt+shift',
    this.learnCorrectionHotkeyEnabled = false,
    this.learnCorrectionHotkeyKey = 'L',
    this.learnCorrectionHotkeyKeyDisplay = '',
    this.learnCorrectionHotkeyModifiers = 'alt+shift',
  });

  final int maxRecordDuration;
  final bool closeToTray;
  final bool errorReporting;
  final String gpuAcceleration;
  final int autoPasteDelay;

  /// Comma-separated list of app bundle IDs (macOS) or process names (Windows)
  /// where auto-paste should be suppressed.
  final String autoPasteBlocklist;

  final bool textReplacementsEnabled;

  /// Strict similarity matching of dictionary terms (#147): a recognised word
  /// at least 92 % similar to a term is corrected to the term. Only runs for
  /// engines without a prompt hint (`TermHintEffect.replacementOnly`); an
  /// engine with a hint channel never uses it. Default on.
  final bool termSimilarityEnabled;

  /// Whether replacements build on each other (issue #1004): on, each rule
  /// works on the text the rules above it produced (the cascade, list
  /// order); off, every rule only matches the dictated original.
  final bool replacementsCascade;

  /// The single global trigger word that opens the Snippet-Picker when a
  /// transcript matches it exactly (dictation-automations ticket 06). Empty
  /// string means the feature is off — the picker has exactly one trigger,
  /// no payload, and its own UI on the Snippets page.
  final String snippetPickerTrigger;

  /// Global on/off switch for learning from corrections (issue #144):
  /// whether repeated corrections are watched for candidate replacements
  /// and terms at all.
  /// Default on -- but every candidate still requires explicit confirmation
  /// in the review UI before it becomes an active replacement, so "on" here
  /// only means "detect", never "auto-apply". Turning this off stops new
  /// candidates from being observed; it never touches already-learned
  /// entries or pending candidates.
  final bool correctionLearningEnabled;

  /// Whether an installed optional CUDA pack (see `cuda_pack.dart`) is used
  /// for on-device Whisper. Default on: installing the pack is the opt-in,
  /// this switch lets the user (or the GPU-load crash recovery) fall back to
  /// Vulkan without deleting the download. No effect without an installed
  /// pack or with `gpuAcceleration` set to CPU only.
  final bool cudaAcceleration;

  /// When a block-listed target blocks auto-paste, still copy the transcript
  /// to the clipboard (true, default) or leave the clipboard untouched; the
  /// transcript is then only kept in the history (AUF-1, maintainer 4a+c).
  final bool copyBlockedToClipboard;

  /// Opt-in (#564, off by default): holding the one fixed extra key (Alt /
  /// Option) while releasing the recording shortcut sends Enter after a
  /// confirmed paste.
  final bool autoSendOnRelease;

  /// Linux only (V1 Wayland): paste and copy with Ctrl+Shift+V/C everywhere,
  /// not only in recognised terminals. The fallback for sessions where the
  /// target app cannot be named (GNOME without the WhisPaste extension, an
  /// unsupported compositor, Flatpak without the compositor socket). Off by
  /// default: some apps bind Ctrl+Shift+V to something else (LibreOffice
  /// opens Paste Special).
  final bool linuxAlwaysShiftPaste;

  /// After a paste, put the user's previous clipboard content back (true,
  /// default) or keep the dictation on the clipboard (false). Only applies
  /// when the paste is confirmed or cannot be confirmed; a receipt timeout
  /// always keeps the transcript.
  final bool restoreClipboardAfterPaste;

  /// Legacy switch (W-E1): after a paste whose read receipt timed out, put the
  /// previous clipboard back after the fixed wait, as the previous release did.
  /// Only with [restoreClipboardAfterPaste]. New installs keep it off; an
  /// install that finished onboarding before W-E1 is switched on once
  /// (`settings_provider.dart`, `kPasteRestoreLegacyMigrationKey`).
  final bool restoreClipboardWithoutReceipt;

  /// Fits the first letter of a dictation and the gap to the text in front of
  /// the caret (#401). Has no effect in the Mac App Store build, whose sandbox
  /// cannot read other apps' fields.
  final bool fitDictationStart;

  /// Off by default (#644): a snippet (picker, side panel, automation API,
  /// interactive snippet) or a transcript picked in the side panel is pasted
  /// into another app as plain text with its Markdown markers removed
  /// (`markdownToPlainText`). On, the text is pasted exactly as written. The
  /// dictation hotkey path never converts.
  final bool pasteWithMarkdown;

  /// The consent value (pack version + EULA version, see
  /// `cudaEulaConsentValue` in `cuda_pack.dart`) the user accepted the NVIDIA
  /// CUDA EULA for. Empty = never accepted. Per installation: deny-listed in
  /// the settings export, so it never travels to another machine.
  final String cudaEulaAccepted;

  /// Off by default: the "paste the last dictation again" hotkey claims a
  /// system-wide shortcut only after the user opts in. It pastes into the
  /// app in front, through the same paster as a dictation.
  final bool repasteHotkeyEnabled;

  /// Storage token, display label and modifiers of that hotkey (see
  /// [HotkeySettings.hotkeyKey]). The modifiers default per platform
  /// ([defaultRepasteHotkeyModifiers]).
  final String repasteHotkeyKey;
  final String repasteHotkeyKeyDisplay;
  final String repasteHotkeyModifiers;

  /// Off by default, like the repaste hotkey: "Learn correction" (#934)
  /// copies the selection in the app in front and proposes it as a
  /// replacement for the matching words of the last dictation.
  final bool learnCorrectionHotkeyEnabled;

  /// Storage token, display label and modifiers of that hotkey; the
  /// modifiers default per platform ([defaultRepasteHotkeyModifiers]).
  final String learnCorrectionHotkeyKey;
  final String learnCorrectionHotkeyKeyDisplay;
  final String learnCorrectionHotkeyModifiers;

  static const BehaviorSettings defaults = BehaviorSettings();

  factory BehaviorSettings.fromMap(Map<String, String> v) => BehaviorSettings(
    maxRecordDuration: _readInt(
      v,
      'max_record_duration',
      defaults.maxRecordDuration,
    ),
    closeToTray: _readBool(v, 'close_to_tray', defaults.closeToTray),
    errorReporting: _readBool(v, 'error_reporting', defaults.errorReporting),
    gpuAcceleration: v['gpu_acceleration'] ?? defaults.gpuAcceleration,
    autoPasteDelay: _readInt(v, 'auto_paste_delay', defaults.autoPasteDelay),
    autoPasteBlocklist:
        v['auto_paste_blocklist'] ?? defaults.autoPasteBlocklist,
    textReplacementsEnabled: _readBool(
      v,
      'text_replacements_enabled',
      defaults.textReplacementsEnabled,
    ),
    termSimilarityEnabled: _readBool(
      v,
      'term_similarity_enabled',
      defaults.termSimilarityEnabled,
    ),
    replacementsCascade: _readBool(
      v,
      'text_replacements_cascade',
      defaults.replacementsCascade,
    ),
    snippetPickerTrigger:
        v['snippet_picker_trigger'] ?? defaults.snippetPickerTrigger,
    correctionLearningEnabled: _readBool(
      v,
      'correction_learning_enabled',
      defaults.correctionLearningEnabled,
    ),
    cudaAcceleration: _readBool(
      v,
      'cuda_acceleration',
      defaults.cudaAcceleration,
    ),
    copyBlockedToClipboard: _readBool(
      v,
      'copy_blocked_to_clipboard',
      defaults.copyBlockedToClipboard,
    ),
    autoSendOnRelease: _readBool(
      v,
      'auto_send_on_release',
      defaults.autoSendOnRelease,
    ),
    linuxAlwaysShiftPaste: _readBool(
      v,
      'linux_always_shift_paste',
      defaults.linuxAlwaysShiftPaste,
    ),
    restoreClipboardAfterPaste: _readBool(
      v,
      'restore_clipboard_after_paste',
      defaults.restoreClipboardAfterPaste,
    ),
    restoreClipboardWithoutReceipt: _readBool(
      v,
      'restore_clipboard_without_receipt',
      defaults.restoreClipboardWithoutReceipt,
    ),
    fitDictationStart: _readBool(
      v,
      'fit_dictation_start',
      defaults.fitDictationStart,
    ),
    pasteWithMarkdown: _readBool(
      v,
      'paste_with_markdown',
      defaults.pasteWithMarkdown,
    ),
    cudaEulaAccepted: v['cuda_eula_accepted'] ?? defaults.cudaEulaAccepted,
    repasteHotkeyEnabled: _readBool(
      v,
      'repaste_hotkey_enabled',
      defaults.repasteHotkeyEnabled,
    ),
    repasteHotkeyKey: v['repaste_hotkey_key'] ?? defaults.repasteHotkeyKey,
    repasteHotkeyKeyDisplay:
        v['repaste_hotkey_key_display'] ?? defaults.repasteHotkeyKeyDisplay,
    repasteHotkeyModifiers:
        v['repaste_hotkey_modifiers'] ?? defaultRepasteHotkeyModifiers(),
    learnCorrectionHotkeyEnabled: _readBool(
      v,
      'learn_correction_hotkey_enabled',
      defaults.learnCorrectionHotkeyEnabled,
    ),
    learnCorrectionHotkeyKey:
        v['learn_correction_hotkey_key'] ?? defaults.learnCorrectionHotkeyKey,
    learnCorrectionHotkeyKeyDisplay:
        v['learn_correction_hotkey_key_display'] ??
        defaults.learnCorrectionHotkeyKeyDisplay,
    learnCorrectionHotkeyModifiers:
        v['learn_correction_hotkey_modifiers'] ??
        defaultRepasteHotkeyModifiers(),
  );

  Map<String, String> toMap() => {
    'max_record_duration': '$maxRecordDuration',
    'close_to_tray': '$closeToTray',
    'error_reporting': '$errorReporting',
    'gpu_acceleration': gpuAcceleration,
    'auto_paste_delay': '$autoPasteDelay',
    'auto_paste_blocklist': autoPasteBlocklist,
    'text_replacements_enabled': '$textReplacementsEnabled',
    'term_similarity_enabled': '$termSimilarityEnabled',
    'text_replacements_cascade': '$replacementsCascade',
    'snippet_picker_trigger': snippetPickerTrigger,
    'correction_learning_enabled': '$correctionLearningEnabled',
    'cuda_acceleration': '$cudaAcceleration',
    'copy_blocked_to_clipboard': '$copyBlockedToClipboard',
    'auto_send_on_release': '$autoSendOnRelease',
    'linux_always_shift_paste': '$linuxAlwaysShiftPaste',
    'restore_clipboard_after_paste': '$restoreClipboardAfterPaste',
    'restore_clipboard_without_receipt': '$restoreClipboardWithoutReceipt',
    'fit_dictation_start': '$fitDictationStart',
    'paste_with_markdown': '$pasteWithMarkdown',
    'cuda_eula_accepted': cudaEulaAccepted,
    'repaste_hotkey_enabled': '$repasteHotkeyEnabled',
    'repaste_hotkey_key': repasteHotkeyKey,
    'repaste_hotkey_key_display': repasteHotkeyKeyDisplay,
    'repaste_hotkey_modifiers': repasteHotkeyModifiers,
    'learn_correction_hotkey_enabled': '$learnCorrectionHotkeyEnabled',
    'learn_correction_hotkey_key': learnCorrectionHotkeyKey,
    'learn_correction_hotkey_key_display': learnCorrectionHotkeyKeyDisplay,
    'learn_correction_hotkey_modifiers': learnCorrectionHotkeyModifiers,
  };

  BehaviorSettings copyWith({
    int? maxRecordDuration,
    bool? closeToTray,
    bool? errorReporting,
    String? gpuAcceleration,
    int? autoPasteDelay,
    String? autoPasteBlocklist,
    bool? textReplacementsEnabled,
    bool? termSimilarityEnabled,
    bool? replacementsCascade,
    String? snippetPickerTrigger,
    bool? correctionLearningEnabled,
    bool? cudaAcceleration,
    bool? copyBlockedToClipboard,
    bool? autoSendOnRelease,
    bool? linuxAlwaysShiftPaste,
    bool? restoreClipboardAfterPaste,
    bool? restoreClipboardWithoutReceipt,
    bool? fitDictationStart,
    bool? pasteWithMarkdown,
    String? cudaEulaAccepted,
    bool? repasteHotkeyEnabled,
    String? repasteHotkeyKey,
    String? repasteHotkeyKeyDisplay,
    String? repasteHotkeyModifiers,
    bool? learnCorrectionHotkeyEnabled,
    String? learnCorrectionHotkeyKey,
    String? learnCorrectionHotkeyKeyDisplay,
    String? learnCorrectionHotkeyModifiers,
  }) => BehaviorSettings(
    maxRecordDuration: maxRecordDuration ?? this.maxRecordDuration,
    closeToTray: closeToTray ?? this.closeToTray,
    errorReporting: errorReporting ?? this.errorReporting,
    gpuAcceleration: gpuAcceleration ?? this.gpuAcceleration,
    autoPasteDelay: autoPasteDelay ?? this.autoPasteDelay,
    autoPasteBlocklist: autoPasteBlocklist ?? this.autoPasteBlocklist,
    textReplacementsEnabled:
        textReplacementsEnabled ?? this.textReplacementsEnabled,
    termSimilarityEnabled: termSimilarityEnabled ?? this.termSimilarityEnabled,
    replacementsCascade: replacementsCascade ?? this.replacementsCascade,
    snippetPickerTrigger: snippetPickerTrigger ?? this.snippetPickerTrigger,
    correctionLearningEnabled:
        correctionLearningEnabled ?? this.correctionLearningEnabled,
    cudaAcceleration: cudaAcceleration ?? this.cudaAcceleration,
    copyBlockedToClipboard:
        copyBlockedToClipboard ?? this.copyBlockedToClipboard,
    autoSendOnRelease: autoSendOnRelease ?? this.autoSendOnRelease,
    linuxAlwaysShiftPaste: linuxAlwaysShiftPaste ?? this.linuxAlwaysShiftPaste,
    restoreClipboardAfterPaste:
        restoreClipboardAfterPaste ?? this.restoreClipboardAfterPaste,
    restoreClipboardWithoutReceipt:
        restoreClipboardWithoutReceipt ?? this.restoreClipboardWithoutReceipt,
    fitDictationStart: fitDictationStart ?? this.fitDictationStart,
    pasteWithMarkdown: pasteWithMarkdown ?? this.pasteWithMarkdown,
    cudaEulaAccepted: cudaEulaAccepted ?? this.cudaEulaAccepted,
    repasteHotkeyEnabled: repasteHotkeyEnabled ?? this.repasteHotkeyEnabled,
    repasteHotkeyKey: repasteHotkeyKey ?? this.repasteHotkeyKey,
    repasteHotkeyKeyDisplay:
        repasteHotkeyKeyDisplay ?? this.repasteHotkeyKeyDisplay,
    repasteHotkeyModifiers:
        repasteHotkeyModifiers ?? this.repasteHotkeyModifiers,
    learnCorrectionHotkeyEnabled:
        learnCorrectionHotkeyEnabled ?? this.learnCorrectionHotkeyEnabled,
    learnCorrectionHotkeyKey:
        learnCorrectionHotkeyKey ?? this.learnCorrectionHotkeyKey,
    learnCorrectionHotkeyKeyDisplay:
        learnCorrectionHotkeyKeyDisplay ?? this.learnCorrectionHotkeyKeyDisplay,
    learnCorrectionHotkeyModifiers:
        learnCorrectionHotkeyModifiers ?? this.learnCorrectionHotkeyModifiers,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BehaviorSettings) return false;
    return maxRecordDuration == other.maxRecordDuration &&
        closeToTray == other.closeToTray &&
        errorReporting == other.errorReporting &&
        gpuAcceleration == other.gpuAcceleration &&
        autoPasteDelay == other.autoPasteDelay &&
        autoPasteBlocklist == other.autoPasteBlocklist &&
        textReplacementsEnabled == other.textReplacementsEnabled &&
        termSimilarityEnabled == other.termSimilarityEnabled &&
        replacementsCascade == other.replacementsCascade &&
        snippetPickerTrigger == other.snippetPickerTrigger &&
        correctionLearningEnabled == other.correctionLearningEnabled &&
        cudaAcceleration == other.cudaAcceleration &&
        copyBlockedToClipboard == other.copyBlockedToClipboard &&
        autoSendOnRelease == other.autoSendOnRelease &&
        linuxAlwaysShiftPaste == other.linuxAlwaysShiftPaste &&
        restoreClipboardAfterPaste == other.restoreClipboardAfterPaste &&
        restoreClipboardWithoutReceipt ==
            other.restoreClipboardWithoutReceipt &&
        fitDictationStart == other.fitDictationStart &&
        pasteWithMarkdown == other.pasteWithMarkdown &&
        cudaEulaAccepted == other.cudaEulaAccepted &&
        repasteHotkeyEnabled == other.repasteHotkeyEnabled &&
        repasteHotkeyKey == other.repasteHotkeyKey &&
        repasteHotkeyKeyDisplay == other.repasteHotkeyKeyDisplay &&
        repasteHotkeyModifiers == other.repasteHotkeyModifiers &&
        learnCorrectionHotkeyEnabled == other.learnCorrectionHotkeyEnabled &&
        learnCorrectionHotkeyKey == other.learnCorrectionHotkeyKey &&
        learnCorrectionHotkeyKeyDisplay ==
            other.learnCorrectionHotkeyKeyDisplay &&
        learnCorrectionHotkeyModifiers == other.learnCorrectionHotkeyModifiers;
  }

  @override
  int get hashCode => Object.hash(
    maxRecordDuration,
    closeToTray,
    errorReporting,
    gpuAcceleration,
    autoPasteDelay,
    autoPasteBlocklist,
    textReplacementsEnabled,
    replacementsCascade,
    snippetPickerTrigger,
    correctionLearningEnabled,
    cudaAcceleration,
    copyBlockedToClipboard,
    autoSendOnRelease,
    linuxAlwaysShiftPaste,
    restoreClipboardAfterPaste,
    restoreClipboardWithoutReceipt,
    // Object.hash takes at most 20 values: grouped with its neighbour.
    Object.hash(fitDictationStart, pasteWithMarkdown, termSimilarityEnabled),
    cudaEulaAccepted,
    // Object.hash takes at most 20 values: the hotkeys hash as one.
    Object.hash(
      repasteHotkeyEnabled,
      repasteHotkeyKey,
      repasteHotkeyKeyDisplay,
      repasteHotkeyModifiers,
    ),
    Object.hash(
      learnCorrectionHotkeyEnabled,
      learnCorrectionHotkeyKey,
      learnCorrectionHotkeyKeyDisplay,
      learnCorrectionHotkeyModifiers,
    ),
  );
}

// ===========================================================================
// Section 10 — Audio Processing
// ===========================================================================

class AudioProcessingSettings {
  const AudioProcessingSettings();

  factory AudioProcessingSettings.fromMap(Map<String, String> _) =>
      const AudioProcessingSettings();

  Map<String, String> toMap() => const <String, String>{};

  AudioProcessingSettings copyWith() => const AudioProcessingSettings();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioProcessingSettings;

  @override
  int get hashCode => 0;
}

// ===========================================================================
// Section 11 — Updates
// ===========================================================================

class UpdateSettings {
  const UpdateSettings({this.checkUpdates = true});

  final bool checkUpdates;

  static const UpdateSettings defaults = UpdateSettings();

  factory UpdateSettings.fromMap(Map<String, String> v) => UpdateSettings(
    checkUpdates: _readBool(v, 'check_updates', defaults.checkUpdates),
  );

  Map<String, String> toMap() => {'check_updates': '$checkUpdates'};

  UpdateSettings copyWith({bool? checkUpdates}) =>
      UpdateSettings(checkUpdates: checkUpdates ?? this.checkUpdates);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateSettings && checkUpdates == other.checkUpdates;

  @override
  int get hashCode => checkUpdates.hashCode;
}

// ===========================================================================
// Section 12 — History
// ===========================================================================

class HistorySettings {
  const HistorySettings({
    this.saveHistory = true,
    this.historyMaxEntries = 1000,
    this.historyAutoTrashDays = 90,
    this.historyHideOnOpen = false,
    this.historyPin = '',
    this.historyPinFailedAttempts = 0,
    this.historyPinLockedUntil = 0,
    this.historyAutoLockMinutes = 0,
  });

  /// Whether a dictation is written to Recordings (the history). Off: the
  /// text is only pasted or copied, no entry and no audio is kept, and the
  /// rating count runs on its own content-free counter. Existing entries are
  /// not touched by switching it off.
  final bool saveHistory;

  /// Max active (non-trashed) history entries to keep. 0 = unlimited.
  final int historyMaxEntries;

  /// Days to keep soft-deleted entries before permanent purge. 0 = never purge.
  final int historyAutoTrashDays;

  /// Hide the History page behind a "Show history" button each time the app
  /// starts or its window is hidden, so a shared computer never opens
  /// straight into past transcripts.
  final bool historyHideOnOpen;

  /// Salted PBKDF2 hash of the History PIN (`history_pin.dart`); empty = no
  /// PIN. Never portable.
  final String historyPin;

  /// Consecutive wrong PINs, persisted so a restart does not reset the
  /// throttle. Never portable.
  final int historyPinFailedAttempts;

  /// Epoch milliseconds until which unlocking is refused; 0 = not locked out.
  /// Never portable.
  final int historyPinLockedUntil;

  /// Conceal the revealed history again after this many minutes without
  /// activity. 0 = never.
  final int historyAutoLockMinutes;

  static const HistorySettings defaults = HistorySettings();

  factory HistorySettings.fromMap(Map<String, String> v) => HistorySettings(
    saveHistory: _readBool(v, 'history_save_enabled', defaults.saveHistory),
    historyMaxEntries: _readInt(
      v,
      'history_max_entries',
      defaults.historyMaxEntries,
    ),
    historyAutoTrashDays: _readInt(
      v,
      'history_auto_trash_days',
      defaults.historyAutoTrashDays,
    ),
    historyHideOnOpen: _readBool(
      v,
      'history_hide_on_open',
      defaults.historyHideOnOpen,
    ),
    historyPin: v['history_pin'] ?? defaults.historyPin,
    historyPinFailedAttempts: _readInt(
      v,
      'history_pin_failed_attempts',
      defaults.historyPinFailedAttempts,
    ),
    historyPinLockedUntil: _readInt(
      v,
      'history_pin_locked_until',
      defaults.historyPinLockedUntil,
    ),
    historyAutoLockMinutes: _readInt(
      v,
      'history_auto_lock_minutes',
      defaults.historyAutoLockMinutes,
    ),
  );

  Map<String, String> toMap() => {
    'history_save_enabled': '$saveHistory',
    'history_max_entries': '$historyMaxEntries',
    'history_auto_trash_days': '$historyAutoTrashDays',
    'history_hide_on_open': '$historyHideOnOpen',
    'history_pin': historyPin,
    'history_pin_failed_attempts': '$historyPinFailedAttempts',
    'history_pin_locked_until': '$historyPinLockedUntil',
    'history_auto_lock_minutes': '$historyAutoLockMinutes',
  };

  HistorySettings copyWith({
    bool? saveHistory,
    int? historyMaxEntries,
    int? historyAutoTrashDays,
    bool? historyHideOnOpen,
    String? historyPin,
    int? historyPinFailedAttempts,
    int? historyPinLockedUntil,
    int? historyAutoLockMinutes,
  }) => HistorySettings(
    saveHistory: saveHistory ?? this.saveHistory,
    historyMaxEntries: historyMaxEntries ?? this.historyMaxEntries,
    historyAutoTrashDays: historyAutoTrashDays ?? this.historyAutoTrashDays,
    historyHideOnOpen: historyHideOnOpen ?? this.historyHideOnOpen,
    historyPin: historyPin ?? this.historyPin,
    historyPinFailedAttempts:
        historyPinFailedAttempts ?? this.historyPinFailedAttempts,
    historyPinLockedUntil: historyPinLockedUntil ?? this.historyPinLockedUntil,
    historyAutoLockMinutes:
        historyAutoLockMinutes ?? this.historyAutoLockMinutes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistorySettings &&
          saveHistory == other.saveHistory &&
          historyMaxEntries == other.historyMaxEntries &&
          historyAutoTrashDays == other.historyAutoTrashDays &&
          historyHideOnOpen == other.historyHideOnOpen &&
          historyPin == other.historyPin &&
          historyPinFailedAttempts == other.historyPinFailedAttempts &&
          historyPinLockedUntil == other.historyPinLockedUntil &&
          historyAutoLockMinutes == other.historyAutoLockMinutes;

  @override
  int get hashCode => Object.hash(
    saveHistory,
    historyMaxEntries,
    historyAutoTrashDays,
    historyHideOnOpen,
    historyPin,
    historyPinFailedAttempts,
    historyPinLockedUntil,
    historyAutoLockMinutes,
  );
}

// ===========================================================================
// Section 13 — Hotkey
// ===========================================================================

/// Modifier-only hotkeys a user can choose instead of a key combination.
/// Stored as the names shared with the native hosts. Empty = no modifier-only
/// hotkey (the combination in [HotkeySettings.hotkeyKey] is used).
const modifierOnlyHotkeyChoices = [
  'fn',
  'leftShift',
  'rightShift',
  'leftControl',
  'rightControl',
  'leftAlt',
  'rightAlt',
  'leftMeta',
  'rightMeta',
];

/// Retired trigger keys of the model before 2026-10-25, when one action could
/// hold a hold key and a double-tap action at once. Nothing reads them any more
/// except [migrateLegacyHotkeyTriggers].
const legacyHotkeyTriggerKeys = {
  'hotkey_modifier_only',
  'double_tap_action',
  'double_tap_hands_free',
};

/// Moves the retired trigger values to the one-trigger model. Returns [raw]
/// with the legacy keys cleared and, when a legacy hold key can become the
/// double-tap trigger, `hotkey_double_tap_key` set to it.
///
/// - A hold key that [doubleTapObservable] accepts becomes the double-tap
///   trigger, unless a double-tap trigger is already stored.
/// - Otherwise the hold key is dropped and the stored combination stays.
/// - A legacy double-tap action is dropped. Quick note and snippet picker keep
///   their own combinations.
///
/// Only active values are cleared, so the result is idempotent: a load after
/// the migration writes nothing, and a trigger the user cleared later is never
/// restored from an old key. Used on load and on settings import.
Map<String, String> migrateLegacyHotkeyTriggers(
  Map<String, String> raw, {
  required bool Function(String choice) doubleTapObservable,
}) {
  final hold = raw['hotkey_modifier_only'] ?? '';
  final action = raw['double_tap_action'] ?? '';
  final handsFree = raw['double_tap_hands_free'] ?? '';
  final activeLegacy =
      hold.isNotEmpty ||
      (action.isNotEmpty && action != 'none') ||
      handsFree == 'true';
  if (!activeLegacy) return raw;

  final migrated = {...raw};
  for (final key in legacyHotkeyTriggerKeys) {
    if (migrated.containsKey(key)) migrated[key] = '';
  }
  final hasDoubleTap = (raw['hotkey_double_tap_key'] ?? '').isNotEmpty;
  if (hold.isNotEmpty &&
      !hasDoubleTap &&
      modifierOnlyHotkeyChoices.contains(hold) &&
      doubleTapObservable(hold)) {
    migrated['hotkey_double_tap_key'] = hold;
  }
  return migrated;
}

/// Reads a stored single-key choice; anything unknown or missing is none (`''`).
String _readModifierChoice(Map<String, String> v, String key) =>
    modifierOnlyHotkeyChoices.contains(v[key]) ? v[key]! : '';

class HotkeySettings {
  const HotkeySettings({
    this.hotkeyEnabled = true,
    this.hotkeyKey = 'D',
    this.hotkeyKeyDisplay = '',
    this.hotkeyModifiers = 'ctrl+shift',
    this.hotkeyDoubleTapKey = '',
    this.hotkeyDoubleTap = true,
  });

  /// Single key that is the dictation trigger (one of
  /// [modifierOnlyHotkeyChoices]), or empty when the dictation trigger is the
  /// key combination in [hotkeyKey]/[hotkeyModifiers]. Only one of the two is
  /// active at a time: an action has exactly one trigger. The stored name
  /// stems from the time the key could only be double-tapped; since
  /// 2026-10-30 it holds and double-taps like a combination.
  final String hotkeyDoubleTapKey;

  /// A double tap of the trigger (combination or single key) starts a
  /// hands-free recording; one press stops it. On for new installs; an
  /// existing install gets it written once (see
  /// `kHotkeyDoubleTapDefaultMigrationKey`).
  final bool hotkeyDoubleTap;

  final bool hotkeyEnabled;

  /// Canonical storage token for the non-modifier key — what `resolveKey`
  /// consumes (e.g. `'D'`, `'F1'`, `';'`).
  final String hotkeyKey;

  /// User-visible label for [hotkeyKey] as captured by the recorder. When
  /// empty, UI formatters fall back to [hotkeyKey]. Lets a DE-layout user
  /// who pressed `Ö` (physical position `semicolon`) see `Ö` in settings and
  /// status bar while the registrar still binds to the stable physical
  /// position via `hotkeyKey=';'`.
  final String hotkeyKeyDisplay;

  final String hotkeyModifiers;

  static const HotkeySettings defaults = HotkeySettings();

  factory HotkeySettings.fromMap(Map<String, String> v) => HotkeySettings(
    hotkeyEnabled: _readBool(v, 'hotkey_enabled', defaults.hotkeyEnabled),
    hotkeyKey: v['hotkey_key'] ?? defaults.hotkeyKey,
    hotkeyKeyDisplay: v['hotkey_key_display'] ?? defaults.hotkeyKeyDisplay,
    hotkeyModifiers:
        v['hotkey_modifiers'] ?? buildDefaultHotkeySettings().hotkeyModifiers,
    hotkeyDoubleTapKey: _readModifierChoice(v, 'hotkey_double_tap_key'),
    hotkeyDoubleTap: _readBool(
      v,
      'hotkey_double_tap',
      defaults.hotkeyDoubleTap,
    ),
  );

  Map<String, String> toMap() => {
    'hotkey_enabled': '$hotkeyEnabled',
    'hotkey_key': hotkeyKey,
    'hotkey_key_display': hotkeyKeyDisplay,
    'hotkey_modifiers': hotkeyModifiers,
    'hotkey_double_tap_key': hotkeyDoubleTapKey,
    'hotkey_double_tap': '$hotkeyDoubleTap',
  };

  HotkeySettings copyWith({
    bool? hotkeyEnabled,
    String? hotkeyKey,
    String? hotkeyKeyDisplay,
    String? hotkeyModifiers,
    String? hotkeyDoubleTapKey,
    bool? hotkeyDoubleTap,
  }) => HotkeySettings(
    hotkeyEnabled: hotkeyEnabled ?? this.hotkeyEnabled,
    hotkeyKey: hotkeyKey ?? this.hotkeyKey,
    hotkeyKeyDisplay: hotkeyKeyDisplay ?? this.hotkeyKeyDisplay,
    hotkeyModifiers: hotkeyModifiers ?? this.hotkeyModifiers,
    hotkeyDoubleTapKey: hotkeyDoubleTapKey ?? this.hotkeyDoubleTapKey,
    hotkeyDoubleTap: hotkeyDoubleTap ?? this.hotkeyDoubleTap,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotkeySettings &&
          hotkeyEnabled == other.hotkeyEnabled &&
          hotkeyKey == other.hotkeyKey &&
          hotkeyKeyDisplay == other.hotkeyKeyDisplay &&
          hotkeyModifiers == other.hotkeyModifiers &&
          hotkeyDoubleTapKey == other.hotkeyDoubleTapKey &&
          hotkeyDoubleTap == other.hotkeyDoubleTap;

  @override
  int get hashCode => Object.hash(
    hotkeyEnabled,
    hotkeyKey,
    hotkeyKeyDisplay,
    hotkeyModifiers,
    hotkeyDoubleTapKey,
    hotkeyDoubleTap,
  );
}

// ===========================================================================
// Section 13b — Quick-note hotkey
// ===========================================================================

/// Settings for the second, independently configurable global hotkey that
/// starts a recording targeting a quick note (ticket 20). Mirrors
/// [HotkeySettings] in shape; kept as its own section (rather than extending
/// [HotkeySettings]) so the existing hotkey's storage keys, defaults and
/// tests stay untouched.
class QuickNoteHotkeySettings {
  const QuickNoteHotkeySettings({
    this.quickNoteHotkeyEnabled = false,
    this.quickNoteHotkeyKey = 'N',
    this.quickNoteHotkeyKeyDisplay = '',
    this.quickNoteHotkeyModifiers = 'ctrl+shift',
    this.openNoteInMainWindow = false,
    this.timestampStyle = QuickNoteTimestampStyle.marginMark,
  });

  /// Off by default — an existing user must opt in, never gets a system-wide
  /// shortcut silently claimed by an update.
  final bool quickNoteHotkeyEnabled;

  /// When a quick note was saved: bring the main window forward and open the
  /// note in the Notizen area. Off by default: the note is saved in the
  /// background and a toast offers "Open note" (UIA-SHL-08).
  final bool openNoteInMainWindow;

  /// How each appended dictation is dated (#803). Margin mark by default:
  /// the note text stays clean, the moment lives in `note_appends`.
  final QuickNoteTimestampStyle timestampStyle;

  /// Canonical storage token for the non-modifier key, as consumed by
  /// `resolveKey` (see [HotkeySettings.hotkeyKey]).
  final String quickNoteHotkeyKey;

  /// User-visible label for [quickNoteHotkeyKey] (see
  /// [HotkeySettings.hotkeyKeyDisplay]).
  final String quickNoteHotkeyKeyDisplay;

  final String quickNoteHotkeyModifiers;

  static const QuickNoteHotkeySettings defaults = QuickNoteHotkeySettings();

  factory QuickNoteHotkeySettings.fromMap(Map<String, String> v) =>
      QuickNoteHotkeySettings(
        quickNoteHotkeyEnabled: _readBool(
          v,
          'quick_note_hotkey_enabled',
          defaults.quickNoteHotkeyEnabled,
        ),
        quickNoteHotkeyKey:
            v['quick_note_hotkey_key'] ?? defaults.quickNoteHotkeyKey,
        quickNoteHotkeyKeyDisplay:
            v['quick_note_hotkey_key_display'] ??
            defaults.quickNoteHotkeyKeyDisplay,
        quickNoteHotkeyModifiers:
            v['quick_note_hotkey_modifiers'] ??
            buildDefaultQuickNoteHotkeySettings().quickNoteHotkeyModifiers,
        openNoteInMainWindow: _readBool(
          v,
          'quick_note_open_in_main_window',
          defaults.openNoteInMainWindow,
        ),
        timestampStyle: QuickNoteTimestampStyle.fromValue(
          v['quick_note_timestamp_style'],
        ),
      );

  Map<String, String> toMap() => {
    'quick_note_hotkey_enabled': '$quickNoteHotkeyEnabled',
    'quick_note_hotkey_key': quickNoteHotkeyKey,
    'quick_note_hotkey_key_display': quickNoteHotkeyKeyDisplay,
    'quick_note_hotkey_modifiers': quickNoteHotkeyModifiers,
    'quick_note_open_in_main_window': '$openNoteInMainWindow',
    'quick_note_timestamp_style': timestampStyle.value,
  };

  QuickNoteHotkeySettings copyWith({
    bool? quickNoteHotkeyEnabled,
    String? quickNoteHotkeyKey,
    String? quickNoteHotkeyKeyDisplay,
    String? quickNoteHotkeyModifiers,
    bool? openNoteInMainWindow,
    QuickNoteTimestampStyle? timestampStyle,
  }) => QuickNoteHotkeySettings(
    quickNoteHotkeyEnabled:
        quickNoteHotkeyEnabled ?? this.quickNoteHotkeyEnabled,
    quickNoteHotkeyKey: quickNoteHotkeyKey ?? this.quickNoteHotkeyKey,
    quickNoteHotkeyKeyDisplay:
        quickNoteHotkeyKeyDisplay ?? this.quickNoteHotkeyKeyDisplay,
    quickNoteHotkeyModifiers:
        quickNoteHotkeyModifiers ?? this.quickNoteHotkeyModifiers,
    openNoteInMainWindow: openNoteInMainWindow ?? this.openNoteInMainWindow,
    timestampStyle: timestampStyle ?? this.timestampStyle,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuickNoteHotkeySettings &&
          quickNoteHotkeyEnabled == other.quickNoteHotkeyEnabled &&
          quickNoteHotkeyKey == other.quickNoteHotkeyKey &&
          quickNoteHotkeyKeyDisplay == other.quickNoteHotkeyKeyDisplay &&
          quickNoteHotkeyModifiers == other.quickNoteHotkeyModifiers &&
          openNoteInMainWindow == other.openNoteInMainWindow &&
          timestampStyle == other.timestampStyle;

  @override
  int get hashCode => Object.hash(
    quickNoteHotkeyEnabled,
    quickNoteHotkeyKey,
    quickNoteHotkeyKeyDisplay,
    quickNoteHotkeyModifiers,
    openNoteInMainWindow,
    timestampStyle,
  );
}

// ===========================================================================
// Section 13c — Snippet-Picker hotkey
// ===========================================================================

/// Settings for the third, independently configurable global hotkey that
/// opens the Snippet-Picker panel directly, without a recording (ticket 26).
/// Mirrors [QuickNoteHotkeySettings] in shape; kept as its own section (same
/// rationale as 13b) so the other two hotkeys' storage keys, defaults and
/// tests stay untouched.
class SnippetPickerHotkeySettings {
  const SnippetPickerHotkeySettings({
    this.snippetPickerHotkeyEnabled = false,
    this.snippetPickerHotkeyKey = 'E',
    this.snippetPickerHotkeyKeyDisplay = '',
    this.snippetPickerHotkeyModifiers = 'ctrl+shift',
  });

  /// Off by default — an existing user must opt in, never gets a system-wide
  /// shortcut silently claimed by an update.
  final bool snippetPickerHotkeyEnabled;

  /// Canonical storage token for the non-modifier key, as consumed by
  /// `resolveKey` (see [HotkeySettings.hotkeyKey]).
  final String snippetPickerHotkeyKey;

  /// User-visible label for [snippetPickerHotkeyKey] (see
  /// [HotkeySettings.hotkeyKeyDisplay]).
  final String snippetPickerHotkeyKeyDisplay;

  final String snippetPickerHotkeyModifiers;

  static const SnippetPickerHotkeySettings defaults =
      SnippetPickerHotkeySettings();

  factory SnippetPickerHotkeySettings.fromMap(
    Map<String, String> v,
  ) => SnippetPickerHotkeySettings(
    snippetPickerHotkeyEnabled: _readBool(
      v,
      'snippet_picker_hotkey_enabled',
      defaults.snippetPickerHotkeyEnabled,
    ),
    snippetPickerHotkeyKey:
        v['snippet_picker_hotkey_key'] ?? defaults.snippetPickerHotkeyKey,
    snippetPickerHotkeyKeyDisplay:
        v['snippet_picker_hotkey_key_display'] ??
        defaults.snippetPickerHotkeyKeyDisplay,
    snippetPickerHotkeyModifiers:
        v['snippet_picker_hotkey_modifiers'] ??
        buildDefaultSnippetPickerHotkeySettings().snippetPickerHotkeyModifiers,
  );

  Map<String, String> toMap() => {
    'snippet_picker_hotkey_enabled': '$snippetPickerHotkeyEnabled',
    'snippet_picker_hotkey_key': snippetPickerHotkeyKey,
    'snippet_picker_hotkey_key_display': snippetPickerHotkeyKeyDisplay,
    'snippet_picker_hotkey_modifiers': snippetPickerHotkeyModifiers,
  };

  SnippetPickerHotkeySettings copyWith({
    bool? snippetPickerHotkeyEnabled,
    String? snippetPickerHotkeyKey,
    String? snippetPickerHotkeyKeyDisplay,
    String? snippetPickerHotkeyModifiers,
  }) => SnippetPickerHotkeySettings(
    snippetPickerHotkeyEnabled:
        snippetPickerHotkeyEnabled ?? this.snippetPickerHotkeyEnabled,
    snippetPickerHotkeyKey:
        snippetPickerHotkeyKey ?? this.snippetPickerHotkeyKey,
    snippetPickerHotkeyKeyDisplay:
        snippetPickerHotkeyKeyDisplay ?? this.snippetPickerHotkeyKeyDisplay,
    snippetPickerHotkeyModifiers:
        snippetPickerHotkeyModifiers ?? this.snippetPickerHotkeyModifiers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnippetPickerHotkeySettings &&
          snippetPickerHotkeyEnabled == other.snippetPickerHotkeyEnabled &&
          snippetPickerHotkeyKey == other.snippetPickerHotkeyKey &&
          snippetPickerHotkeyKeyDisplay ==
              other.snippetPickerHotkeyKeyDisplay &&
          snippetPickerHotkeyModifiers == other.snippetPickerHotkeyModifiers;

  @override
  int get hashCode => Object.hash(
    snippetPickerHotkeyEnabled,
    snippetPickerHotkeyKey,
    snippetPickerHotkeyKeyDisplay,
    snippetPickerHotkeyModifiers,
  );
}

// ===========================================================================
// Section 14 — Window Positions
// ===========================================================================

class WindowPositionSettings {
  const WindowPositionSettings({
    this.floatingButtonX = -1.0,
    this.floatingButtonY = -1.0,
    this.floatingOverlayX = -1.0,
    this.floatingOverlayY = -1.0,
    this.windowX = -1.0,
    this.windowY = -1.0,
    this.windowWidth = 1100.0,
    this.windowHeight = 750.0,
    this.windowMaximized = false,
    this.overlayPositionsByMonitor = '',
  });

  /// Raw JSON `{monitorKey: [dx, dy]}`: the overlay position relative to each
  /// monitor it was dragged to. Decoded by `MonitorRelativePosition`.
  final String overlayPositionsByMonitor;

  final double floatingButtonX;
  final double floatingButtonY;
  final double floatingOverlayX;
  final double floatingOverlayY;
  final double windowX;
  final double windowY;
  final double windowWidth;
  final double windowHeight;
  final bool windowMaximized;

  static const WindowPositionSettings defaults = WindowPositionSettings();

  factory WindowPositionSettings.fromMap(
    Map<String, String> v,
  ) => WindowPositionSettings(
    floatingButtonX: _readDouble(
      v,
      'floating_button_x',
      defaults.floatingButtonX,
    ),
    floatingButtonY: _readDouble(
      v,
      'floating_button_y',
      defaults.floatingButtonY,
    ),
    floatingOverlayX: _readDouble(
      v,
      'floating_overlay_x',
      defaults.floatingOverlayX,
    ),
    floatingOverlayY: _readDouble(
      v,
      'floating_overlay_y',
      defaults.floatingOverlayY,
    ),
    windowX: _readDouble(v, 'window_x', defaults.windowX),
    windowY: _readDouble(v, 'window_y', defaults.windowY),
    windowWidth: _readDouble(v, 'window_width', defaults.windowWidth),
    windowHeight: _readDouble(v, 'window_height', defaults.windowHeight),
    windowMaximized: _readBool(v, 'window_maximized', defaults.windowMaximized),
    overlayPositionsByMonitor:
        v['overlay_positions_by_monitor'] ?? defaults.overlayPositionsByMonitor,
  );

  Map<String, String> toMap() => {
    'floating_button_x': '$floatingButtonX',
    'floating_button_y': '$floatingButtonY',
    'floating_overlay_x': '$floatingOverlayX',
    'floating_overlay_y': '$floatingOverlayY',
    'window_x': '$windowX',
    'window_y': '$windowY',
    'window_width': '$windowWidth',
    'window_height': '$windowHeight',
    'window_maximized': '$windowMaximized',
    'overlay_positions_by_monitor': overlayPositionsByMonitor,
  };

  WindowPositionSettings copyWith({
    double? floatingButtonX,
    double? floatingButtonY,
    double? floatingOverlayX,
    double? floatingOverlayY,
    double? windowX,
    double? windowY,
    double? windowWidth,
    double? windowHeight,
    bool? windowMaximized,
    String? overlayPositionsByMonitor,
  }) => WindowPositionSettings(
    floatingButtonX: floatingButtonX ?? this.floatingButtonX,
    floatingButtonY: floatingButtonY ?? this.floatingButtonY,
    floatingOverlayX: floatingOverlayX ?? this.floatingOverlayX,
    floatingOverlayY: floatingOverlayY ?? this.floatingOverlayY,
    windowX: windowX ?? this.windowX,
    windowY: windowY ?? this.windowY,
    windowWidth: windowWidth ?? this.windowWidth,
    windowHeight: windowHeight ?? this.windowHeight,
    windowMaximized: windowMaximized ?? this.windowMaximized,
    overlayPositionsByMonitor:
        overlayPositionsByMonitor ?? this.overlayPositionsByMonitor,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowPositionSettings &&
          floatingButtonX == other.floatingButtonX &&
          floatingButtonY == other.floatingButtonY &&
          floatingOverlayX == other.floatingOverlayX &&
          floatingOverlayY == other.floatingOverlayY &&
          windowX == other.windowX &&
          windowY == other.windowY &&
          windowWidth == other.windowWidth &&
          windowHeight == other.windowHeight &&
          windowMaximized == other.windowMaximized &&
          overlayPositionsByMonitor == other.overlayPositionsByMonitor;

  @override
  int get hashCode => Object.hash(
    floatingButtonX,
    floatingButtonY,
    floatingOverlayX,
    floatingOverlayY,
    windowX,
    windowY,
    windowWidth,
    windowHeight,
    windowMaximized,
    overlayPositionsByMonitor,
  );
}

// ===========================================================================
// Section 15 — Onboarding
// ===========================================================================

class OnboardingSettings {
  const OnboardingSettings({
    this.onboardingCompleted = false,
    this.autoPasteOffHintDismissed = false,
    this.onboardingCurrentStep = 0,
    this.onboardingFlowVersion = 0,
    this.onboardingContentVersion = 0,
    this.smartModeUsageHintShown = false,
    this.dataKeyExplained = false,
    this.inputMonitoringOffered = false,
    this.exactTriggerHintDismissed = false,
    this.userFirstName = '',
    this.userFirstNameSet = false,
    this.userRoles = '',
    this.userAttribution = '',
    this.aboutFollowUpDone = false,
    this.roleTermsDone = false,
    this.firstStepsArmed = false,
    this.firstStepsDismissed = false,
    this.firstStepsDone = '',
    this.completedInVersion = '',
  });

  final bool onboardingCompleted;

  /// The one-time hint in the replacements list that names the similar
  /// entries whose short triggers now match exactly (#204) was dismissed.
  final bool exactTriggerHintDismissed;

  /// Persistent dismiss of the "Auto-Paste deaktiviert" status-bar hint that
  /// appears after the user skips Auto-Paste during onboarding. When `true`,
  /// the chip is hidden permanently — even while Auto-Paste remains off.
  /// Re-enabling Auto-Paste in Settings makes the chip irrelevant regardless.
  final bool autoPasteOffHintDismissed;

  /// Index into the onboarding step sequence the user last reached.
  /// Persisted so a required app restart mid-onboarding (e.g. after
  /// granting the Auto-Paste permission) resumes where the user left off
  /// instead of restarting the whole flow from step 0.
  final int onboardingCurrentStep;

  /// Version of the onboarding step sequence [onboardingCurrentStep] indexes
  /// into. `0` = legacy 7/8-step flow (or a value written before this field
  /// existed — including fresh installations that never ran the new flow).
  /// `1` = current five-step flow. When the overlay hydrates a saved position
  /// with a version older than the current flow, it translates the index via
  /// `migrateLegacyOnboardingStepIndex` exactly once and then stamps the
  /// current version here so the translation can never run twice.
  final int onboardingFlowVersion;

  /// Last onboarding *content* revision this user was shown, distinct from
  /// [onboardingFlowVersion] (which tracks the step-sequence shape a saved
  /// resume position indexes into, not what content was seen). `0` means
  /// "never stamped" — either a fresh install (no revision has run yet) or
  /// a pre-existing installation that predates this field; both are
  /// grandfathered to the current target revision once onboarding is
  /// found complete, so no one is retroactively shown revisions that
  /// predate their install. The revision registry itself starts counting
  /// real entries at `1`; see `lib/core/onboarding/onboarding_revision.dart`.
  final int onboardingContentVersion;

  /// Whether the one-time, post-usage Smart Mode discovery hint has
  /// already been shown. Shown at most
  /// once, regardless of user action, to users who have not engaged with
  /// Smart Mode (standard preset still `off`) after their first completed
  /// recording — covers both onboarding-skippers and pre-existing users who
  /// onboarded before this feature shipped.
  final bool smartModeUsageHintShown;

  /// Whether this installation already explained the data key (#1071):
  /// what it protects, that it stays on the device and what declining
  /// means. The system key-store prompt only follows that explanation and a
  /// deliberate tap. Device-local, never exported.
  final bool dataKeyExplained;

  /// Whether this installation already offered the macOS Input Monitoring
  /// permission for a key combination (#807), after a recording kept running
  /// because the key's release did not arrive. Offered once; a decline or an
  /// ignored offer is not repeated. Device-local, never exported.
  final bool inputMonitoringOffered;

  /// First name from the "About you" page, used in later onboarding
  /// headings. Empty means no name. Stays on this device.
  final String userFirstName;

  /// Whether [userFirstName] was ever confirmed on the "About you" page.
  /// Until then the page prefills the name from the operating system; after
  /// it, a cleared name stays cleared.
  final bool userFirstNameSet;

  /// Comma-separated role ids from the "About you" page
  /// (`OnboardingRole.name`). Local only; the dictionary's one-time term
  /// suggestion reads it (`lib/features/dictionary/role_terms.dart`).
  final String userRoles;

  /// The "How did you find us?" answer (`OnboardingAttribution.name`), empty
  /// when unanswered. Local only, so going back shows the answer again.
  final String userAttribution;

  /// Whether the one-time follow-up card in the Übersicht's "Mitmachen"
  /// block, which asks again whoever answered "Keine Angabe", is finished:
  /// answered or dismissed. It never comes back after that.
  final bool aboutFollowUpDone;

  /// Whether the dictionary's one-time term suggestion for the roles in
  /// [userRoles] is finished: taken over or hidden. It never comes back.
  /// See `lib/features/dictionary/role_terms.dart`.
  final bool roleTermsDone;

  /// Set once the user finishes Onboarding v6 (the final "Start" action). The
  /// "Erste Schritte" card is only ever shown while this is `true`, so an
  /// existing install, which never passes that action again, never sees it.
  /// See `lib/core/first_steps/first_steps.dart`.
  final bool firstStepsArmed;

  /// The user closed the "Erste Schritte" card. Cleared by "Neu anzeigen" in
  /// Settings; [firstStepsDone] is kept either way.
  final bool firstStepsDismissed;

  /// Comma-separated ids of the first-steps items confirmed by app state or
  /// events (`FirstStepsItem.id`). Parsed at the point of use, never by a
  /// click on an item.
  final String firstStepsDone;

  /// The app version in which this install finished its first onboarding, or
  /// empty for installs that finished it before this was recorded. The
  /// Übersicht treats "new in this version" of that version as already seen:
  /// a fresh install has nothing to catch up on.
  final String completedInVersion;

  static const OnboardingSettings defaults = OnboardingSettings();

  factory OnboardingSettings.fromMap(Map<String, String> v) =>
      OnboardingSettings(
        onboardingCompleted: _readBool(
          v,
          'onboarding_completed',
          defaults.onboardingCompleted,
        ),
        autoPasteOffHintDismissed: _readBool(
          v,
          'auto_paste_off_hint_dismissed',
          defaults.autoPasteOffHintDismissed,
        ),
        exactTriggerHintDismissed: _readBool(
          v,
          'exact_trigger_hint_dismissed',
          defaults.exactTriggerHintDismissed,
        ),
        onboardingCurrentStep: _readInt(
          v,
          'onboarding_current_step',
          defaults.onboardingCurrentStep,
        ),
        onboardingFlowVersion: _readInt(
          v,
          'onboarding_flow_version',
          defaults.onboardingFlowVersion,
        ),
        onboardingContentVersion: _readInt(
          v,
          'onboarding_content_version',
          defaults.onboardingContentVersion,
        ),
        smartModeUsageHintShown: _readBool(
          v,
          'smart_mode_usage_hint_shown',
          defaults.smartModeUsageHintShown,
        ),
        dataKeyExplained: _readBool(
          v,
          'data_key_explained',
          defaults.dataKeyExplained,
        ),
        inputMonitoringOffered: _readBool(
          v,
          'input_monitoring_offered',
          defaults.inputMonitoringOffered,
        ),
        userFirstName: v['user_first_name'] ?? defaults.userFirstName,
        userFirstNameSet: _readBool(
          v,
          'user_first_name_set',
          defaults.userFirstNameSet,
        ),
        userRoles: v['user_roles'] ?? defaults.userRoles,
        userAttribution: v['user_attribution'] ?? defaults.userAttribution,
        aboutFollowUpDone: _readBool(
          v,
          'about_follow_up_done',
          defaults.aboutFollowUpDone,
        ),
        roleTermsDone: _readBool(v, 'role_terms_done', defaults.roleTermsDone),
        firstStepsArmed: _readBool(
          v,
          'first_steps_armed',
          defaults.firstStepsArmed,
        ),
        firstStepsDismissed: _readBool(
          v,
          'first_steps_dismissed',
          defaults.firstStepsDismissed,
        ),
        firstStepsDone: v['first_steps_done'] ?? defaults.firstStepsDone,
        completedInVersion:
            v['onboarding_completed_in_version'] ?? defaults.completedInVersion,
      );

  Map<String, String> toMap() => {
    'onboarding_completed': '$onboardingCompleted',
    'auto_paste_off_hint_dismissed': '$autoPasteOffHintDismissed',
    'exact_trigger_hint_dismissed': '$exactTriggerHintDismissed',
    'onboarding_current_step': '$onboardingCurrentStep',
    'onboarding_flow_version': '$onboardingFlowVersion',
    'onboarding_content_version': '$onboardingContentVersion',
    'smart_mode_usage_hint_shown': '$smartModeUsageHintShown',
    'data_key_explained': '$dataKeyExplained',
    'input_monitoring_offered': '$inputMonitoringOffered',
    'user_first_name': userFirstName,
    'user_first_name_set': '$userFirstNameSet',
    'user_roles': userRoles,
    'user_attribution': userAttribution,
    'about_follow_up_done': '$aboutFollowUpDone',
    'role_terms_done': '$roleTermsDone',
    'first_steps_armed': '$firstStepsArmed',
    'first_steps_dismissed': '$firstStepsDismissed',
    'first_steps_done': firstStepsDone,
    'onboarding_completed_in_version': completedInVersion,
  };

  OnboardingSettings copyWith({
    bool? onboardingCompleted,
    bool? autoPasteOffHintDismissed,
    bool? exactTriggerHintDismissed,
    int? onboardingCurrentStep,
    int? onboardingFlowVersion,
    int? onboardingContentVersion,
    bool? smartModeUsageHintShown,
    bool? dataKeyExplained,
    bool? inputMonitoringOffered,
    String? userFirstName,
    bool? userFirstNameSet,
    String? userRoles,
    String? userAttribution,
    bool? aboutFollowUpDone,
    bool? roleTermsDone,
    bool? firstStepsArmed,
    bool? firstStepsDismissed,
    String? firstStepsDone,
    String? completedInVersion,
  }) => OnboardingSettings(
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    autoPasteOffHintDismissed:
        autoPasteOffHintDismissed ?? this.autoPasteOffHintDismissed,
    exactTriggerHintDismissed:
        exactTriggerHintDismissed ?? this.exactTriggerHintDismissed,
    onboardingCurrentStep: onboardingCurrentStep ?? this.onboardingCurrentStep,
    onboardingFlowVersion: onboardingFlowVersion ?? this.onboardingFlowVersion,
    onboardingContentVersion:
        onboardingContentVersion ?? this.onboardingContentVersion,
    smartModeUsageHintShown:
        smartModeUsageHintShown ?? this.smartModeUsageHintShown,
    dataKeyExplained: dataKeyExplained ?? this.dataKeyExplained,
    inputMonitoringOffered:
        inputMonitoringOffered ?? this.inputMonitoringOffered,
    userFirstName: userFirstName ?? this.userFirstName,
    userFirstNameSet: userFirstNameSet ?? this.userFirstNameSet,
    userRoles: userRoles ?? this.userRoles,
    userAttribution: userAttribution ?? this.userAttribution,
    aboutFollowUpDone: aboutFollowUpDone ?? this.aboutFollowUpDone,
    roleTermsDone: roleTermsDone ?? this.roleTermsDone,
    firstStepsArmed: firstStepsArmed ?? this.firstStepsArmed,
    firstStepsDismissed: firstStepsDismissed ?? this.firstStepsDismissed,
    firstStepsDone: firstStepsDone ?? this.firstStepsDone,
    completedInVersion: completedInVersion ?? this.completedInVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnboardingSettings &&
          onboardingCompleted == other.onboardingCompleted &&
          autoPasteOffHintDismissed == other.autoPasteOffHintDismissed &&
          exactTriggerHintDismissed == other.exactTriggerHintDismissed &&
          onboardingCurrentStep == other.onboardingCurrentStep &&
          onboardingFlowVersion == other.onboardingFlowVersion &&
          onboardingContentVersion == other.onboardingContentVersion &&
          smartModeUsageHintShown == other.smartModeUsageHintShown &&
          dataKeyExplained == other.dataKeyExplained &&
          inputMonitoringOffered == other.inputMonitoringOffered &&
          userFirstName == other.userFirstName &&
          userFirstNameSet == other.userFirstNameSet &&
          userRoles == other.userRoles &&
          userAttribution == other.userAttribution &&
          aboutFollowUpDone == other.aboutFollowUpDone &&
          roleTermsDone == other.roleTermsDone &&
          firstStepsArmed == other.firstStepsArmed &&
          firstStepsDismissed == other.firstStepsDismissed &&
          firstStepsDone == other.firstStepsDone &&
          completedInVersion == other.completedInVersion;

  @override
  int get hashCode => Object.hash(
    onboardingCompleted,
    autoPasteOffHintDismissed,
    exactTriggerHintDismissed,
    onboardingCurrentStep,
    onboardingFlowVersion,
    onboardingContentVersion,
    smartModeUsageHintShown,
    dataKeyExplained,
    inputMonitoringOffered,
    userFirstName,
    userFirstNameSet,
    userRoles,
    userAttribution,
    aboutFollowUpDone,
    roleTermsDone,
    firstStepsArmed,
    firstStepsDismissed,
    firstStepsDone,
    completedInVersion,
  );
}

// ===========================================================================
// Section 16 — Benchmark
// ===========================================================================

class BenchmarkSettings {
  const BenchmarkSettings({
    this.tierBenchmarkRtf,
    this.benchmarkHardwareId,
    this.benchmarkTimestamp,
    this.benchmarkBackend,
  });

  /// Real-time factor (RTF) for each quality tier from last benchmark.
  /// RTF = processing_time / audio_duration. Lower is better.
  final Map<QualityTier, double>? tierBenchmarkRtf;

  /// Hardware ID (hash) that the benchmark was run on.
  final String? benchmarkHardwareId;

  /// When the benchmark was last run.
  final DateTime? benchmarkTimestamp;

  /// Compute backend the last measurement ran on (`cpu`, `metal`, `cuda`,
  /// `vulkan`). Persisted so the result can name its hardware path later.
  final String? benchmarkBackend;

  factory BenchmarkSettings.fromMap(Map<String, String> v) => BenchmarkSettings(
    tierBenchmarkRtf: _readBenchmarkRtf(v['tier_benchmark_rtf']),
    benchmarkHardwareId: v['benchmark_hardware_id'],
    benchmarkTimestamp: _readDateTime(v['benchmark_timestamp']),
    benchmarkBackend: v['benchmark_backend'],
  );

  Map<String, String> toMap() => {
    'tier_benchmark_rtf': _writeBenchmarkRtf(tierBenchmarkRtf),
    'benchmark_hardware_id': benchmarkHardwareId ?? '',
    'benchmark_timestamp': benchmarkTimestamp?.toIso8601String() ?? '',
    'benchmark_backend': benchmarkBackend ?? '',
  };

  BenchmarkSettings copyWith({
    Map<QualityTier, double>? tierBenchmarkRtf,
    String? benchmarkHardwareId,
    DateTime? benchmarkTimestamp,
    String? benchmarkBackend,
  }) => BenchmarkSettings(
    tierBenchmarkRtf: tierBenchmarkRtf ?? this.tierBenchmarkRtf,
    benchmarkHardwareId: benchmarkHardwareId ?? this.benchmarkHardwareId,
    benchmarkTimestamp: benchmarkTimestamp ?? this.benchmarkTimestamp,
    benchmarkBackend: benchmarkBackend ?? this.benchmarkBackend,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BenchmarkSettings &&
          tierBenchmarkRtf == other.tierBenchmarkRtf &&
          benchmarkHardwareId == other.benchmarkHardwareId &&
          benchmarkTimestamp == other.benchmarkTimestamp &&
          benchmarkBackend == other.benchmarkBackend;

  @override
  int get hashCode => Object.hash(
    tierBenchmarkRtf,
    benchmarkHardwareId,
    benchmarkTimestamp,
    benchmarkBackend,
  );
}

// ===========================================================================
// Section 17 — Privacy
// ===========================================================================

/// How long the audio of a failed transcription is kept for a retry when
/// audio retention is off, unless the user picked another stage: 24 hours,
/// the one default for the live path, the crash recovery and the queue.
const int kDefaultFailedAudioKeepDays = 1;

/// Default and selectable counts for retained, successfully saved recordings.
const int kDefaultRetainedAudioCount = 20;
const kRetainedAudioCountStages = [5, 10, 20, 50, 100];

class PrivacySettings {
  // Opt-out by design (PRD Säule D): anonymous, cookieless, self-hosted usage
  // stats default ON, with DSGVO Art. 6 (1) (f) as the legal basis. Consistent
  // with the default-on Sentry crash reporter; a discrete Datenschutz toggle
  // lets users opt out.
  //
  // retainRecentAudio defaults OFF, the opposite polarity — this is an
  // opt-in exception to the app's "no durable audio" default (internal-notes
  // §6.5), so the safe default keeps that principle intact until a user
  // deliberately turns it on.
  const PrivacySettings({
    this.shareUsageStats = true,
    this.retainRecentAudio = false,
    this.retainedAudioCount = kDefaultRetainedAudioCount,
    this.failedAudioKeepDays = kDefaultFailedAudioKeepDays,
    this.cohortPseudonymSalt,
  });

  final bool shareUsageStats;

  /// Keeps the WAV of each dictation (up to [retainedAudioCount]) in
  /// a persistent app-data directory instead of deleting it after
  /// transcription — for debugging and for restoring past dictations.
  final bool retainRecentAudio;

  /// Maximum retained recordings. Changes apply at the next cleanup.
  final int retainedAudioCount;

  /// Days the audio of a failed transcription is kept for a retry when
  /// [retainRecentAudio] is off. Applies to parked audio at the next sweep.
  final int failedAudioKeepDays;

  Duration get failedAudioKeepDuration => Duration(days: failedAudioKeepDays);

  /// Locally generated, never-transmitted random salt for the weekly-rotating
  /// cohort pseudonym sent to Matomo as `dimension7` (see `telemetry_service`
  /// `cohortPseudonymDimension`). Lazily created on first telemetry dispatch
  /// while [shareUsageStats] is true — hardware/install-bound like
  /// `benchmarkHardwareId`, so it is denylisted from settings export/import
  /// (`settingsPortabilityDenyList`).
  final String? cohortPseudonymSalt;

  static const PrivacySettings defaults = PrivacySettings();

  factory PrivacySettings.fromMap(Map<String, String> v) => PrivacySettings(
    shareUsageStats: _readBool(
      v,
      'share_usage_stats',
      defaults.shareUsageStats,
    ),
    retainRecentAudio: _readBool(
      v,
      'retain_recent_audio',
      defaults.retainRecentAudio,
    ),
    retainedAudioCount: _readInt(
      v,
      'retained_audio_count',
      kDefaultRetainedAudioCount,
    ).clamp(kRetainedAudioCountStages.first, kRetainedAudioCountStages.last),
    failedAudioKeepDays:
        _readInt(v, 'failed_audio_keep_days', defaults.failedAudioKeepDays) > 0
        ? _readInt(v, 'failed_audio_keep_days', defaults.failedAudioKeepDays)
        : defaults.failedAudioKeepDays,
    cohortPseudonymSalt: v['cohort_pseudonym_salt']?.isEmpty ?? true
        ? null
        : v['cohort_pseudonym_salt'],
  );

  Map<String, String> toMap() => {
    'share_usage_stats': '$shareUsageStats',
    'retain_recent_audio': '$retainRecentAudio',
    'retained_audio_count': '$retainedAudioCount',
    'failed_audio_keep_days': '$failedAudioKeepDays',
    'cohort_pseudonym_salt': cohortPseudonymSalt ?? '',
  };

  PrivacySettings copyWith({
    bool? shareUsageStats,
    bool? retainRecentAudio,
    int? retainedAudioCount,
    int? failedAudioKeepDays,
    String? cohortPseudonymSalt,
  }) => PrivacySettings(
    shareUsageStats: shareUsageStats ?? this.shareUsageStats,
    retainRecentAudio: retainRecentAudio ?? this.retainRecentAudio,
    retainedAudioCount: retainedAudioCount ?? this.retainedAudioCount,
    failedAudioKeepDays: failedAudioKeepDays ?? this.failedAudioKeepDays,
    cohortPseudonymSalt: cohortPseudonymSalt ?? this.cohortPseudonymSalt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacySettings &&
          shareUsageStats == other.shareUsageStats &&
          retainRecentAudio == other.retainRecentAudio &&
          retainedAudioCount == other.retainedAudioCount &&
          failedAudioKeepDays == other.failedAudioKeepDays &&
          cohortPseudonymSalt == other.cohortPseudonymSalt;

  @override
  int get hashCode => Object.hash(
    shareUsageStats,
    retainRecentAudio,
    retainedAudioCount,
    failedAudioKeepDays,
    cohortPseudonymSalt,
  );
}

// ===========================================================================
// Section 18 — Settings Portability Paths
// ===========================================================================

/// Remembered file-dialog target for the settings export/import feature
/// (PRD `settings-portability-vollumfang`, Tickets 03 + 04). Once the user
/// confirms a native save/open dialog (`file_selector`), the chosen path is
/// remembered here so every later export/import reuses it without asking
/// again — until the path turns out to be unusable (file/folder gone,
/// access denied), at which point `SettingsPortabilityController` clears it
/// and the dialog opens again automatically.
///
/// [exportPath] and [importPath] are deliberately separate keys: sharing one
/// key would make an export after an import silently overwrite the file the
/// import just read from.
///
/// [exportBookmark]/[importBookmark] hold the base64 macOS security-scoped
/// bookmark paired with each path (`SecureBookmarkService`, Ticket 04) — it
/// lets the Mac App Store sandbox re-grant access to a user-picked file
/// across app restarts, where the dialog's own grant is process-bound.
/// Always empty on Windows/Linux and on the macOS direct-download build.
class SettingsPortabilityPathSettings {
  const SettingsPortabilityPathSettings({
    this.exportPath = '',
    this.importPath = '',
    this.exportBookmark = '',
    this.importBookmark = '',
  });

  final String exportPath;
  final String importPath;
  final String exportBookmark;
  final String importBookmark;

  static const SettingsPortabilityPathSettings defaults =
      SettingsPortabilityPathSettings();

  factory SettingsPortabilityPathSettings.fromMap(
    Map<String, String> v,
  ) => SettingsPortabilityPathSettings(
    exportPath: v['settings_export_path'] ?? defaults.exportPath,
    importPath: v['settings_import_path'] ?? defaults.importPath,
    exportBookmark: v['settings_export_bookmark'] ?? defaults.exportBookmark,
    importBookmark: v['settings_import_bookmark'] ?? defaults.importBookmark,
  );

  Map<String, String> toMap() => {
    'settings_export_path': exportPath,
    'settings_import_path': importPath,
    'settings_export_bookmark': exportBookmark,
    'settings_import_bookmark': importBookmark,
  };

  SettingsPortabilityPathSettings copyWith({
    String? exportPath,
    String? importPath,
    String? exportBookmark,
    String? importBookmark,
  }) => SettingsPortabilityPathSettings(
    exportPath: exportPath ?? this.exportPath,
    importPath: importPath ?? this.importPath,
    exportBookmark: exportBookmark ?? this.exportBookmark,
    importBookmark: importBookmark ?? this.importBookmark,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsPortabilityPathSettings &&
          exportPath == other.exportPath &&
          importPath == other.importPath &&
          exportBookmark == other.exportBookmark &&
          importBookmark == other.importBookmark;

  @override
  int get hashCode =>
      Object.hash(exportPath, importPath, exportBookmark, importBookmark);
}

// ===========================================================================
// Section 19 — Settings Autosave
// ===========================================================================

/// Automatic, event-driven backup of the portable settings bundle
/// (Ticket 26 — decisions E11a–E11d).
///
/// Every key here is machine-bound or local run state, so all five are on
/// [settingsPortabilityDenyList]: the folder path and its bookmark describe
/// *where this installation writes*, and the two timestamps describe *what
/// happened on this machine*. Deny-listing them is also what keeps the
/// feature from feeding itself — the autosave trigger compares the
/// deny-list-filtered settings map, so writing [lastSuccess] back after a
/// run cannot look like a change worth backing up (see
/// `services/settings_autosave_service.dart`).
///
/// [folder] is deliberately a *directory* and deliberately not
/// `SettingsPortabilityPathSettings.exportPath`: the manual export writes one
/// file the user named, the automation rotates dated files of its own
/// (decision E11c=b). Sharing the one path would let a background run
/// overwrite a good hand-made backup with a broken one, or the reverse.
///
/// [enabled] defaults to `false` and stays false until the user both flips
/// the switch and confirms a folder — nobody inherits a background write job
/// on their disk from an app update.
class SettingsAutosaveSettings {
  const SettingsAutosaveSettings({
    this.enabled = false,
    this.folder = '',
    this.bookmark = '',
    this.lastSuccess = '',
    this.lastError = '',
  });

  /// Master switch. `false` unless the user turned it on *and* a folder was
  /// confirmed — the two are written in one update, never separately.
  final bool enabled;

  /// Absolute path of the rotation directory. `''` means "never chosen".
  final String folder;

  /// Base64 macOS security-scoped bookmark for [folder]
  /// (`SecureBookmarkService`). Always empty on Windows/Linux and on the
  /// macOS direct-download build. Without it the sandbox forgets the
  /// directory grant on restart — and unlike the manual flow, the autosave
  /// path may never re-ask with a dialog (H1), so an unresolvable bookmark
  /// simply ends the run.
  final String bookmark;

  /// ISO-8601 UTC timestamp of the last *successful* run, `''` if none.
  final String lastSuccess;

  /// ISO-8601 UTC timestamp of the last *failed* run, cleared back to `''`
  /// by the next success. Kept alongside [lastSuccess] rather than replacing
  /// it so the passive status line can stay honest across a restart: a
  /// failure after a success must not be able to render as "last backup
  /// 14:03" with nothing said about the failure (decision E11d).
  final String lastError;

  static const SettingsAutosaveSettings defaults = SettingsAutosaveSettings();

  factory SettingsAutosaveSettings.fromMap(Map<String, String> v) =>
      SettingsAutosaveSettings(
        enabled: _readBool(v, 'settings_autosave_enabled', defaults.enabled),
        folder: v['settings_autosave_folder'] ?? defaults.folder,
        bookmark: v['settings_autosave_bookmark'] ?? defaults.bookmark,
        lastSuccess:
            v['settings_autosave_last_success'] ?? defaults.lastSuccess,
        lastError: v['settings_autosave_last_error'] ?? defaults.lastError,
      );

  Map<String, String> toMap() => {
    'settings_autosave_enabled': '$enabled',
    'settings_autosave_folder': folder,
    'settings_autosave_bookmark': bookmark,
    'settings_autosave_last_success': lastSuccess,
    'settings_autosave_last_error': lastError,
  };

  SettingsAutosaveSettings copyWith({
    bool? enabled,
    String? folder,
    String? bookmark,
    String? lastSuccess,
    String? lastError,
  }) => SettingsAutosaveSettings(
    enabled: enabled ?? this.enabled,
    folder: folder ?? this.folder,
    bookmark: bookmark ?? this.bookmark,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    lastError: lastError ?? this.lastError,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAutosaveSettings &&
          enabled == other.enabled &&
          folder == other.folder &&
          bookmark == other.bookmark &&
          lastSuccess == other.lastSuccess &&
          lastError == other.lastError;

  @override
  int get hashCode =>
      Object.hash(enabled, folder, bookmark, lastSuccess, lastError);
}

// ===========================================================================
// Section 21 — Smart Mode
// ===========================================================================

/// Smart-Mode-v2 settings.
///
/// [standardPreset] is the only field ticket 01 needs — everything else the
/// feature will grow (target language in ticket 03, hotkey-preset in ticket
/// 04, local/cloud provider choice in ticket 06) is added by those tickets as
/// their own fields on this same section, not restructured in here.
class SmartModeSettings {
  const SmartModeSettings({
    this.standardPreset = 'off',
    this.targetLanguage = 'en',
    this.provider = 'local',
    this.customPresets = const [],
  });

  /// One of `off` / `cleanup` / `concise` / `translate`, or
  /// `custom:<id>` for one of [customPresets] (#891). Defaults to `off` —
  /// an update to an existing installation must not change dictation
  /// behavior until the user actively opts in (ADR-independent product
  /// requirement, ticket 01).
  final String standardPreset;

  /// Standard target language for the [translate] preset, as an ISO 639-1
  /// code. Applies to both live paths that can trigger Translate (the
  /// standard preset here, and the Smart-Mode hotkey added by ticket 04) —
  /// there is no per-invocation language picker (PRODUCT-SPEC §5, neither
  /// live path has a selection moment).
  ///
  /// Ticket 03's 18-sentence batch test validated both `de` (German) and
  /// `en` (English, 5 DE→EN cases) — the other five official target
  /// languages (es/fr/pt/zh/ru) are modeled here so the pipeline and this
  /// field are generic, but ticket 09 gates each one's UI visibility behind
  /// its own validation spike before it can actually be chosen. Defaults to
  /// `en`: translating into the language the user is already dictating in
  /// is a no-op for most users, so German cannot be the sensible default
  /// despite being validated too; harmless while `standardPreset` defaults
  /// to `off`.
  final String targetLanguage;

  /// Local-vs-cloud engine selection, as a [SmartModeProviderType.value].
  /// Strict either-or per ADR 0010 — never both at once, no per-preset mix.
  /// Defaults to `local`.
  final String provider;

  /// The user's own named presets (#891), each a name plus a free-text
  /// instruction. Selected through [standardPreset] as `custom:<id>`.
  final List<SmartModeCustomPreset> customPresets;

  /// The custom preset [standardPreset] points at, or null for a built-in
  /// preset or a `custom:` id that no longer exists (which then acts as
  /// `off`, like any other unknown value).
  SmartModeCustomPreset? get activeCustomPreset =>
      customPresetFor(standardPreset);

  /// The custom preset behind a `custom:<id>` [value], or null.
  SmartModeCustomPreset? customPresetFor(String value) {
    if (!value.startsWith(SmartModeCustomPreset.valuePrefix)) return null;
    final id = value.substring(SmartModeCustomPreset.valuePrefix.length);
    for (final preset in customPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static const SmartModeSettings defaults = SmartModeSettings();

  factory SmartModeSettings.fromMap(Map<String, String> v) => SmartModeSettings(
    standardPreset: v['smart_mode_standard_preset'] ?? defaults.standardPreset,
    targetLanguage: v['smart_mode_target_language'] ?? defaults.targetLanguage,
    provider: v['smart_mode_provider'] ?? defaults.provider,
    customPresets: SmartModeCustomPreset.listFromJson(
      v['smart_mode_custom_presets'],
    ),
  );

  Map<String, String> toMap() => {
    'smart_mode_standard_preset': standardPreset,
    'smart_mode_target_language': targetLanguage,
    'smart_mode_provider': provider,
    'smart_mode_custom_presets': SmartModeCustomPreset.listToJson(
      customPresets,
    ),
  };

  SmartModeSettings copyWith({
    String? standardPreset,
    String? targetLanguage,
    String? provider,
    List<SmartModeCustomPreset>? customPresets,
  }) => SmartModeSettings(
    standardPreset: standardPreset ?? this.standardPreset,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    provider: provider ?? this.provider,
    customPresets: customPresets ?? this.customPresets,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartModeSettings &&
          standardPreset == other.standardPreset &&
          targetLanguage == other.targetLanguage &&
          provider == other.provider &&
          listEquals(customPresets, other.customPresets);

  @override
  int get hashCode => Object.hash(
    standardPreset,
    targetLanguage,
    provider,
    Object.hashAll(customPresets),
  );
}

/// A named Smart Mode preset of the user's own (#891): a [name] shown in
/// Settings, overlay and dock, plus the free-text [instruction] the engine
/// follows. It runs with the same safety net as the built-in presets (fact
/// guard, loop check, raw-text fallback).
@immutable
class SmartModeCustomPreset {
  const SmartModeCustomPreset({
    required this.id,
    required this.name,
    required this.instruction,
  });

  /// Prefix of a [SmartModeSettings.standardPreset] value that selects a
  /// custom preset by [id].
  static const valuePrefix = 'custom:';

  /// Stable id, unique within the list; never shown.
  final String id;

  /// Display name the user chose.
  final String name;

  /// What the engine should do with the dictated text.
  final String instruction;

  /// The [SmartModeSettings.standardPreset] value selecting this preset.
  String get value => '$valuePrefix$id';

  /// Parses the stored JSON list; a missing or damaged value is an empty
  /// list, and entries without id or instruction are dropped.
  static List<SmartModeCustomPreset> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map &&
              item['id'] is String &&
              (item['id'] as String).isNotEmpty &&
              item['instruction'] is String)
            SmartModeCustomPreset(
              id: item['id'] as String,
              name: item['name'] is String ? item['name'] as String : '',
              instruction: item['instruction'] as String,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  static String listToJson(List<SmartModeCustomPreset> presets) => jsonEncode([
    for (final p in presets)
      {'id': p.id, 'name': p.name, 'instruction': p.instruction},
  ]);

  SmartModeCustomPreset copyWith({String? name, String? instruction}) =>
      SmartModeCustomPreset(
        id: id,
        name: name ?? this.name,
        instruction: instruction ?? this.instruction,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartModeCustomPreset &&
          id == other.id &&
          name == other.name &&
          instruction == other.instruction;

  @override
  int get hashCode => Object.hash(id, name, instruction);
}

/// Longest instruction a custom Smart Mode preset may be saved with (#1685),
/// counted in characters (graphemes, the unit the field's counter shows).
///
/// The same for the local model and for cloud/BYOK: a preset is stored apart
/// from the engine, and the engine is a global setting that can change at any
/// time, so a larger cloud limit would turn a saved preset invalid or worse
/// after a switch to local. 500 characters hold one task with a target format
/// and a constraint or two; small on-device models follow longer,
/// many-part instructions noticeably worse. Reasoning and sources: #1685.
///
/// Presets saved before the limit keep running unchanged and are never cut;
/// the edit dialog only refuses to *save* an over-long instruction.
const int kSmartModeCustomInstructionMaxChars = 500;

/// Characters of [instruction] as the save rule counts them: trimmed, in
/// graphemes.
int smartModeCustomInstructionLength(String instruction) =>
    instruction.trim().characters.length;

/// Whether the preset dialog may save [name] and [instruction]: both present
/// and the instruction no longer than [kSmartModeCustomInstructionMaxChars].
bool smartModeCustomPresetCanSave({
  required String name,
  required String instruction,
}) {
  if (name.trim().isEmpty) return false;
  final length = smartModeCustomInstructionLength(instruction);
  return length > 0 && length <= kSmartModeCustomInstructionMaxChars;
}

// ===========================================================================
// Section 21b — Smart-Mode hotkey
// ===========================================================================

/// Settings for the Smart-Mode hotkey (ticket 04) — a fourth, independently
/// configurable global hotkey. Unlike [QuickNoteHotkeySettings] and
/// [SnippetPickerHotkeySettings] it also carries a bound [smartModeHotkeyPreset]
/// (one of `cleanup`/`concise`/`translate` — never `off`, see ADR 0008: one
/// extra hotkey, not one per preset), applied regardless of the
/// [SmartModeSettings.standardPreset] the main hotkey uses.
class SmartModeHotkeySettings {
  const SmartModeHotkeySettings({
    this.smartModeHotkeyEnabled = false,
    this.smartModeHotkeyKey = 'M',
    this.smartModeHotkeyKeyDisplay = '',
    this.smartModeHotkeyModifiers = 'ctrl+shift',
    this.smartModeHotkeyPreset = 'cleanup',
    this.smartModeHotkeyTargetLanguage = 'en',
  });

  /// Off by default — an existing user must opt in, never gets a system-wide
  /// shortcut silently claimed by an update.
  final bool smartModeHotkeyEnabled;

  /// Canonical storage token for the non-modifier key, as consumed by
  /// `resolveKey` (see [HotkeySettings.hotkeyKey]).
  final String smartModeHotkeyKey;

  /// User-visible label for [smartModeHotkeyKey] (see
  /// [HotkeySettings.hotkeyKeyDisplay]).
  final String smartModeHotkeyKeyDisplay;

  final String smartModeHotkeyModifiers;

  /// The preset applied whenever this hotkey triggers a recording. One of
  /// `cleanup`/`concise`/`translate` — deliberately never `off` (a disabled
  /// hotkey is expressed via [smartModeHotkeyEnabled], not via this field).
  final String smartModeHotkeyPreset;

  /// Target language used when [smartModeHotkeyPreset] is `translate` —
  /// independent of [SmartModeSettings.targetLanguage] (the standard
  /// preset's own target language), since the two presets can run with
  /// different destination languages (e.g. a hotkey dedicated to
  /// translating into English while the standard preset stays off). One of
  /// [smartModeValidatedTargetLanguages]' codes; `en` default for the same
  /// no-self-translation reason as the standard preset's default.
  final String smartModeHotkeyTargetLanguage;

  static const SmartModeHotkeySettings defaults = SmartModeHotkeySettings();

  factory SmartModeHotkeySettings.fromMap(Map<String, String> v) =>
      SmartModeHotkeySettings(
        smartModeHotkeyEnabled: _readBool(
          v,
          'smart_mode_hotkey_enabled',
          defaults.smartModeHotkeyEnabled,
        ),
        smartModeHotkeyKey:
            v['smart_mode_hotkey_key'] ?? defaults.smartModeHotkeyKey,
        smartModeHotkeyKeyDisplay:
            v['smart_mode_hotkey_key_display'] ??
            defaults.smartModeHotkeyKeyDisplay,
        smartModeHotkeyModifiers:
            v['smart_mode_hotkey_modifiers'] ??
            buildDefaultSmartModeHotkeySettings().smartModeHotkeyModifiers,
        smartModeHotkeyPreset:
            v['smart_mode_hotkey_preset'] ?? defaults.smartModeHotkeyPreset,
        smartModeHotkeyTargetLanguage:
            v['smart_mode_hotkey_target_language'] ??
            defaults.smartModeHotkeyTargetLanguage,
      );

  Map<String, String> toMap() => {
    'smart_mode_hotkey_enabled': '$smartModeHotkeyEnabled',
    'smart_mode_hotkey_key': smartModeHotkeyKey,
    'smart_mode_hotkey_key_display': smartModeHotkeyKeyDisplay,
    'smart_mode_hotkey_modifiers': smartModeHotkeyModifiers,
    'smart_mode_hotkey_preset': smartModeHotkeyPreset,
    'smart_mode_hotkey_target_language': smartModeHotkeyTargetLanguage,
  };

  SmartModeHotkeySettings copyWith({
    bool? smartModeHotkeyEnabled,
    String? smartModeHotkeyKey,
    String? smartModeHotkeyKeyDisplay,
    String? smartModeHotkeyModifiers,
    String? smartModeHotkeyPreset,
    String? smartModeHotkeyTargetLanguage,
  }) => SmartModeHotkeySettings(
    smartModeHotkeyEnabled:
        smartModeHotkeyEnabled ?? this.smartModeHotkeyEnabled,
    smartModeHotkeyKey: smartModeHotkeyKey ?? this.smartModeHotkeyKey,
    smartModeHotkeyKeyDisplay:
        smartModeHotkeyKeyDisplay ?? this.smartModeHotkeyKeyDisplay,
    smartModeHotkeyModifiers:
        smartModeHotkeyModifiers ?? this.smartModeHotkeyModifiers,
    smartModeHotkeyPreset: smartModeHotkeyPreset ?? this.smartModeHotkeyPreset,
    smartModeHotkeyTargetLanguage:
        smartModeHotkeyTargetLanguage ?? this.smartModeHotkeyTargetLanguage,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartModeHotkeySettings &&
          smartModeHotkeyEnabled == other.smartModeHotkeyEnabled &&
          smartModeHotkeyKey == other.smartModeHotkeyKey &&
          smartModeHotkeyKeyDisplay == other.smartModeHotkeyKeyDisplay &&
          smartModeHotkeyModifiers == other.smartModeHotkeyModifiers &&
          smartModeHotkeyPreset == other.smartModeHotkeyPreset &&
          smartModeHotkeyTargetLanguage == other.smartModeHotkeyTargetLanguage;

  @override
  int get hashCode => Object.hash(
    smartModeHotkeyEnabled,
    smartModeHotkeyKey,
    smartModeHotkeyKeyDisplay,
    smartModeHotkeyModifiers,
    smartModeHotkeyPreset,
    smartModeHotkeyTargetLanguage,
  );
}

/// Settings for the "edit selection by voice" hotkey:
/// select text in any app, press it,
/// speak an instruction — the Smart Mode engine's result replaces the
/// selection. A fifth, independently configurable global hotkey, same shape
/// as [QuickNoteHotkeySettings].
class SelectionEditHotkeySettings {
  const SelectionEditHotkeySettings({
    this.selectionEditHotkeyEnabled = false,
    this.selectionEditHotkeyKey = 'Y',
    this.selectionEditHotkeyKeyDisplay = '',
    this.selectionEditHotkeyModifiers = 'ctrl+shift',
  });

  /// Off by default — an existing user must opt in, never gets a system-wide
  /// shortcut silently claimed by an update.
  final bool selectionEditHotkeyEnabled;

  /// Canonical storage token for the non-modifier key (see
  /// [HotkeySettings.hotkeyKey]).
  final String selectionEditHotkeyKey;

  /// User-visible label for [selectionEditHotkeyKey] (see
  /// [HotkeySettings.hotkeyKeyDisplay]).
  final String selectionEditHotkeyKeyDisplay;

  final String selectionEditHotkeyModifiers;

  static const SelectionEditHotkeySettings defaults =
      SelectionEditHotkeySettings();

  factory SelectionEditHotkeySettings.fromMap(
    Map<String, String> v,
  ) => SelectionEditHotkeySettings(
    selectionEditHotkeyEnabled: _readBool(
      v,
      'selection_edit_hotkey_enabled',
      defaults.selectionEditHotkeyEnabled,
    ),
    selectionEditHotkeyKey:
        v['selection_edit_hotkey_key'] ?? defaults.selectionEditHotkeyKey,
    selectionEditHotkeyKeyDisplay:
        v['selection_edit_hotkey_key_display'] ??
        defaults.selectionEditHotkeyKeyDisplay,
    selectionEditHotkeyModifiers:
        v['selection_edit_hotkey_modifiers'] ??
        buildDefaultSelectionEditHotkeySettings().selectionEditHotkeyModifiers,
  );

  Map<String, String> toMap() => {
    'selection_edit_hotkey_enabled': '$selectionEditHotkeyEnabled',
    'selection_edit_hotkey_key': selectionEditHotkeyKey,
    'selection_edit_hotkey_key_display': selectionEditHotkeyKeyDisplay,
    'selection_edit_hotkey_modifiers': selectionEditHotkeyModifiers,
  };

  SelectionEditHotkeySettings copyWith({
    bool? selectionEditHotkeyEnabled,
    String? selectionEditHotkeyKey,
    String? selectionEditHotkeyKeyDisplay,
    String? selectionEditHotkeyModifiers,
  }) => SelectionEditHotkeySettings(
    selectionEditHotkeyEnabled:
        selectionEditHotkeyEnabled ?? this.selectionEditHotkeyEnabled,
    selectionEditHotkeyKey:
        selectionEditHotkeyKey ?? this.selectionEditHotkeyKey,
    selectionEditHotkeyKeyDisplay:
        selectionEditHotkeyKeyDisplay ?? this.selectionEditHotkeyKeyDisplay,
    selectionEditHotkeyModifiers:
        selectionEditHotkeyModifiers ?? this.selectionEditHotkeyModifiers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionEditHotkeySettings &&
          selectionEditHotkeyEnabled == other.selectionEditHotkeyEnabled &&
          selectionEditHotkeyKey == other.selectionEditHotkeyKey &&
          selectionEditHotkeyKeyDisplay ==
              other.selectionEditHotkeyKeyDisplay &&
          selectionEditHotkeyModifiers == other.selectionEditHotkeyModifiers;

  @override
  int get hashCode => Object.hash(
    selectionEditHotkeyEnabled,
    selectionEditHotkeyKey,
    selectionEditHotkeyKeyDisplay,
    selectionEditHotkeyModifiers,
  );
}

// ===========================================================================
// Section 23 — Local Automation API
// ===========================================================================

/// Local automation API settings, including the custom port — a
/// loopback-only HTTP server power users can script dictation against.
///
/// The bearer token lives in secure storage (`wp_automation_api_token`, see
/// `lib/services/automation_api/automation_api_token_store.dart`), never in
/// this flat settings map — same separation `CloudProviderSettings` uses for
/// API keys. The *actually bound* port is runtime state (exposed by
/// `AutomationApiController`), not a persisted setting — only the user's
/// requested [customPort] is.
class AutomationApiSettings {
  const AutomationApiSettings({
    this.enabled = false,
    this.customPort,
    this.hooks = const [],
  });

  /// Whether the local automation API server should be running. Off by
  /// default — the ticket's first acceptance criterion.
  final bool enabled;

  /// User-chosen port to bind to; `null` (the default) means "automatic" —
  /// the server targets [kAutomationApiDefaultPort] and, on a bind
  /// failure, automatically tries a small range of alternates (see
  /// `AutomationApiController._start`).
  final int? customPort;

  /// Outbound event hooks (ticket / 8.3). Loopback-only; see
  /// `automation_hooks.dart`. Stored under the additive key
  /// `automation_hooks`.
  final List<AutomationHook> hooks;

  static const AutomationApiSettings defaults = AutomationApiSettings();

  factory AutomationApiSettings.fromMap(Map<String, String> v) =>
      AutomationApiSettings(
        enabled: _readBool(v, 'automation_api_enabled', defaults.enabled),
        customPort: _readNullableInt(v, 'automation_api_custom_port'),
        hooks: decodeAutomationHooks(v[kAutomationHooksSettingsKey]),
      );

  Map<String, String> toMap() => {
    'automation_api_enabled': '$enabled',
    'automation_api_custom_port': customPort?.toString() ?? '',
    kAutomationHooksSettingsKey: encodeAutomationHooks(hooks),
  };

  /// [customPort] defaults to the private [_unset] sentinel so
  /// `copyWith(customPort: null)` can explicitly clear it back to
  /// "automatic" — omitting the argument entirely leaves the current value
  /// untouched, the same distinction every other nullable field in this
  /// file cannot make (none of them are ever cleared once set).
  AutomationApiSettings copyWith({
    bool? enabled,
    Object? customPort = _unset,
    List<AutomationHook>? hooks,
  }) => AutomationApiSettings(
    enabled: enabled ?? this.enabled,
    customPort: identical(customPort, _unset)
        ? this.customPort
        : customPort as int?,
    hooks: hooks ?? this.hooks,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomationApiSettings &&
          enabled == other.enabled &&
          customPort == other.customPort &&
          _sameHooks(hooks, other.hooks);

  @override
  int get hashCode => Object.hash(enabled, customPort, Object.hashAll(hooks));

  static bool _sameHooks(List<AutomationHook> a, List<AutomationHook> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);
}

// ===========================================================================
// Platform-aware defaults factory
// ===========================================================================

/// Build a [HotkeySettings] with the platform-correct default modifier.
HotkeySettings buildDefaultHotkeySettings() => HotkeySettings(
  hotkeyModifiers: defaultTargetPlatform == TargetPlatform.macOS
      ? 'meta+shift'
      : 'ctrl+shift',
);

/// Build a [QuickNoteHotkeySettings] with the platform-correct default
/// modifier and pre-filled (but disabled) `Ctrl/Cmd+Shift+N` combination.
QuickNoteHotkeySettings buildDefaultQuickNoteHotkeySettings() =>
    QuickNoteHotkeySettings(
      quickNoteHotkeyModifiers: defaultTargetPlatform == TargetPlatform.macOS
          ? 'meta+shift'
          : 'ctrl+shift',
    );

/// Default modifiers of the "paste the last dictation again" hotkey:
/// Ctrl+Cmd on macOS, Alt+Shift elsewhere. Ctrl+Shift+V is taken by "paste
/// without formatting" in many apps, and Ctrl+Alt is AltGr on Windows.
String defaultRepasteHotkeyModifiers() =>
    defaultTargetPlatform == TargetPlatform.macOS ? 'ctrl+meta' : 'alt+shift';

/// Build a [SnippetPickerHotkeySettings] with the platform-correct default
/// modifier and pre-filled (but disabled) `Ctrl/Cmd+Shift+E` combination
/// (ticket 26).
SnippetPickerHotkeySettings buildDefaultSnippetPickerHotkeySettings() =>
    SnippetPickerHotkeySettings(
      snippetPickerHotkeyModifiers:
          defaultTargetPlatform == TargetPlatform.macOS
          ? 'meta+shift'
          : 'ctrl+shift',
    );

/// Build a [SmartModeHotkeySettings] with the platform-correct default
/// modifier and pre-filled (but disabled) `Ctrl/Cmd+Shift+M` combination
/// (ticket 04).
SmartModeHotkeySettings buildDefaultSmartModeHotkeySettings() =>
    SmartModeHotkeySettings(
      smartModeHotkeyModifiers: defaultTargetPlatform == TargetPlatform.macOS
          ? 'meta+shift'
          : 'ctrl+shift',
    );

SelectionEditHotkeySettings buildDefaultSelectionEditHotkeySettings() =>
    SelectionEditHotkeySettings(
      selectionEditHotkeyModifiers:
          defaultTargetPlatform == TargetPlatform.macOS
          ? 'meta+shift'
          : 'ctrl+shift',
    );

int? _portInRange(int? port) =>
    port != null && port >= 1024 && port <= 65535 ? port : null;
