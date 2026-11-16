/// Names what disturbs the hotkey right now (issue #775): macOS secure input
/// (a password field or an app that asked for it) and other apps' active
/// keyboard event taps with a high latency.
///
/// Read once per hotkey press, after the press was handed to the trigger
/// handler, so the hotkey path never waits for it. Notice only: WhisPaste
/// never touches the other app or its tap.
///
/// macOS only. Windows and Linux have no system flag for secure input and no
/// public list of other apps' keyboard hooks, so their hosts do not answer
/// `inputDisturbance` on `com.whispaste.modifier_monitor`; the probe reports
/// nothing there (allow-list in test/parity/platform_channel_parity_test.dart,
/// internal-notes §2.7).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import 'desktop_paste/desktop_paste_controller_interface.dart';
import 'paste/paste_result_notice.dart' show appNoticeL10n;
import 'paste/secure_input_notice.dart' show secureInputCause;
import 'system_attention_service.dart';
import 'tap_disabled_evidence.dart';

final _log = AppLogger('HotkeyDisturbance');

/// An average tap latency from which another app's keyboard tap counts as a
/// likely cause of hotkey dropouts. Ordinary taps answer in well under a
/// millisecond; 100 ms is already a noticeable delay on every key press.
const Duration kSlowKeyboardTapLatency = Duration(milliseconds: 100);

/// Secure input is named at most once in this window, so a user who keeps
/// dictating next to a password field is not told on every press.
const Duration kHotkeyDisturbanceRepeat = Duration(minutes: 30);

/// A slow tap that was announced before is announced again only when its
/// latency is at least this many times the one at the last announcement
/// (#915), or when the system switched an event tap off since.
const int kSlowTapWorseFactor = 2;

/// Preference key of the per-app slow-tap records (#915).
const String kSlowTapRecordsPrefKey = 'hotkey_slow_tap_records';

/// Another app's active (filtering) keyboard event tap, as the system lists
/// it. Listen-only taps cannot delay events and are left out natively.
class KeyboardTapInfo {
  const KeyboardTapInfo({
    required this.avgLatency,
    this.name,
    this.bundleId,
    this.pid,
  });

  final Duration avgLatency;
  final String? name;
  final String? bundleId;
  final int? pid;
}

/// One reading of the system state that can disturb the hotkey.
class InputDisturbance {
  const InputDisturbance({
    this.secureInput = false,
    this.holder,
    this.keyboardTaps = const [],
  });

  /// Nothing known (other platforms, a failed or missing native answer).
  static const none = InputDisturbance();

  final bool secureInput;

  /// The app holding secure input; null when the system does not name it
  /// (for example inside the Mac App Store sandbox).
  final SecureInputHolder? holder;

  final List<KeyboardTapInfo> keyboardTaps;

  /// Parses the native answer. Anything malformed reads as "nothing known".
  static InputDisturbance fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) return none;
    final holderRaw = raw['holder'];
    SecureInputHolder? holder;
    if (holderRaw is Map) {
      final name = holderRaw['name'];
      final bundleId = holderRaw['bundleId'];
      final pid = holderRaw['pid'];
      holder = SecureInputHolder(
        name: name is String && name.isNotEmpty ? name : null,
        bundleId: bundleId is String && bundleId.isNotEmpty ? bundleId : null,
        pid: pid is int ? pid : null,
      );
    }
    final taps = <KeyboardTapInfo>[];
    final tapsRaw = raw['keyboardTaps'];
    if (tapsRaw is List) {
      for (final tap in tapsRaw) {
        if (tap is! Map) continue;
        final latency = tap['avgLatencyUs'];
        if (latency is! num || latency < 0) continue;
        final name = tap['name'];
        final bundleId = tap['bundleId'];
        final pid = tap['pid'];
        taps.add(
          KeyboardTapInfo(
            avgLatency: Duration(microseconds: latency.round()),
            name: name is String && name.isNotEmpty ? name : null,
            bundleId: bundleId is String && bundleId.isNotEmpty
                ? bundleId
                : null,
            pid: pid is int ? pid : null,
          ),
        );
      }
    }
    return InputDisturbance(
      secureInput: raw['secureInput'] == true,
      holder: holder,
      keyboardTaps: taps,
    );
  }
}

enum HotkeyDisturbanceCause { secureInput, slowKeyboardTap }

/// The cause to name, and the app behind it when the system names one.
class HotkeyDisturbanceNotice {
  const HotkeyDisturbanceNotice(
    this.cause, {
    this.appName,
    this.bundleId,
    this.pid,
    this.latency,
  });

  final HotkeyDisturbanceCause cause;
  final String? appName;

