/// App profiles (WP-33a): a named set of dictation settings that applies while
/// a matching target app is in front at recording start.
///
/// A profile never inserts or sends anything on its own. It only changes how
/// one recording is refined (Smart Mode choice), which ASR language is used,
/// and which optional context source may be read. Everything is opt-in: no
/// profile means today's behaviour.
library;

import '../smart_mode/smart_mode_presets.dart';
import 'app_profile_consent.dart';
import 'app_profile_context_source.dart';

export 'app_profile_context_source.dart';

/// Fallbacks for unknown stored values (DEV-240):
///   - an unknown or missing Smart Mode value becomes [AppProfileSmartMode.standard]
///     (the global preset), never `off`;
///   - an unknown or missing context source becomes [AppProfileContextSource.none]
///     (nothing is read).
/// Both maps below are generated from the enum values, so the stored form and
/// the parser cannot drift apart.
String? normalizeAppIdentifier(String? raw) {
  if (raw == null) return null;
  var key = raw.trim().toLowerCase();
  // DEV-237: a trailing `.exe` is dropped on both sides, so `chrome` matches
  // `Chrome.EXE`. Bundle ids and WM_CLASS values never end in `.exe`.
  const exeSuffix = '.exe';
  if (key.endsWith(exeSuffix)) {
    key = key.substring(0, key.length - exeSuffix.length).trim();
  }
  return key.isEmpty ? null : key;
}

/// The Smart Mode choice of a profile. [standard] keeps the global preset;
/// the others force one preset for the recording (or force it off).
enum AppProfileSmartMode {
  standard('standard', null),
  off('off', SmartModePreset.off),
  cleanup('cleanup', SmartModePreset.cleanup),
  concise('concise', SmartModePreset.concise),
  translate('translate', SmartModePreset.translate);

  const AppProfileSmartMode(this.storageValue, this.preset);

  /// Value persisted in `app_profiles.smart_mode`.
  final String storageValue;

  /// The preset this choice forces, or `null` for [standard].
  final SmartModePreset? preset;

  static final Map<String, AppProfileSmartMode> _byStorageValue = {
    for (final value in values) value.storageValue: value,
  };

  /// Parses a stored value. Unknown or missing values fall back to
  /// [standard], never to [off].
  static AppProfileSmartMode fromStorage(String? value) =>
      _byStorageValue[value] ?? standard;
}

/// One way a profile is recognised as the active app.
///
/// [identifier] is the bundle id / exe name / WM_CLASS the name check compares.
/// [teamId] is the macOS code-signing team identifier. It is used on macOS
/// only, where clipboard context needs it (GS-067): a rule without a team id
/// can never unlock clipboard context there. Windows and Linux rely on the
/// name check alone.
class AppMatchRule {
  const AppMatchRule({required this.identifier, this.teamId});

  final String identifier;

  /// macOS code-signing team identifier, or `null` when not recorded.
  final String? teamId;

  /// Normalised name key, or `null` when the identifier is blank.
  String? get matchKey => normalizeAppIdentifier(identifier);

  @override
  bool operator ==(Object other) =>
      other is AppMatchRule &&
      other.identifier == identifier &&
      other.teamId == teamId;

  @override
  int get hashCode => Object.hash(identifier, teamId);
}

/// One profile. Immutable; the editor builds a new instance on every save.
class AppProfile {
  const AppProfile({
    required this.id,
    required this.name,
    this.rules = const [],
    this.smartMode = AppProfileSmartMode.standard,
    this.asrLanguage,
    this.modelId,
    this.contextSource = AppProfileContextSource.none,
    this.consent,
    this.hotkeyKey,
    this.hotkeyModifiers,
    this.afterTranscription,
    this.microphone,
  });

  /// Stable id (also the manual-override key).
  final String id;

  /// User-facing name, shown in the dock quick menu.
  final String name;

  /// Matching rules in stored order. Empty = manual selection only.
  final List<AppMatchRule> rules;

  final AppProfileSmartMode smartMode;

  /// ASR language code (e.g. `de`). `null` keeps the configured language.
  final String? asrLanguage;

  /// Optional transcription model override. Stored for the schema contract;
  /// not applied by WP-33a (see the WP-33a report).
  final String? modelId;

  final AppProfileContextSource contextSource;

  /// The user's recorded consent for [contextSource]. Required when the Smart
  /// Mode provider is a cloud provider; see [AppProfileConsent.covers].
  final AppProfileConsent? consent;

  /// Hotkey that switches to this profile, in the settings' storage format
  /// (`hotkeyKey` label, `hotkeyModifiers` such as `ctrl+shift`). Both null
  /// when the profile has no hotkey.
  final String? hotkeyKey;
  final String? hotkeyModifiers;

  /// The after-transcription action this profile sets, as its storage value.
  /// Null keeps the current action.
  final String? afterTranscription;

  /// The microphone this profile sets (the audio input name, or the default
  /// sentinel). Null keeps the current microphone.
  final String? microphone;

  /// Whether a hotkey is set (both parts are needed to register one).
  bool get hasHotkey => (hotkeyKey ?? '').isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! AppProfile) return false;
    if (other.rules.length != rules.length) return false;
    for (var i = 0; i < rules.length; i++) {
      if (other.rules[i] != rules[i]) return false;
    }
    return other.id == id &&
        other.name == name &&
        other.smartMode == smartMode &&
        other.asrLanguage == asrLanguage &&
        other.modelId == modelId &&
        other.contextSource == contextSource &&
        other.consent == consent &&
        other.hotkeyKey == hotkeyKey &&
        other.hotkeyModifiers == hotkeyModifiers &&
        other.afterTranscription == afterTranscription &&
        other.microphone == microphone;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(rules),
    smartMode,
    asrLanguage,
    modelId,
    contextSource,
    consent,
    hotkeyKey,
    hotkeyModifiers,
    afterTranscription,
    microphone,
  );
}

/// Match keys this profile claims that another profile already claims too
/// (GS-067 / DEV-239: the editor refuses duplicates across profiles, so
/// the resolver's first-match order is never the only safeguard). Also reports
/// a key repeated inside this profile.
Set<String> duplicateMatchKeys(AppProfile profile, List<AppProfile> all) {
  final own = <String>{};
  final repeated = <String>{};
  for (final rule in profile.rules) {
    final key = rule.matchKey;
    if (key == null) continue;
    if (!own.add(key)) repeated.add(key);
  }
  final claimedElsewhere = <String>{
    for (final other in all)
      if (other.id != profile.id)
        for (final rule in other.rules) ?rule.matchKey,
  };
  return {...repeated, ...own.where(claimedElsewhere.contains)};
}
