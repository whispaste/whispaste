/// Input-device enumeration that degrades quietly when the platform cannot
/// provide it.
///
/// On Linux the `record` package lists devices by running `pactl`
/// (PulseAudio/PipeWire). On a system without it the call throws a
/// [ProcessException]. That is an expected environment, not an error: the
/// app falls back to the system default microphone and says so once at info
/// level instead of logging a SEVERE error on every lookup.
library;

import 'dart:async';
import 'dart:io';

import 'package:record/record.dart' show InputDevice;

import '../../core/logging/app_logger.dart';

final _log = AppLogger('InputDeviceLookup');

bool _unavailableNoticeLogged = false;

/// How long a device listing may take before the recording starts with
/// the system default microphone (RE2-09). The listing runs in front of the
/// recording start whenever a microphone or a priority list is set; a
/// normal listing takes milliseconds, a stuck `pactl` or driver never ends.
const inputDeviceLookupTimeout = Duration(milliseconds: 1500);

/// The listing still running from an earlier lookup, if any. record_linux
/// starts a new `pactl` process for every call and never kills it, so a stuck
/// listing must not be joined by another one.
Future<List<InputDevice>>? _listingInFlight;

/// Runs [list] and returns its devices, or `null` when enumeration is
/// unavailable, takes longer than [timeout], or an earlier listing is still
/// stuck. A missing enumeration tool is logged once at info level; any other
/// failure is logged as a warning.
Future<List<InputDevice>?> lookupInputDevices(
  Future<List<InputDevice>> Function() list, {
  Duration timeout = inputDeviceLookupTimeout,
}) async {
  if (_listingInFlight != null) {
    _log.info(
      'Input device listing from an earlier start is still running; '
      'using the system default microphone',
    );
    return null;
  }
  final listing = Future.sync(list);
  _listingInFlight = listing;
  // Clears the marker when the listing ends, also after a timeout. The error
  // is handled by the await below; this branch only has to swallow it.
  unawaited(
    listing.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_listingInFlight, listing)) _listingInFlight = null;
    }),
  );
  try {
    return [for (final d in await listing.timeout(timeout)) _withUnquotedId(d)];
  } on TimeoutException {
    _log.warning(
      'Input device listing timed out after ${timeout.inMilliseconds} ms; '
      'using the system default microphone',
    );
    return null;
  } on ProcessException catch (e) {
    if (!_unavailableNoticeLogged) {
      _unavailableNoticeLogged = true;
      _log.info(
        'Input device listing not available (${e.executable} not found); '
        'using the system default microphone',
      );
    }
    return null;
  } on Exception catch (e) {
    _log.warning('Failed to enumerate input devices: $e');
    return null;
  }
}

/// record_linux reads `node.name = "wp_mic2"` from `pactl` with the quotes and
/// passes them to `parecord --device=` without a shell. PipeWire then finds no
/// such source and silently records the system default. Device ids on macOS
/// and Windows never come quoted, so the cleanup is harmless there.
InputDevice _withUnquotedId(InputDevice device) {
  final id = device.id;
  if (id.length < 2 || !id.startsWith('"') || !id.endsWith('"')) return device;
  return InputDevice(
    id: id.substring(1, id.length - 1),
    label: device.label,
    sampleRates: device.sampleRates,
  );
}

/// Settings dropdown labels: the system-default sentinel first, then every
/// named device. [devices] is `null` when enumeration was unavailable.
List<String> inputDeviceLabelsFrom(List<InputDevice>? devices) => [
  'Default',
  ...?devices?.where((d) => d.label.isNotEmpty).map((d) => d.label),
];

/// Resets the once-per-process notice flag and the stuck-listing marker.
/// Test-only.
void resetInputDeviceLookupNoticeForTest() {
  _unavailableNoticeLogged = false;
  _listingInFlight = null;
}