  /// The holder's bundle id (secure input only): tells a macOS password
  /// prompt and Terminal apart from any other app for the wording (#1617).
  final String? bundleId;
  final int? pid;

  /// The measured average tap latency (slow tap only).
  final Duration? latency;

  /// Same cause and same app: the repeat gate treats these as one notice.
  String get key => '${cause.name}:${appName ?? ''}:${pid ?? ''}';
}

/// Which notice [reading] calls for, or null when nothing disturbs the
/// hotkey. Secure input wins: it is certain, a slow tap is only a likely
/// cause. Of several slow taps the slowest is named.
HotkeyDisturbanceNotice? hotkeyDisturbanceNotice(InputDisturbance reading) {
  if (reading.secureInput) {
    return HotkeyDisturbanceNotice(
      HotkeyDisturbanceCause.secureInput,
      appName: reading.holder?.name,
      bundleId: reading.holder?.bundleId,
      pid: reading.holder?.pid,
    );
  }
  final slowest = slowestKeyboardTap(reading);
  if (slowest == null) return null;
  return HotkeyDisturbanceNotice(
    HotkeyDisturbanceCause.slowKeyboardTap,
    appName: slowest.name ?? slowest.bundleId,
    pid: slowest.pid,
    latency: slowest.avgLatency,
  );
}

/// The log line for one reading of a slow tap: app, latency and whether the
/// notice was announced or held back. Written for every reading (#915), so a
/// support case can be traced. Counters only, never key data.
String slowTapLogLine(
  HotkeyDisturbanceNotice notice, {
  required bool announced,
}) {
  return 'Slow keyboard tap: app ${notice.appName ?? 'unknown'}'
      '${notice.pid == null ? '' : ' (pid ${notice.pid})'}, '
      'latency ${notice.latency?.inMilliseconds ?? '?'} ms, '
      '${announced ? 'announced' : 'not announced (known)'}';
}

/// What was known about one app's slow tap at its last announcement.
class SlowTapRecord {
  const SlowTapRecord({
    required this.latencyMs,
    required this.announcedAtMs,
    this.acknowledged = false,
  });

  final int latencyMs;
  final int announcedAtMs;

  /// The user closed the notice for this app (#1607): it never comes back for
  /// it, neither as toast nor as system notification. The calm hint in the
  /// hotkey settings and the log line stay.
  final bool acknowledged;
}

/// Per-app slow-tap records, kept across restarts in one JSON preference.
Map<String, SlowTapRecord> decodeSlowTapRecords(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final out = <String, SlowTapRecord>{};
    decoded.forEach((app, value) {
      if (app is! String || value is! Map) return;
      final ms = value['ms'];
      final at = value['at'];
      if (ms is int && at is int) {
        out[app] = SlowTapRecord(
          latencyMs: ms,
          announcedAtMs: at,
          acknowledged: value['ack'] == true,
        );
      }
    });
    return out;
  } on Object {
    return {};
  }
}

String encodeSlowTapRecords(Map<String, SlowTapRecord> records) => jsonEncode({
  for (final e in records.entries)
    e.key: {
      'ms': e.value.latencyMs,
      'at': e.value.announcedAtMs,
      if (e.value.acknowledged) 'ack': true,
    },
});

/// Notice title and body in the app language.
({String title, String body}) hotkeyDisturbanceText(
  L10n l10n,
  HotkeyDisturbanceNotice notice,
) {
  final app = notice.appName;
  return switch (notice.cause) {
    // What holds the keyboard and the way out first, in the same words as
    // the skipped-paste notice (a macOS password prompt is answered or
    // closed, never quit, #1617), then what it does to the hotkey.
    HotkeyDisturbanceCause.secureInput => (
      title: l10n.hotkeyDisturbanceSecureInputTitle,
      body: [
        secureInputCause(
          l10n,
          SecureInputHolder(name: app, bundleId: notice.bundleId),
        ),
        l10n.hotkeyDisturbanceSecureInputEffect,
      ].join(' '),
    ),
    HotkeyDisturbanceCause.slowKeyboardTap => (
      title: l10n.hotkeyDisturbanceSlowTapTitle,
      body: app == null
          ? l10n.hotkeyDisturbanceSlowTapGeneric
          : l10n.hotkeyDisturbanceSlowTapNamed(app),
    ),
  };
}

/// Decides which notices pass. Secure input: once per
/// [kHotkeyDisturbanceRepeat] per app (in memory). A slow tap (#915): once
/// per app, kept across restarts; again only when the system switched a tap
/// off since, or the latency is at least [kSlowTapWorseFactor] times the one
/// at the last announcement. Never again once the user closed the notice for
/// that app ([acknowledge], #1607).
class HotkeyDisturbanceGate {
  HotkeyDisturbanceGate({
    DateTime Function()? clock,
    this._loadRecords,
    this._saveRecords,
    TapDisabledEvidence? evidence,
  }) : _clock = clock ?? DateTime.now,
       _evidence = evidence ?? tapDisabledEvidence;

