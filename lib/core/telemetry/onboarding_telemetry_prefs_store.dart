/// [OnboardingTelemetryStore] in SharedPreferences: the onboarding events held
/// before the privacy choice survive a restart on this device (GR-033).
///
/// The copy holds only what the buffer holds (fixed category, action and
/// bucket names, a timestamp), never leaves the device and is removed as soon
/// as the choice is made. A factory reset clears it with every other key.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import 'onboarding_telemetry_buffer.dart';

/// SharedPreferences key of the held onboarding events.
const kHeldOnboardingTelemetryKey = 'onboarding_telemetry_held_v1';

final _log = AppLogger('OnboardingTelemetry');

final class SharedPrefsOnboardingTelemetryStore
    implements OnboardingTelemetryStore {
  SharedPrefsOnboardingTelemetryStore({
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  /// Writes run one after another, so a late save never overtakes a clear.
  Future<void> _queue = Future.value();

  void _enqueue(Future<void> Function(SharedPreferences prefs) write) {
    _queue = _queue.then((_) async {
      try {
        await write(await _prefs());
      } on Object catch (e) {
        _log.debug('held onboarding telemetry not stored: $e');
      }
    });
  }

  @override
  Future<List<BufferedTelemetryEvent>> load() async {
    try {
      await _queue;
      final raw = (await _prefs()).get(kHeldOnboardingTelemetryKey);
      return decodeHeldEvents(raw is String ? raw : null);
    } on Object catch (e) {
      _log.debug('held onboarding telemetry not read: $e');
      return const [];
    }
  }

  @override
  void save(List<BufferedTelemetryEvent> events) {
    final raw = encodeHeldEvents(events);
    _enqueue((prefs) => prefs.setString(kHeldOnboardingTelemetryKey, raw));
  }

  @override
  void clear() =>
      _enqueue((prefs) => prefs.remove(kHeldOnboardingTelemetryKey));
}
