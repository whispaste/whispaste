/// Microphone priority list and virtual-input exclusion (ticket, matrix 9.2).
///
/// Pure decision logic, no platform calls: [AudioService] enumerates the
/// devices once at start and hands the labels here. The explicit choice
/// always wins; the priority list only fills in when no explicit device is
/// present; virtual or loopback inputs are never picked automatically.
library;

/// Sentinel meaning "system default" — mirrors `AudioInputSettings.microphone`.
const _systemDefaultLabel = 'Default';

/// Lower-cased name fragments of virtual, loopback or monitor inputs. They
/// carry no microphone signal, so an automatic pick would record silence.
/// Explicit selection is not filtered: a user who picked one on purpose keeps it.
const _virtualInputFragments = <String>[
  'virtual',
  'loopback',
  'aggregate',
  'stereo mix',
  'monitor of',
  'blackhole',
  'soundflower',
  'vb-audio',
  // Windows "stereo mix" in the system languages of the app.
  'stereomix',
  'mixage stéréo',
  'mezcla estéreo',
  'missaggio stereo',
  'mixagem estéreo',
  'стерео микшер',
  '立体声混音',
];

/// Whether [label] names a virtual, loopback or monitor input.
bool isVirtualInputLabel(String label) {
  final lower = label.toLowerCase();
  return _virtualInputFragments.any(lower.contains);
}

/// Outcome of [resolveMicrophoneChoice].
class MicrophoneChoice {
  const MicrophoneChoice._(this.label, this.source);

  /// The device to open, or `null` for the system default input.
  final String? label;

  final MicrophoneChoiceSource source;

  static const systemDefault = MicrophoneChoice._(
    null,
    MicrophoneChoiceSource.systemDefault,
  );
}

/// Why a device was chosen. Used for logging and, later, for UI hints.
enum MicrophoneChoiceSource {
  /// The user's explicit selection was present and used.
  explicit,

  /// The selection was absent or "Default"; the first present entry of the
  /// priority list was used.
  priority,

  /// Nothing matched; the system default input is used.
  systemDefault,

  /// The chosen device is the built-in microphone and the lid is closed
  /// (#846): it delivers no signal, so the system default is used instead.
  lidClosedFallback,
}

/// Picks the input device for a recording start.
///
/// - [selected]: the explicit choice (`'Default'` or a device label).
/// - [priority]: ordered device labels, most preferred first.
/// - [available]: labels enumerated from the platform at this moment.
///
/// Order: explicit selection if present, then the first priority entry that
/// is present and not virtual, otherwise the system default.
///
/// With [lidClosed] (notebook lid shut, #846) the built-in microphone is
/// skipped everywhere: it has no signal, so an explicit choice of it yields
/// the system default (never forced by routing) and the priority list passes
/// over it. Other explicit choices are untouched.
MicrophoneChoice resolveMicrophoneChoice({
  required String selected,
  required List<String> priority,
  required List<String> available,
  bool lidClosed = false,
}) {
  bool blocked(String label) =>
      lidClosed && classifyMicrophone(label) == MicrophoneKind.builtIn;
  if (selected != _systemDefaultLabel && available.contains(selected)) {
    if (blocked(selected)) {
      return const MicrophoneChoice._(
        null,
        MicrophoneChoiceSource.lidClosedFallback,
      );
    }
    return MicrophoneChoice._(selected, MicrophoneChoiceSource.explicit);
  }
  for (final candidate in priority) {
    if (candidate.isEmpty || candidate == _systemDefaultLabel) continue;
    if (isVirtualInputLabel(candidate) || blocked(candidate)) continue;
    if (available.contains(candidate)) {
      return MicrophoneChoice._(candidate, MicrophoneChoiceSource.priority);
    }
  }
  return MicrophoneChoice.systemDefault;
}

/// What kind of input a device label stands for.
///
/// The `record` package hands over only an id and a label on every platform,
/// so the kind is read from the label (name heuristic, same on macOS, Windows
/// and Linux). A wrong guess only changes the order of a suggestion, never an
/// explicit choice.
enum MicrophoneKind {
  /// Cable or USB microphone / headset, or a known external brand.
  external,

  /// The computer's own microphone.
  builtIn,

  /// A name that says nothing about the kind (could be a headset). Ranked
  /// behind the built-in microphone: reliability before a lucky guess.
  unknown,

  /// Bluetooth headset or earbuds (narrow call codec, startup delay).
  bluetooth,

  /// A phone used as microphone (continuity, camera apps).
  phone,

  /// Loopback, aggregate or monitor input without a microphone signal.
  virtual,
}