  final DateTime Function() _clock;
  final Future<String?> Function()? _loadRecords;
  final void Function(String json)? _saveRecords;
  final TapDisabledEvidence _evidence;
  final Map<String, DateTime> _shown = {};
  Map<String, SlowTapRecord> _records = {};
  Future<void>? _loaded;

  /// Loads the persisted records once. Call before [allow] for a slow tap.
  Future<void> load() => _loaded ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      _records = decodeSlowTapRecords(await _loadRecords?.call());
    } on Object catch (e) {
      _log.debug('Slow-tap records unavailable', e);
    }
  }

  /// The app a slow-tap record is kept under (not the pid, which changes).
  static String? appKey(HotkeyDisturbanceNotice notice) =>
      notice.appName == null || notice.appName!.isEmpty ? null : notice.appName;

  bool allow(HotkeyDisturbanceNotice notice) {
    final now = _clock();
    if (notice.cause == HotkeyDisturbanceCause.slowKeyboardTap) {
      return _allowSlowTap(notice, now);
    }
    final last = _shown[notice.key];
    if (last != null && now.difference(last) < kHotkeyDisturbanceRepeat) {
      return false;
    }
    _shown[notice.key] = now;
    return true;
  }

  bool _allowSlowTap(HotkeyDisturbanceNotice notice, DateTime now) {
    final app = appKey(notice) ?? '';
    final ms = notice.latency?.inMilliseconds ?? 0;
    final record = _records[app];
    if (record != null && record.acknowledged) return false;
    final disabledAt = _evidence.lastAt;
    final announce =
        record == null ||
        (disabledAt != null &&
            disabledAt.millisecondsSinceEpoch > record.announcedAtMs) ||
        ms >= record.latencyMs * kSlowTapWorseFactor;
    if (!announce) return false;
    _records[app] = SlowTapRecord(
      latencyMs: ms,
      announcedAtMs: now.millisecondsSinceEpoch,
    );
    _saveRecords?.call(encodeSlowTapRecords(_records));
    return true;
  }

  /// The user closed (or followed) the slow-tap notice for this app: it is
  /// taken note of and stays silent for this app from now on, across
  /// restarts. Secure input is not acknowledged: it blocks the hotkey for
  /// certain and ends with the password field, so it keeps its 30 min repeat.
  Future<void> acknowledge(HotkeyDisturbanceNotice notice) async {
    if (notice.cause != HotkeyDisturbanceCause.slowKeyboardTap) return;
    await load();
    final app = appKey(notice) ?? '';
    final record = _records[app];
    if (record != null && record.acknowledged) return;
    _records[app] = SlowTapRecord(
      latencyMs: record?.latencyMs ?? notice.latency?.inMilliseconds ?? 0,
      announcedAtMs: record?.announcedAtMs ?? _clock().millisecondsSinceEpoch,
      acknowledged: true,
    );
    _saveRecords?.call(encodeSlowTapRecords(_records));
  }
}

/// Reads the state from the macOS modifier host. Every failure reads as
/// [InputDisturbance.none]: a missing answer must never become a notice.
///
/// The answer is awaited for one second at most. That deadline is a [Timer]
/// of its own, cancelled when the answer arrives or when [cancelled] completes
/// (the owning provider is disposed), so a widget tree that goes away never
/// leaves it pending.
Future<InputDisturbance> readInputDisturbance({
  MethodChannel channel = const MethodChannel('com.whispaste.modifier_monitor'),
  Future<void>? cancelled,
}) async {
  final done = Completer<InputDisturbance>();
  final deadline = Timer(const Duration(seconds: 1), () {
    if (!done.isCompleted) done.complete(InputDisturbance.none);
  });
  unawaited(
    cancelled?.then((_) {
      if (!done.isCompleted) done.complete(InputDisturbance.none);
    }),
  );
  unawaited(() async {
    try {
      final raw = await channel.invokeMapMethod<Object?, Object?>(
        'inputDisturbance',
      );
      if (!done.isCompleted) done.complete(InputDisturbance.fromMap(raw));
    } on MissingPluginException {
      if (!done.isCompleted) done.complete(InputDisturbance.none);
    } on Object catch (e) {
      _log.debug('Input disturbance unavailable', e);
      if (!done.isCompleted) done.complete(InputDisturbance.none);
    }
  }());
  try {
    return await done.future;
  } finally {
    deadline.cancel();
  }
}

