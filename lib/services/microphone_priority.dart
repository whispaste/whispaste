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
}

/// Picks the input device for a recording start.
///
/// - [selected]: the explicit choice (`'Default'` or a device label).
/// - [priority]: ordered device labels, most preferred first.
/// - [available]: labels enumerated from the platform at this moment.
///
/// Order: explicit selection if present, then the first priority entry that
/// is present and not virtual, otherwise the system default.
MicrophoneChoice resolveMicrophoneChoice({
  required String selected,
  required List<String> priority,
  required List<String> available,
}) {
  if (selected != _systemDefaultLabel && available.contains(selected)) {
    return MicrophoneChoice._(selected, MicrophoneChoiceSource.explicit);
  }
  for (final candidate in priority) {
    if (candidate.isEmpty || candidate == _systemDefaultLabel) continue;
    if (isVirtualInputLabel(candidate)) continue;
    if (available.contains(candidate)) {
      return MicrophoneChoice._(candidate, MicrophoneChoiceSource.priority);
    }
  }
  return MicrophoneChoice.systemDefault;
}