const _externalFragments = <String>[
  'usb',
  'yeti',
  'rode',
  'shure',
  'focusrite',
  'scarlett',
  'audio-technica',
  'blue ',
  'samson',
  'hyperx',
  'razer',
  'line in',
  'line-in',
  'external',
  'extern',
];

const _bluetoothFragments = <String>[
  'airpods',
  'bluetooth',
  'bluez',
  'hands-free',
  'handsfree',
  'freisprech',
  'buds',
  'headset hf',
  // Hands-free profile names of the app's languages.
  'mains libres',
  'manos libres',
  'vivavoce',
  'viva-voce',
  'громкой связи',
  '免提',
];

const _phoneFragments = <String>[
  'iphone',
  'ipad',
  'android',
  'pixel',
  'galaxy',
  'continuity',
  'phone link',
  'your phone',
  'droidcam',
  'iriun',
];

const _builtInFragments = <String>[
  'built-in',
  'builtin',
  'internal',
  'integrated',
  'macbook',
  'eingebaut',
  'internes mikrofon',
  'microphone array',
  'mikrofonarray',
  // Windows "Microphone Array" and typical built-in names, other languages.
  // Not lab-verified (the labs run German only), taken from vendor and
  // driver INF strings, see internal-notes.
  'matrice de microphones',
  'matriz de micrófonos',
  'matriz de microfones',
  'array di microfoni',
  'массив микрофонов',
  '麦克风阵列',
  'micrófono integrado',
  'microphone intégré',
  'microfono integrato',
  'microfone integrado',
  'встроенный',
  '内置',
];

/// Classifies [label]. Order matters: virtual and phone devices never count
/// as built-in or external, and a Bluetooth name beats a "headset" name.
MicrophoneKind classifyMicrophone(String label) {
  final lower = label.toLowerCase();
  if (isVirtualInputLabel(label)) return MicrophoneKind.virtual;
  if (_phoneFragments.any(lower.contains)) return MicrophoneKind.phone;
  if (_bluetoothFragments.any(lower.contains)) return MicrophoneKind.bluetooth;
  if (_builtInFragments.any(lower.contains)) return MicrophoneKind.builtIn;
  if (_externalFragments.any(lower.contains)) return MicrophoneKind.external;
  return MicrophoneKind.unknown;
}

/// The devices of [available] that may be picked or suggested without the
/// user naming them, best first: cable/USB, built-in, unnamed kinds, Bluetooth last
/// (narrow call codec, startup delay); phone and virtual inputs never. The
/// platform order is kept inside one kind. With [lidClosed] the built-in
/// microphone is left out (no signal in clamshell mode, #846).
List<String> rankMicrophones(List<String> available, {bool lidClosed = false}) {
  int rank(MicrophoneKind k) => switch (k) {
    MicrophoneKind.external => 0,
    MicrophoneKind.builtIn => 1,
    MicrophoneKind.unknown => 2,
    MicrophoneKind.bluetooth => 3,
    MicrophoneKind.phone || MicrophoneKind.virtual => -1,
  };
  final seen = <String>{};
  final entries = <(int, int, String)>[];
  for (var i = 0; i < available.length; i++) {
    final label = available[i];
    if (label.isEmpty || label == _systemDefaultLabel || !seen.add(label)) {
      continue;
    }
    final kind = classifyMicrophone(label);
    if (lidClosed && kind == MicrophoneKind.builtIn) continue;
    final r = rank(kind);
    if (r >= 0) entries.add((r, i, label));
  }
  entries.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return [for (final e in entries) e.$3];
}

/// The device to offer when [silent] delivered only silence: the best ranked
/// device other than [silent], or `null` when there is none. A suggestion
/// only; the caller applies it after the user agreed, also when the user had
/// chosen [silent] explicitly. When [silent] is the system-default sentinel,
/// the silent device is unknown and the best ranked one could be that very
/// device, so nothing is suggested. macOS and Linux resolve the sentinel to
/// the real default device before calling this (#930).
String? suggestAlternativeMicrophone({
  required String silent,
  required List<String> available,
  bool lidClosed = false,
}) {
  if (silent == _systemDefaultLabel) return null;
  for (final label in rankMicrophones(available, lidClosed: lidClosed)) {
    if (label != silent) return label;
  }
  return null;
}

/// How long the device list may take for the suggestion to still be offered.
/// The error notice never waits for it; it is shown at once.
const micSuggestionGrace = Duration(milliseconds: 300);

/// Runs [lookup] and returns its result, or `null` when it fails or takes
/// longer than [grace]. Never throws: a missing suggestion must not cost the
/// user anything but the shortcut.
Future<String?> suggestWithinGrace(
  Future<String?> Function() lookup, {
  Duration grace = micSuggestionGrace,
}) async {
  try {
    return await lookup().timeout(grace, onTimeout: () => null);
  } on Exception {
    return null;
  }
}