/// Checks after a hotkey press and names the cause once (see the library
/// comment). Busy while a check runs, so a burst of presses reads once.
class HotkeyDisturbanceWatcher {
  HotkeyDisturbanceWatcher({
    required this._read,
    required this._notify,
    HotkeyDisturbanceGate? gate,
  }) : _gate = gate ?? HotkeyDisturbanceGate();

  final Future<InputDisturbance> Function() _read;
  final void Function(HotkeyDisturbanceNotice notice) _notify;
  final HotkeyDisturbanceGate _gate;
  bool _busy = false;

  /// The user closed the notice: see [HotkeyDisturbanceGate.acknowledge].
  Future<void> acknowledge(HotkeyDisturbanceNotice notice) =>
      _gate.acknowledge(notice);

  Future<void> onHotkeyPressed() async {
    if (_busy) return;
    _busy = true;
    try {
      final notice = hotkeyDisturbanceNotice(await _read());
      if (notice == null) return;
      await _gate.load();
      final allowed = _gate.allow(notice);
      if (notice.cause == HotkeyDisturbanceCause.slowKeyboardTap) {
        _log.info(slowTapLogLine(notice, announced: allowed));
      } else if (allowed) {
        _log.info(
          'Hotkey disturbance: ${notice.cause.name}, '
          'app ${notice.appName ?? 'unknown'}'
          '${notice.pid == null ? '' : ' (pid ${notice.pid})'}',
        );
      }
      if (allowed) _notify(notice);
    } finally {
      _busy = false;
    }
  }
}

/// The latest notice that passed the repeat gate. The app shell listens and
/// shows the in-app toast next to the system notification (#831), so the
/// cause is visible even when system notifications are off. No own setting.
class HotkeyDisturbanceNoticeNotifier
    extends Notifier<HotkeyDisturbanceNotice?> {
  @override
  HotkeyDisturbanceNotice? build() => null;

  void publish(HotkeyDisturbanceNotice notice) => state = notice;
}

final hotkeyDisturbanceNoticeProvider =
    NotifierProvider<HotkeyDisturbanceNoticeNotifier, HotkeyDisturbanceNotice?>(
      HotkeyDisturbanceNoticeNotifier.new,
    );

/// One watcher per process, on macOS only; null elsewhere.
final hotkeyDisturbanceWatcherProvider = Provider<HotkeyDisturbanceWatcher?>((
  ref,
) {
  if (!Platform.isMacOS) return null;
  final disposed = Completer<void>();
  ref.onDispose(disposed.complete);
  return HotkeyDisturbanceWatcher(
    read: () => readInputDisturbance(cancelled: disposed.future),
    gate: HotkeyDisturbanceGate(
      loadRecords: () async => (await SharedPreferences.getInstance())
          .getString(kSlowTapRecordsPrefKey),
      saveRecords: (json) => unawaited(
        SharedPreferences.getInstance()
            .then((p) => p.setString(kSlowTapRecordsPrefKey, json))
            .catchError((Object e) {
              _log.debug('Slow-tap records not saved', e);
              return false;
            }),
      ),
    ),
    notify: (notice) {
      ref.read(hotkeyDisturbanceNoticeProvider.notifier).publish(notice);
      final l10n = appNoticeL10n(ref.read(settingsProvider).value?.locale);
      final text = hotkeyDisturbanceText(l10n, notice);
      unawaited(
        ref
            .read(systemAttentionServiceProvider)
            .requestAttention(
              kind: AttentionKind.hotkeyDisturbed,
              title: text.title,
              body: text.body,
            ),
      );
    },
  );
});

/// The slowest other-app keyboard tap right now, read fresh when a page that
/// shows the calm hint opens (#915). Null off macOS or when none is slow.
/// Notice only, no toast.
final slowKeyboardTapNowProvider = FutureProvider.autoDispose<KeyboardTapInfo?>(
  (ref) async {
    if (!Platform.isMacOS) return null;
    final disposed = Completer<void>();
    ref.onDispose(disposed.complete);
    return slowestKeyboardTap(
      await readInputDisturbance(cancelled: disposed.future),
    );
  },
);

/// The slowest tap at or above [kSlowKeyboardTapLatency], or null.
KeyboardTapInfo? slowestKeyboardTap(InputDisturbance reading) {
  KeyboardTapInfo? slowest;
  for (final tap in reading.keyboardTaps) {
    if (tap.avgLatency < kSlowKeyboardTapLatency) continue;
    if (slowest == null || tap.avgLatency > slowest.avgLatency) slowest = tap;
  }
  return slowest;
}
